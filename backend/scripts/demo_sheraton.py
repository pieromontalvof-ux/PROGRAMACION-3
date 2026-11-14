"""Demo local autorizada de Sheraton. Sin --apply solo inspecciona el plan.

Carga 21 días terminados ayer. Respaldo previo, una transacción, sin red externa,
idempotencia por marca, rechazo si hay actividad real y conciliación de existencias.
"""
import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, ROUND_CEILING
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
from app import create_app
from app.core.extensions import db
from app.modules.auth.salon_payments import consumos
from app.modules.inventarios.operativo import reporte, serial
from app.modules.auditoria.service import registrar_actividad

TAG = 'DEMO-SHERATON-20261111'
TODAY = date(2026, 11, 11)
START = TODAY - timedelta(days=21)
LIMA = timezone(timedelta(hours=-5))


def query(sql, **params):
    return [dict(r) for r in db.session.execute(text(sql), params).mappings()]


from sqlalchemy import text


def scalar(sql, **params):
    return db.session.execute(text(sql), params).scalar_one()


def inspect():
    if db.engine.url.host not in ('localhost', '127.0.0.1', '::1'):
        raise RuntimeError('Esta carga solo admite la base local.')
    local = scalar("SELECT id_local FROM local WHERE lower(nombre)='sheraton' AND estado_registro=1")
    if scalar("SELECT count(*) FROM actividad_usuario WHERE descripcion=:tag AND accion='CARGAR_DEMO'", tag=TAG):
        raise RuntimeError('Este lote DEMO ya está cargado. No se duplica.')
    for table in ('salon_cobro', 'orden_compra', 'movimiento_inventario', 'inventario_evento', 'salon_pedido_actual'):
        if scalar(f'SELECT count(*) FROM {table} WHERE id_local=:l', l=local):
            raise RuntimeError('Sheraton ya tiene actividad; no se mezcla automáticamente con la demo.')
    if scalar('SELECT count(*) FROM inventario_stock_teorico WHERE id_local=:l AND stock_actual<>0', l=local):
        raise RuntimeError('Sheraton ya tiene stock; revisar antes de cargar.')
    if scalar('SELECT count(*) FROM inventario_jornada WHERE id_local=:l AND fecha>=:start', l=local, start=START):
        raise RuntimeError('Hay jornadas dentro del período demo; no se reemplazan.')
    user = scalar('''SELECT min(u.id_usuario) FROM usuario u JOIN usuario_local ul USING(id_usuario)
        JOIN usuario_perfiles up USING(id_usuario) WHERE ul.id_local=:l AND ul.estado_registro=1
        AND up.id_perfil=2 AND up.estado_registro=1 AND u.estado_registro=1''', l=local)
    if user is None:
        raise RuntimeError('Falta gerente autorizado en Sheraton.')
    menu = query('''SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,pv.precio FROM presentacion_venta pv
        JOIN item_carta ic USING(id_item_carta) WHERE pv.activo AND ic.activo AND pv.precio>0
        AND NOT EXISTS(SELECT 1 FROM grupo_salsa gs WHERE gs.activo AND gs.id_presentacion_venta=pv.id_presentacion_venta)
        AND pv.id_presentacion_venta=ANY(:ids) ORDER BY pv.id_presentacion_venta''', ids=[8,9,16,24,34,36,46,52,53,118,124])
    valid = []
    for row in menu:
        line = {**row, 'id_promocion':None, 'selecciones_promocion':[], 'cantidad':1, 'opciones':[], 'comentario':TAG+' · VENTA FICTICIA'}
        try:
            used = consumos([line])
        except Exception as error:
            print('Presentación omitida:', row['id_presentacion'], str(error))
            continue
        if used:
            valid.append(line)
    if len(valid)<5:
        raise RuntimeError('No hay suficientes recetas válidas para esta demo.')
    schedule, totals = [], defaultdict(Decimal)
    for i in range(21):
        day = START + timedelta(days=i)
        lines = [{**line, 'cantidad': (5 if day.weekday() in (4,5) else 2) + (i+j)%4}
                 for j,line in enumerate(valid)]
        for slot in range(2):
            for product, amount in consumos([line for j,line in enumerate(lines) if j%2==slot]).items():
                totals[product] += amount
        schedule.append((day, lines))
    products = {p['id_producto']:p for p in query('SELECT id_producto,nombre,unidad,id_proveedor FROM producto WHERE id_producto=ANY(:ids)', ids=list(totals))}
    if any(p['id_proveedor'] is None for p in products.values()):
        raise RuntimeError('Falta proveedor asociado a un insumo.')
    # Algunos insumos quedan con cobertura corta y otros holgada para probar la reposición.
    incoming, targets = {}, {}
    for i,(product, total) in enumerate(sorted(totals.items())):
        target = total/Decimal(21)*Decimal(2 if i%2==0 else 20)
        target = target.quantize(Decimal('1') if products[product]['unidad']=='C62' else Decimal('.001'), rounding=ROUND_CEILING)
        targets[product] = target
        incoming[product] = total + target
    return local, user, schedule, totals, products, incoming, targets


def backup():
    target = ROOT/'backend/instance/migration_backups'/TAG/datetime.now().strftime('%Y%m%d-%H%M%S')
    target.mkdir(parents=True, exist_ok=False)
    url = db.engine.url
    command = [r'C:/Program Files/PostgreSQL/18/bin/pg_dump.exe', '-h', url.host, '-p', str(url.port or 5432),
               '-U', url.username, '-d', url.database, '-Fc', '--no-owner', '--no-privileges', '-f', str(target/'before.dump')]
    completed = subprocess.run(command, env={**os.environ,'PGPASSWORD':url.password or ''}, capture_output=True)
    if completed.returncode or (target/'before.dump').stat().st_size<1000:
        raise RuntimeError('No se pudo respaldar; no se aplica la carga.')
    return target


def apply():
    db.session.execute(text("SET LOCAL lock_timeout='5s'"))
    db.session.execute(text('''LOCK TABLE inventario_jornada,inventario_evento,inventario_jornada_inicio,
        orden_compra,orden_compra_detalle,factura_recepcion,factura_recepcion_detalle,
        salon_pedido,salon_pedido_linea,salon_cobro,salon_cobro_pedido,movimiento_inventario,
        movimiento_inventario_detalle,receta,receta_detalle,subproducto,subproducto_detalle,
        producto,actividad_usuario IN SHARE ROW EXCLUSIVE MODE'''))
    local,user,schedule,totals,products,incoming,targets = inspect()
    protected = {t:query(f'SELECT * FROM {t} WHERE id_local<>:l ORDER BY 1,2', l=local)
                 for t in ('inventario_stock_teorico','salon_cobro','orden_compra','inventario_jornada','inventario_evento')}
    ids = {'ordenes':[], 'recepciones':[], 'pedidos_salon':[], 'cobros':[], 'jornadas':[]}
    # Solo se cierra la jornada vacía preexistente, que bloqueaba el avance del calendario.
    for old in query('SELECT * FROM inventario_jornada WHERE id_local=:l AND cerrado_en IS NULL', l=local):
        content = reporte({'id_jornada':old['id_jornada'],'id_local':local})
        db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=:t,cerrado_por=:u,reporte=CAST(:r AS jsonb) WHERE id_jornada=:j'),
            dict(t=datetime.combine(old['fecha'],datetime.min.time(),LIMA)+timedelta(hours=23),u=user,r=json.dumps(content),j=old['id_jornada']))
        registrar_actividad(user,'INVENTARIO_OPERATIVO','CIERRE_PRUEBA',old['id_jornada'],TAG+' · cierre de jornada vacía previa',id_perfil_utilizado=2,id_local=local)
    delivered = defaultdict(Decimal)
    for index,(day,lines) in enumerate(schedule):
        opening = datetime.combine(day, datetime.min.time(), LIMA)+timedelta(hours=12)
        jid = scalar('SELECT inventario_abrir_jornada(:l,:u,:day)', l=local,u=user,day=day)
        ids['jornadas'].append(jid)
        db.session.execute(text('UPDATE inventario_jornada SET abierto_en=:t WHERE id_jornada=:j'), dict(t=opening,j=jid))
        if index in (0,7,14):
            order = scalar('''INSERT INTO orden_compra(codigo,estado_orden_compra,usuario_registro,fecha_registro,id_local)
                VALUES(:code,'ENVIADA',:u,:day,:l) RETURNING id_orden_compra''',code=f'DSH-{day:%Y%m%d}',u=user,day=day,l=local)
            ids['ordenes'].append(order)
            groups = defaultdict(list)
            for product,total in incoming.items():
                quantum = Decimal('1') if products[product]['unidad']=='C62' else Decimal('.001')
                quantity = ((total*Decimal('.50' if index==0 else '.30')).quantize(quantum, rounding=ROUND_CEILING)
                            if index<14 else total-delivered[product])
                if quantity<=0:
                    continue
                delivered[product] += quantity
                supplier = products[product]['id_proveedor']
                db.session.execute(text('INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada,id_proveedor) VALUES(:o,:p,:q,:v)'),dict(o=order,p=product,q=quantity,v=supplier))
                groups[supplier].append((product,quantity))
            for supplier,items in groups.items():
                receipt = scalar('''INSERT INTO factura_recepcion(id_orden_compra,id_proveedor,numero_factura,fecha_recepcion,usuario_recepcion)
                    VALUES(:o,:v,:code,:day,:u) RETURNING id_factura_recepcion''',o=order,v=supplier,code=f'DEMO-SH-{day:%Y%m%d}-{supplier}',day=day,u=user)
                ids['recepciones'].append(receipt)
                for product,quantity in items:
                    db.session.execute(text('INSERT INTO factura_recepcion_detalle(id_factura_recepcion,id_producto,cantidad_recibida) VALUES(:r,:p,:q)'),dict(r=receipt,p=product,q=quantity))
            db.session.execute(text("UPDATE orden_compra SET estado_orden_compra='RECEPCIONADA',usuario_modificacion=:u,fecha_modificacion=:t WHERE id_orden_compra=:o"),dict(u=user,t=opening.replace(tzinfo=None),o=order))
            db.session.execute(text('''INSERT INTO orden_compra_estado_historial(id_orden_compra,estado_anterior,estado_nuevo,motivo,usuario_modificacion,fecha_modificacion)
                VALUES(:o,'ENVIADA','RECEPCIONADA',:tag,:u,:t)'''),dict(o=order,tag=TAG+' · recepción ficticia sin envío externo',u=user,t=opening.replace(tzinfo=None)))
            registrar_actividad(user,'COMPRAS','COMPRA_PRUEBA',order,TAG+' · compra y recepción ficticias',id_perfil_utilizado=2,id_local=local)
        for slot in range(2):
            sold = [dict(line) for i,line in enumerate(lines) if i%2==slot]
            moment = opening+timedelta(hours=6+slot*3)
            key = str(uuid.uuid5(uuid.NAMESPACE_URL,f'{TAG}:{day}:{slot}'))
            hashed = hashlib.sha256(key.encode()).hexdigest()
            pid = scalar('''INSERT INTO salon_pedido(id_local,mesa,id_usuario,creado_en,envio_clave,envio_hash)
                VALUES(:l,'M01',:u,:t,CAST(:key AS uuid),:hash) RETURNING id_pedido''',l=local,u=user,t=moment,key=key,hash=hashed)
            ids['pedidos_salon'].append(pid)
            for pos,line in enumerate(sold):
                lid = scalar('''INSERT INTO salon_pedido_linea(id_pedido,posicion,id_presentacion,nombre,precio,cantidad,comentario,opciones)
                    VALUES(:p,:pos,:id_presentacion,:nombre,:precio,:cantidad,:comentario,'[]'::jsonb) RETURNING id_linea''',
                    p=pid,pos=pos,**{k:v for k,v in line.items() if k!='opciones'})
                line.update(ids_lineas=[lid],enviada=True)
            db.session.execute(text("UPDATE salon_pedido SET estado='ENVIADO',enviado_en=:t WHERE id_pedido=:p"),dict(t=moment,p=pid))
            move = scalar('''INSERT INTO movimiento_inventario(codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local,observacion,registrado_en)
                VALUES(:code,'SALIDA','VENTA_SALON',:day,:u,:l,:tag,:t) RETURNING id_movimiento_inventario''',
                code=f'DSH-V-{index:02d}-{slot}',day=day,u=user,l=local,tag=TAG+' · venta ficticia',t=moment.replace(tzinfo=None))
            for product,amount in consumos(sold).items():
                db.session.execute(text('INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:m,:p,:q)'),dict(m=move,p=product,q=amount))
            total = sum(line['precio']*line['cantidad'] for line in sold)
            snapshot = serial(dict(tipo='BOLETA',metodo='EFECTIVO',documento='',cliente='',local='Sheraton',mesa='M01',
                                   total=total,fiscal=False,lineas=sold,prueba=TAG))
            paid = scalar('''INSERT INTO salon_cobro(id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,total,comprobante,id_movimiento,creado_en)
                VALUES(:l,:u,'M01',CAST(:key AS uuid),:hash,'BOLETA','EFECTIVO',:total,CAST(:r AS jsonb),:m,:t) RETURNING id_cobro''',
                l=local,u=user,key=key,hash=hashed,total=total,r=json.dumps(snapshot),m=move,t=moment)
            ids['cobros'].append(paid)
            db.session.execute(text('INSERT INTO salon_cobro_pedido(id_pedido,id_cobro) VALUES(:p,:c)'),dict(p=pid,c=paid))
            registrar_actividad(user,'SALON','COBRO_PRUEBA',paid,TAG+' · venta ficticia',id_perfil_utilizado=2,id_local=local)
        db.session.execute(text('UPDATE inventario_evento SET registrado_en=:t WHERE id_jornada=:j AND id_local=:l'),dict(t=opening+timedelta(hours=9),j=jid,l=local))
        if scalar('SELECT count(*) FROM inventario_stock_teorico WHERE id_local=:l AND stock_actual<0',l=local):
            raise RuntimeError('La demo generaría stock negativo; se revierte completa.')
        content = reporte({'id_jornada':jid,'id_local':local})
        db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=:t,cerrado_por=:u,reporte=CAST(:r AS jsonb) WHERE id_jornada=:j'),dict(t=opening+timedelta(hours=11),u=user,r=json.dumps(content),j=jid))
    actual = {r['id_producto']:r['stock_actual'] for r in query('SELECT * FROM inventario_stock_teorico WHERE id_local=:l',l=local)}
    if any(abs(actual[p]-target)>Decimal('.001') for p,target in targets.items()):
        raise RuntimeError('No concilia stock = recepciones - consumo. Se revierte.')
    for table,before in protected.items():
        if before != query(f'SELECT * FROM {table} WHERE id_local<>:l ORDER BY 1,2',l=local):
            raise RuntimeError('Cambió otra sede; se revierte.')
    registrar_actividad(user,'INVENTARIO_OPERATIVO','CARGAR_DEMO',local,TAG,id_perfil_utilizado=2,id_local=local)
    return dict(marca=TAG,local=local,desde=START,hasta=TODAY-timedelta(days=1),ids=ids,
                productos_con_stock=len(targets),consumo=totals,stock_final={p:actual[p] for p in targets},otras_sedes_sin_cambios=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args=parser.parse_args()
    with create_app().app_context():
        local,user,schedule,totals,products,incoming,targets=inspect()
        print(json.dumps(serial(dict(local=local,marca=TAG,dias=len(schedule),presentaciones=len(schedule[0][1]),
              insumos=len(totals),ordenes=3,cobros=42,stock_final=targets)), ensure_ascii=True))
        db.session.rollback()
        if not args.apply:
            return
        target=backup()
        try:
            result=apply()
            (target/'resultado.json').write_text(json.dumps(serial(result),ensure_ascii=False,indent=2),encoding='utf-8')
            db.session.commit()
        except Exception:
            db.session.rollback()
            raise
        print(json.dumps(serial(result),ensure_ascii=True))


if __name__=='__main__':
    main()
