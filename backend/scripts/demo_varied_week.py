"""Auditable demo history, Nov 17–23 2026. Dry-run unless --apply; never emits PDFs/SUNAT."""
import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_CEILING
import hashlib
import gzip
import json
import os
from pathlib import Path
import random
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
from app import create_app
from app.core.extensions import db
from app.modules.inventarios.operativo import reporte
from app.modules.salon.salon_payments import consumos
from app.modules.recepciones.invoices import calcular_factura
from scripts.demo_sheraton_four_months import rows, scalar, bulk
from scripts.demo_sheraton_inventory import serial, digest, LIMA
from sqlalchemy import text
from flask import current_app

START, END = date(2026, 11, 17), date(2026, 11, 23)
TAG = 'DEMO-SEMANA-VARIADA-20261117-23-V1'
DAYS = [START + timedelta(days=n) for n in range(7)]
Q = Decimal('.001')


def configure_period(start, end):
    """Select one to seven historical days; retain the original week's audit tag."""
    global START, END, DAYS, TAG
    if end < start or (end-start).days > 6:
        raise ValueError('Selecciona entre uno y siete días consecutivos.')
    START, END = start, end
    DAYS = [start + timedelta(days=n) for n in range((end-start).days+1)]
    TAG = ('DEMO-SEMANA-VARIADA-20261117-23-V1' if (start,end)==(date(2026,11,17),date(2026,11,23))
           else f'DEMO-OPERACION-VARIADA-{start:%Y%m%d}-{end:%Y%m%d}-V1')


def schedule(local, day, menu):
    seed = int(day.strftime('%Y%m%d')) * 31 + local
    rng = random.Random(seed)
    count = 12 + (local * 3 + day.day * 7) % 8 + (6 if day.weekday() in (4, 5) else 0)
    tickets = []
    for slot in range(count):
        chosen = rng.sample(menu, min(len(menu), rng.randint(2, 5)))
        lines = [{**m, 'cantidad': rng.choices([1, 2, 3, 4], [6, 4, 2, 1])[0],
                  'opciones': [], 'id_promocion': None, 'selecciones_promocion': []} for m in chosen]
        tickets.append({'lineas': lines, 'total': sum(l['precio'] * l['cantidad'] for l in lines),
                        'metodo': 'TARJETA' if (slot + local + day.day) % 10 < 6 else 'EFECTIVO',
                        'mesa': f'M{1 + slot % 12:02}', 'slot': slot})
    return tickets


def deliveries(usage, opening, buffers):
    groups = [DAYS[n:n+3] for n in range(0,len(DAYS),3)]
    result = {days[0]: {} for days in groups}
    for pid, buffer in buffers.items():
        extra = max(Decimal(0), -opening.get(pid, Decimal(0)))
        first_part = (buffer / 2).quantize(Q)
        second_part = (buffer / 3).quantize(Q)
        portions = ([buffer] if len(groups)==1 else [first_part,buffer-first_part] if len(groups)==2
                    else [first_part, second_part, buffer - first_part - second_part])
        for index, days in enumerate(groups):
            quantity = sum((usage.get(day, {}).get(pid, Decimal(0)) for day in days), Decimal(0))
            quantity += portions[index] + (extra if index == 0 else 0)
            result[days[0]][pid] = quantity.quantize(Q, rounding=ROUND_CEILING)
    return result


def inspect(local_ids=None, close_stale=False):
    if END >= datetime.now(LIMA).date():
        raise RuntimeError('El histórico solo admite fechas anteriores a hoy.')
    if db.engine.url.host not in ('localhost', '127.0.0.1', '::1') and os.getenv('RAILWAY_ENVIRONMENT_NAME') != 'production':
        raise RuntimeError('Base de destino no autorizada.')
    locals_ = rows('SELECT id_local,nombre FROM local WHERE estado_registro=1 ORDER BY id_local')
    if local_ids:
        locals_ = [l for l in locals_ if l['id_local'] in local_ids]
    products = rows('SELECT * FROM producto WHERE activo ORDER BY id_producto')
    menu, omitted = [], []
    for m in rows('''SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,pv.precio
      FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
      WHERE pv.activo AND ic.activo AND pv.precio>0 AND NOT EXISTS
      (SELECT 1 FROM grupo_salsa gs WHERE gs.activo AND gs.id_presentacion_venta=pv.id_presentacion_venta) ORDER BY 1'''):
        try:
            used = consumos([{**m, 'cantidad': 1, 'opciones': [], 'id_promocion': None, 'selecciones_promocion': []}])
            if used and set(used) <= {p['id_producto'] for p in products} and all(q > 0 for q in used.values()):
                menu.append(m)
            else:
                omitted.append(m['id_presentacion'])
        except (ValueError, KeyError):
            omitted.append(m['id_presentacion'])
    if len(menu) < 5:
        raise RuntimeError('Recetas válidas insuficientes.')
    plan = []
    for local in locals_:
        identity = local['id_local']
        done = scalar("SELECT count(*) FROM actividad_usuario WHERE accion='CARGAR_DEMO' AND descripcion=:tag AND id_local=:l", tag=TAG, l=identity)
        busy = scalar("SELECT count(*) FROM salon_pedido_actual WHERE id_local=:l AND estado='ENVIADO'", l=identity)
        rounds = scalar('SELECT count(*) FROM inventario_ronda WHERE id_local=:l AND cerrado_en IS NULL', l=identity)
        closed = rows('''SELECT fecha,reporte FROM inventario_jornada WHERE id_local=:l
          AND fecha BETWEEN :s AND :e AND cerrado_en IS NOT NULL''', l=identity, s=START, e=END)
        non_demo = [r['fecha'] for r in closed if not str((r['reporte'] or {}).get('prueba', '')).startswith('DEMO-')]
        real_closures = scalar('SELECT count(*) FROM salon_cierre_diario WHERE id_local=:l AND fecha BETWEEN :s AND :e AND NOT simulacion', l=identity, s=START, e=END)
        old_open = scalar('SELECT count(*) FROM inventario_jornada WHERE id_local=:l AND fecha<:s AND cerrado_en IS NULL', l=identity, s=START)
        future_closed = scalar('SELECT count(*) FROM inventario_jornada WHERE id_local=:l AND fecha>:e AND cerrado_en IS NOT NULL', l=identity, e=END)
        reason = 'ya_aplicado' if done else 'pedidos_sin_cobrar' if busy else 'conteo_abierto' if rounds else 'jornada_anterior_abierta' if old_open and not close_stale else 'cierre_posterior_protegido' if future_closed else 'cierre_operativo_protegido' if non_demo or real_closures else None
        plan.append({**local, 'omitir': reason, 'cobros_nuevos': sum(len(schedule(identity, day, menu)) for day in DAYS) if not reason else 0})
    return products, menu, plan, omitted


def event_time(journal, floor, moment):
    db.session.execute(text('UPDATE inventario_evento SET registrado_en=:t WHERE id_jornada=:j AND id_evento>:f'), {'t': moment, 'j': journal, 'f': floor})


def movement(local, user, day, journal, code, amounts, reason, moment):
    floor = scalar('SELECT coalesce(max(id_evento),0) FROM inventario_evento')
    identity = scalar('''INSERT INTO movimiento_inventario(codigo,tipo_movimiento,motivo_movimiento,
      fecha_movimiento,usuario_registro,id_local,observacion,registrado_en)
      VALUES(:c,'SALIDA',:reason,:d,:u,:l,:note,:t) RETURNING id_movimiento_inventario''',
      c=code, reason=reason, d=day, u=user, l=local, note=TAG, t=moment.replace(tzinfo=None))
    bulk('INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:m,:p,:q)',
         [dict(m=identity, p=pid, q=q) for pid, q in amounts.items() if q > 0])
    event_time(journal, floor, moment)
    return identity


def receipt(local, user, day, journal, quantities, products):
    order = scalar('''INSERT INTO orden_compra(codigo,estado_orden_compra,usuario_registro,fecha_registro,id_local)
      VALUES(:c,'ENVIADA',:u,:d,:l) RETURNING id_orden_compra''', c=f'SV{local}-{day:%y%m%d}', u=user, d=day, l=local)
    groups = defaultdict(list)
    for pid, quantity in quantities.items():
        if quantity > 0:
            groups[products[pid]['id_proveedor']].append((pid, quantity))
    for supplier, items in groups.items():
        bulk('''INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada,id_proveedor)
          VALUES(:o,:p,:q,:v)''', [dict(o=order, p=p, q=q, v=supplier) for p, q in items])
        invoice = calcular_factura({'fecha_emision': day.isoformat(), 'moneda': 'PEN', 'lineas': [
            {'id_producto': p, 'cantidad_facturada': float(q), 'precio_unitario': round(3 + (p % 23) * 1.15, 2),
             'descuento': 0, 'afectacion_igv': 'GRAVADO', 'igv_porcentaje': 18} for p, q in items]})
        invoice['prueba'] = TAG
        supplier_row = rows('SELECT nombre,datos_comerciales FROM proveedor WHERE id_proveedor=:p',p=supplier)[0]
        invoice['proveedor'] = {'id_proveedor':supplier,'nombre':supplier_row['nombre'], **(supplier_row['datos_comerciales'] or {})}
        floor = scalar('SELECT coalesce(max(id_evento),0) FROM inventario_evento')
        rid = scalar('''INSERT INTO factura_recepcion(id_orden_compra,id_proveedor,numero_factura,fecha_recepcion,usuario_recepcion,datos_factura)
          VALUES(:o,:v,:c,:d,:u,CAST(:data AS jsonb)) RETURNING id_factura_recepcion''',
          o=order, v=supplier, c=f'SV{local}-{day:%y%m%d}-{supplier}', d=day, u=user, data=json.dumps(serial(invoice)))
        bulk('INSERT INTO factura_recepcion_detalle(id_factura_recepcion,id_producto,cantidad_recibida) VALUES(:r,:p,:q)',
             [dict(r=rid, p=p, q=q) for p, q in items])
        event_time(journal, floor, datetime.combine(day, datetime.min.time(), LIMA) + timedelta(hours=11))
        db.session.execute(text('UPDATE factura_recepcion SET entregas=CAST(:ent AS jsonb) WHERE id_factura_recepcion=:r'),
          {'r': rid, 'ent': json.dumps(serial([{'fecha_recepcion': day.isoformat(), 'usuario_recepcion': user,
             'productos': [{'id_producto': p, 'cantidad_recibida': q} for p, q in items]}]))})
    db.session.execute(text("UPDATE orden_compra SET estado_orden_compra='RECEPCIONADA' WHERE id_orden_compra=:o"), {'o': order})
    db.session.execute(text('''INSERT INTO orden_compra_estado_historial(id_orden_compra,estado_anterior,estado_nuevo,motivo,usuario_modificacion,fecha_modificacion)
      VALUES(:o,'ENVIADA','RECEPCIONADA',:note,:u,:d)'''), {'o': order, 'note': TAG, 'u': user, 'd': datetime.combine(day, datetime.min.time()) + timedelta(hours=11)})


def sale(local, name, user, day, journal, ticket):
    slot = ticket['slot']
    moment = datetime.combine(day, datetime.min.time(), LIMA) + timedelta(hours=12, minutes=(slot * 37 + local * 11) % 630)
    key = str(uuid.uuid5(uuid.NAMESPACE_URL, f'{TAG}:{local}:{day}:{slot}'))
    hashed = hashlib.sha256(key.encode()).hexdigest()
    pid = scalar('''INSERT INTO salon_pedido(id_local,mesa,id_usuario,creado_en,envio_clave,envio_hash)
      VALUES(:l,:mesa,:u,:t,CAST(:k AS uuid),:h) RETURNING id_pedido''', l=local, mesa=ticket['mesa'], u=user, t=moment, k=key, h=hashed)
    for position, line in enumerate(ticket['lineas']):
        lid = scalar('''INSERT INTO salon_pedido_linea(id_pedido,posicion,id_presentacion,nombre,precio,cantidad,comentario,opciones)
          VALUES(:p,:pos,:id_presentacion,:nombre,:precio,:cantidad,:note,'[]'::jsonb) RETURNING id_linea''', p=pid, pos=position, note=TAG, **line)
        line.update(ids_lineas=[lid], enviada=True, comentario=TAG)
    db.session.execute(text("UPDATE salon_pedido SET estado='ENVIADO',enviado_en=:t WHERE id_pedido=:p"), {'t': moment, 'p': pid})
    move = movement(local, user, day, journal, f'SV{local}{day:%y%m%d}V{slot:02}', ticket['consumo'], 'VENTA_SALON', moment)
    kind = 'FACTURA' if slot % 11 == 0 else 'BOLETA_ELECTRONICA' if slot % 4 == 0 else 'BOLETA'
    document = f'2099{local:02}{day.day:02}{slot:03}' if kind == 'FACTURA' else f'99{local:02}{day.day:02}{slot:02}' if kind == 'BOLETA_ELECTRONICA' else ''
    customer = f'Cliente de prueba {local}-{day.day}-{slot}' if document else ''
    snapshot = serial(dict(tipo=kind, metodo=ticket['metodo'], documento=document, cliente=customer, local=name,
      mesa=ticket['mesa'], total=ticket['total'], fiscal=False, lineas=ticket['lineas'], prueba=TAG))
    paid = scalar('''INSERT INTO salon_cobro(id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,documento,cliente,total,comprobante,id_movimiento,creado_en)
      VALUES(:l,:u,:mesa,CAST(:k AS uuid),:h,:kind,:method,:doc,:customer,:total,CAST(:snap AS jsonb),:m,:t) RETURNING id_cobro''',
      l=local, u=user, mesa=ticket['mesa'], k=key, h=hashed, kind=kind, method=ticket['metodo'], doc=document,
      customer=customer, total=ticket['total'], snap=json.dumps(snapshot), m=move, t=moment)
    db.session.execute(text('INSERT INTO salon_cobro_pedido VALUES(:p,:c)'), {'p': pid, 'c': paid})


def verify(local):
    journals = rows('SELECT fecha,reporte,cerrado_en FROM inventario_jornada WHERE id_local=:l AND fecha BETWEEN :s AND :e ORDER BY fecha', l=local, s=START, e=END)
    if len(journals) != len(DAYS) or any(j['cerrado_en'] is None for j in journals):
        raise RuntimeError('El período no tiene todas sus jornadas cerradas.')
    previous = None
    for journal in journals:
        inventory = journal['reporte']['inventario']
        for item in inventory:
            numbers = {key: Decimal(str(item[key])) for key in ('inicial','entradas','salidas','final')}
            if abs(numbers['inicial'] + numbers['entradas'] - numbers['salidas'] - numbers['final']) > Q:
                raise RuntimeError('El inventario diario no concilia.')
            if previous and abs(numbers['inicial'] - previous[item['id_producto']]) > Q:
                raise RuntimeError('La apertura no coincide con el cierre anterior.')
        previous = {item['id_producto']: Decimal(str(item['final'])) for item in inventory}
    invalid = scalar('''SELECT count(*) FROM salon_cobro c WHERE c.id_local=:l
      AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :s AND :e
      AND c.comprobante->>'prueba'=:tag AND c.total IS DISTINCT FROM
      (SELECT sum((line->>'precio')::numeric*(line->>'cantidad')::numeric)
       FROM jsonb_array_elements(c.comprobante->'lineas') line)''', l=local,s=START,e=END,tag=TAG)
    if invalid: raise RuntimeError('Un ticket no coincide con sus líneas.')
    invalid = scalar('''SELECT count(*) FROM salon_cierre_diario d CROSS JOIN LATERAL
      (SELECT count(*) cantidad,coalesce(sum(c.total) FILTER(WHERE c.metodo='EFECTIVO'),0) efectivo,coalesce(sum(c.total) FILTER(WHERE c.metodo='TARJETA'),0) tarjeta
       FROM salon_cobro c WHERE c.id_local=d.id_local AND (c.creado_en AT TIME ZONE 'America/Lima')::date=d.fecha AND c.comprobante->'anulacion' IS NULL) actual
      WHERE d.id_local=:l AND d.fecha BETWEEN :s AND :e AND
      (d.cantidad,d.efectivo,d.tarjeta) IS DISTINCT FROM (actual.cantidad,actual.efectivo,actual.tarjeta)''', l=local,s=START,e=END)
    if invalid: raise RuntimeError('El cierre de caja no coincide con las ventas.')
    future = {r['id_producto']:r['cantidad'] for r in rows("SELECT id_producto,sum(cantidad) cantidad FROM inventario_evento WHERE id_local=:l AND (registrado_en AT TIME ZONE 'America/Lima')::date>:e GROUP BY id_producto", l=local,e=END)}
    for stock in rows('SELECT id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=:l',l=local):
        if stock['id_producto'] in previous and abs(stock['stock_actual'] - previous[stock['id_producto']] - future.get(stock['id_producto'],Decimal(0))) > Q:
            raise RuntimeError(f'El saldo histórico no concilia: local {local}, producto {stock["id_producto"]}, actual {stock["stock_actual"]}, cierre {previous[stock["id_producto"]]}, posterior {future.get(stock["id_producto"],Decimal(0))}.')
    return True


def backup_sources(local_ids):
    source = {}
    for table in ('inventario_jornada','inventario_evento','salon_cobro','salon_cierre_diario'):
        source[table] = rows(f'SELECT * FROM {table} WHERE id_local=ANY(:ids) ORDER BY 1',ids=local_ids)
    source['inventario_jornada_inicio'] = rows('SELECT i.* FROM inventario_jornada_inicio i JOIN inventario_jornada j USING(id_jornada) WHERE j.id_local=ANY(:ids) ORDER BY 1,2',ids=local_ids)
    source['maximos_antes'] = {table: scalar(f'SELECT coalesce(max({column}),0) FROM {table}') for table,column in (
      ('salon_cobro','id_cobro'),('salon_pedido','id_pedido'),('orden_compra','id_orden_compra'),
      ('factura_recepcion','id_factura_recepcion'),('movimiento_inventario','id_movimiento_inventario'),('inventario_ronda','id_ronda'))}
    folder = Path(current_app.instance_path)/'history_backups'
    folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    target = folder/(TAG+'-'+uuid.uuid4().hex+'.json.gz')
    payload = gzip.compress(json.dumps(serial(source),ensure_ascii=False).encode('utf-8'))
    with target.open('xb') as destination: destination.write(payload)
    if os.name != 'nt': target.chmod(0o600)
    return {'archivo':str(target),'sha256':hashlib.sha256(payload).hexdigest(),'bytes':len(payload)}


def apply(local_ids=None, close_stale=False, backup=False):
    db.session.execute(text("SET LOCAL lock_timeout='10s'"))
    db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:tag))"), {'tag': TAG})
    db.session.execute(text('''LOCK TABLE inventario_jornada,inventario_jornada_inicio,inventario_evento,
      inventario_ronda,inventario_conteo,inventario_conteo_historial,salon_pedido,salon_pedido_linea,salon_cobro,
      salon_cobro_pedido,movimiento_inventario,movimiento_inventario_detalle,orden_compra,orden_compra_detalle,
      factura_recepcion,factura_recepcion_detalle,salon_cierre_diario IN SHARE ROW EXCLUSIVE MODE'''))
    products, menu, plan, omitted = inspect(local_ids, close_stale)
    snapshot = backup_sources([local['id_local'] for local in plan if not local['omitir']]) if backup else None
    pmap = {p['id_producto']: p for p in products}
    results = []
    jobs_before = scalar('SELECT count(*) FROM fact_api_operacion')
    for local in plan:
        identity = local['id_local']
        if local['omitir']:
            results.append(local); continue
        db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext('inventario-dia:'||CAST(:l AS text)))"), {'l': identity})
        user = scalar('''SELECT min(u.id_usuario) FROM usuario u JOIN usuario_perfiles up USING(id_usuario)
          WHERE u.estado_registro=1 AND up.estado_registro=1 AND (up.id_perfil=1 OR
            (up.id_perfil IN (2,3) AND EXISTS(SELECT 1 FROM usuario_local ul WHERE ul.id_usuario=u.id_usuario AND ul.id_local=:l AND ul.estado_registro=1)))''', l=identity)
        if user is None:
            raise RuntimeError('No hay responsable autorizado para la sede.')
        manual_before = rows("SELECT * FROM salon_cobro WHERE id_local=:l AND coalesce(comprobante->>'prueba','') NOT LIKE 'DEMO-%' ORDER BY id_cobro", l=identity)
        journals = {r['fecha']: r for r in rows('SELECT * FROM inventario_jornada WHERE id_local=:l ORDER BY fecha', l=identity)}
        future = [j for d, j in journals.items() if d > END and j['cerrado_en'] is not None]
        if future:
            raise RuntimeError('Hay cierres posteriores; no se reescribe su saldo.')
        current = {r['id_producto']: r['stock_actual'] for r in rows('SELECT id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=:l', l=identity)}
        after_start = {r['id_producto']: r['cantidad'] for r in rows("SELECT id_producto,sum(cantidad) cantidad FROM inventario_evento WHERE id_local=:l AND (registrado_en AT TIME ZONE 'America/Lima')::date>=:s GROUP BY id_producto", l=identity, s=START)}
        opening = {p: current.get(p, Decimal(0)) - after_start.get(p, Decimal(0)) for p in pmap}
        historical_outflow = defaultdict(dict)
        for entry in rows("""SELECT (registrado_en AT TIME ZONE 'America/Lima')::date fecha,id_producto,sum(cantidad) cantidad
          FROM inventario_evento WHERE id_local=:l AND (registrado_en AT TIME ZONE 'America/Lima')::date BETWEEN :s AND :e
          GROUP BY fecha,id_producto""", l=identity,s=START,e=END):
            historical_outflow[entry['fecha']][entry['id_producto']] = max(Decimal(0),-entry['cantidad'])
        tickets, usage, waste = {}, {}, {}
        for day in DAYS:
            tickets[day] = schedule(identity, day, menu)
            totals = defaultdict(Decimal)
            for ticket in tickets[day]:
                ticket['consumo'] = {p: q.quantize(Q) for p, q in consumos(ticket['lineas']).items()}
                for p, q in ticket['consumo'].items(): totals[p] += q
            waste[day] = {p['id_producto']: (Decimal(1) if p['unidad']=='C62' else Decimal('.025') * (1 + p['id_producto'] % 3))
                          for p in products if (p['id_producto'] + day.day + identity) % 29 == 0}
            for p, q in waste[day].items(): totals[p] += q
            for p, q in historical_outflow[day].items(): totals[p] += q
            usage[day] = dict(totals)
        buffers = {p['id_producto']: max(Decimal(12 if p['unidad']=='C62' else 5), p['stock_minimo'] * Decimal('1.5')).quantize(Q) for p in products}
        incoming = deliveries(usage, opening, buffers)
        # Park a currently open day while triggers attach each backdated operation to its own day.
        for journal in journals.values():
            if journal['cerrado_en'] is None:
                db.session.execute(text("UPDATE inventario_jornada SET cerrado_en=abierto_en,reporte='{}'::jsonb WHERE id_jornada=:j"), {'j': journal['id_jornada']})
        future_open = next((j for d, j in journals.items() if d > END and j['cerrado_en'] is None), None)
        later_operations = scalar("""SELECT
          (SELECT count(*) FROM inventario_evento WHERE id_local=:l AND (registrado_en AT TIME ZONE 'America/Lima')::date>:e)
          +(SELECT count(*) FROM salon_cobro WHERE id_local=:l AND (creado_en AT TIME ZONE 'America/Lima')::date>:e)""", l=identity,e=END)
        if later_operations and future_open is None:
            today = datetime.now(LIMA).date()
            jid = scalar("INSERT INTO inventario_jornada(id_local,fecha,abierto_por,abierto_en,cerrado_en,reporte) VALUES(:l,:d,:u,:t,:t,'{}'::jsonb) RETURNING id_jornada",l=identity,d=today,u=user,t=datetime.combine(today,datetime.min.time(),LIMA)+timedelta(hours=10))
            future_open = {'id_jornada': jid, 'fecha': today, 'cerrado_en': None}
            journals[today] = future_open
        if future_open:
            db.session.execute(text("UPDATE inventario_evento SET id_jornada=:j WHERE id_local=:l AND (registrado_en AT TIME ZONE 'America/Lima')::date>:e"),{'j':future_open['id_jornada'],'l':identity,'e':END})
            db.session.execute(text("UPDATE salon_cobro SET id_jornada=:j WHERE id_local=:l AND (creado_en AT TIME ZONE 'America/Lima')::date>:e"),{'j':future_open['id_jornada'],'l':identity,'e':END})
        week_ids = {}
        for day in DAYS:
            if day in journals:
                week_ids[day] = journals[day]['id_jornada']
            else:
                week_ids[day] = scalar("INSERT INTO inventario_jornada(id_local,fecha,abierto_por,abierto_en,cerrado_en,reporte) VALUES(:l,:d,:u,:t,:t,'{}'::jsonb) RETURNING id_jornada",l=identity,d=day,u=user,t=datetime.combine(day,datetime.min.time(),LIMA)+timedelta(hours=10))
            db.session.execute(text("UPDATE inventario_evento SET id_jornada=:j WHERE id_local=:l AND (registrado_en AT TIME ZONE 'America/Lima')::date=:d AND id_jornada<>:j"), {'j':week_ids[day],'l':identity,'d':day})
            db.session.execute(text("UPDATE salon_cobro SET id_jornada=:j WHERE id_local=:l AND (creado_en AT TIME ZONE 'America/Lima')::date=:d AND id_jornada IS DISTINCT FROM :j"), {'j':week_ids[day],'l':identity,'d':day})
        running = opening.copy()
        for day in DAYS:
            at_open = datetime.combine(day, datetime.min.time(), LIMA) + timedelta(hours=10)
            at_close = at_open + timedelta(hours=13, minutes=45)
            original = journals.get(day)
            jid = week_ids[day]
            db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=NULL,reporte=NULL WHERE id_jornada=:j'), {'j': jid})
            bulk('''INSERT INTO inventario_jornada_inicio(id_jornada,id_producto,cantidad) VALUES(:j,:p,:q)
              ON CONFLICT(id_jornada,id_producto) DO UPDATE SET cantidad=EXCLUDED.cantidad''', [dict(j=jid, p=p, q=q) for p, q in running.items()])
            db.session.execute(text("UPDATE inventario_evento SET id_jornada=:j WHERE id_local=:l AND (registrado_en AT TIME ZONE 'America/Lima')::date=:d AND id_jornada<>:j"), {'j': jid, 'l': identity, 'd': day})
            db.session.execute(text("UPDATE salon_cobro SET id_jornada=:j WHERE id_local=:l AND (creado_en AT TIME ZONE 'America/Lima')::date=:d AND id_jornada IS DISTINCT FROM :j"), {'j': jid, 'l': identity, 'd': day})
            if day in incoming: receipt(identity, user, day, jid, incoming[day], pmap)
            for ticket in tickets[day]: sale(identity, local['nombre'], user, day, jid, ticket)
            if waste[day]: movement(identity, user, day, jid, f'SV{identity}{day:%y%m%d}M', waste[day], 'MERMA', at_close - timedelta(minutes=30))
            # Only explicitly tagged historical demo payments are varied; manual payments survive.
            db.session.execute(text("""UPDATE salon_cobro SET metodo='TARJETA',comprobante=jsonb_set(comprobante,'{metodo}','\"TARJETA\"'::jsonb)
              WHERE id_local=:l AND (creado_en AT TIME ZONE 'America/Lima')::date=:d AND comprobante->>'prueba' LIKE 'DEMO-SHERATON-%' AND id_cobro%2=0"""), {'l': identity, 'd': day})
            report = reporte({'id_jornada': jid, 'id_local': identity})
            running = {r['id_producto']: Decimal(str(r['final'])) for r in report['inventario']}
            if any(q < 0 for q in running.values()): raise RuntimeError(f'El cierre genera un saldo negativo en local {identity}, {day}; se revierte.')
            report.update(prueba=TAG, revision_demo={'reporte_anterior_sha256': digest(original['reporte']) if original else None})
            db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=:t,cerrado_por=:u,reporte=CAST(:r AS jsonb) WHERE id_jornada=:j'), {'t': at_close, 'u': user, 'r': json.dumps(serial(report)), 'j': jid})
            rid = scalar('INSERT INTO inventario_ronda(id_local,nombre,creado_por,creado_en,cerrado_en) VALUES(:l,:name,:u,:t,:t) RETURNING id_ronda', l=identity, name=f'SV {local["nombre"]} {day}', u=user, t=at_close)
            bulk('''INSERT INTO inventario_conteo(id_ronda,id_producto,teorico,contado,contado_por,contado_en,estado,observacion,revisado_por,revisado_en,justificacion,justificado_por,justificado_en,contado_perfil,contado_perfil_nombre)
              VALUES(:r,:p,:q,:q,:u,:t,'REVISADO',:note,:u,:t,:note,:u,:t,1,'Administrador del sistema')''',
              [dict(r=rid, p=p, q=q, u=user, t=at_close, note=TAG) for p, q in running.items()])
            db.session.execute(text("INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo,creado_en) SELECT id_ronda,id_producto,:u,'revisar','{}'::jsonb,to_jsonb(c),:t FROM inventario_conteo c WHERE id_ronda=:r"), {'u': user, 't': at_close, 'r': rid})
            db.session.execute(text('''INSERT INTO salon_cierre_diario(id_local,fecha,simulacion,cantidad,efectivo,tarjeta)
              SELECT :l,:d,true,count(*),coalesce(sum(total) FILTER(WHERE metodo='EFECTIVO'),0),coalesce(sum(total) FILTER(WHERE metodo='TARJETA'),0)
              FROM salon_cobro WHERE id_local=:l AND (creado_en AT TIME ZONE 'America/Lima')::date=:d AND comprobante->'anulacion' IS NULL
              ON CONFLICT(id_local,fecha) DO UPDATE SET cantidad=EXCLUDED.cantidad,efectivo=EXCLUDED.efectivo,tarjeta=EXCLUDED.tarjeta WHERE salon_cierre_diario.simulacion'''), {'l': identity, 'd': day})
        for day, journal in journals.items():
            if day > END and journal['cerrado_en'] is None:
                bulk('''INSERT INTO inventario_jornada_inicio(id_jornada,id_producto,cantidad) VALUES(:j,:p,:q)
                  ON CONFLICT(id_jornada,id_producto) DO UPDATE SET cantidad=EXCLUDED.cantidad''', [dict(j=journal['id_jornada'], p=p, q=q) for p, q in running.items()])
                db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=NULL,reporte=NULL WHERE id_jornada=:j'), {'j': journal['id_jornada']})
        stale = [journal for day, journal in journals.items() if day < START and journal['cerrado_en'] is None]
        if stale:
            for journal in stale:
                legacy_report = reporte(journal)
                db.session.execute(text('UPDATE inventario_jornada SET reporte=CAST(:r AS jsonb),cerrado_en=:t,cerrado_por=:u WHERE id_jornada=:j'),
                  {'r': json.dumps(serial(legacy_report)), 't': datetime.combine(START,datetime.min.time(),LIMA)-timedelta(minutes=15), 'u': user, 'j': journal['id_jornada']})
                db.session.execute(text('''INSERT INTO actividad_usuario(id_usuario,modulo,accion,id_registro_afectado,descripcion,id_perfil_utilizado,id_local)
                  VALUES(:u,'INVENTARIO_OPERATIVO','REGULARIZAR_JORNADA',:j,:tag,1,:l)'''), {'u': user, 'j': journal['id_jornada'], 'tag': TAG, 'l': identity})
        manual_after = rows("SELECT * FROM salon_cobro WHERE id_local=:l AND coalesce(comprobante->>'prueba','') NOT LIKE 'DEMO-%' ORDER BY id_cobro", l=identity)
        strip = lambda items: [{k: v for k, v in item.items() if k != 'id_jornada'} for item in items]
        if strip(manual_before) != strip(manual_after): raise RuntimeError('Se alteró una venta manual; se revierte.')
        verify(identity)
        db.session.execute(text('''INSERT INTO actividad_usuario(id_usuario,modulo,accion,id_registro_afectado,descripcion,id_perfil_utilizado,id_local)
          VALUES(:u,'INVENTARIO_OPERATIVO','CARGAR_DEMO',:l,:tag,1,:l)'''), {'u': user, 'l': identity, 'tag': TAG})
        results.append({**local, 'dias_cerrados': len(DAYS), 'productos': len(running), 'ventas_manuales_preservadas': len(manual_before), 'jornadas_previas_regularizadas': len(stale)})
    if scalar('SELECT count(*) FROM fact_api_operacion') != jobs_before: raise RuntimeError('El histórico creó trabajos fiscales; se revierte.')
    return {'desde': START.isoformat(), 'hasta': END.isoformat(), 'locales': results, 'recetas_validas': len(menu), 'recetas_omitidas': omitted, 'resguardo':snapshot}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--validate', action='store_true')
    parser.add_argument('--close-stale', action='store_true')
    parser.add_argument('--local', type=int, action='append')
    parser.add_argument('--start', type=date.fromisoformat, default=START)
    parser.add_argument('--end', type=date.fromisoformat, default=END)
    args = parser.parse_args()
    configure_period(args.start,args.end)
    with create_app().app_context():
        try:
            if args.apply or args.validate:
                result = apply(args.local, args.close_stale, backup=args.apply)
                if args.apply: db.session.commit()
                else: db.session.rollback()
                result['confirmado'] = bool(args.apply)
            else:
                products, menu, plan, omitted = inspect(args.local, args.close_stale)
                result = {'plan': plan, 'productos': len(products), 'recetas_validas': len(menu), 'recetas_omitidas': omitted}
                db.session.rollback()
            print(json.dumps(serial(result), ensure_ascii=True))
        except Exception:
            db.session.rollback(); raise


if __name__ == '__main__': main()
