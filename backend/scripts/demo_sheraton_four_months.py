"""Authorized LOCAL FICTIONAL history, July 15–November 14, 2026.

Default is read-only. Historical purchases exactly fund historical recipe
consumption, so inserting the missing past cannot change today's stock. Existing
closed reports, counts and sales are never replaced. No fiscal issuance or send.
"""
import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'backend'))
from app import create_app
from app.core.extensions import db
from app.modules.salon.salon_payments import consumos
from app.modules.inventarios.operativo import reporte
from sqlalchemy import text
from scripts.demo_sheraton_inventory import serial, digest, fictional_count, LIMA

TAG = 'DEMO-SHERATON-4MESES-20260715-20261114'
START, END = date(2026,7,15), date(2026,11,14)


def rows(sql, **p):
    return [dict(r) for r in db.session.execute(text(sql),p).mappings()]


def scalar(sql, **p):
    return db.session.execute(text(sql),p).scalar_one()


def bulk(sql, data):
    if data:
        db.session.execute(text(sql),data)


def sale_schedule(menu, start, end):
    result = []
    for i in range((end-start).days+1):
        day = start+timedelta(days=i)
        # Friday/Saturday demand, monthly trend, weekly cycle and product mix.
        lines = [{**m, 'cantidad': 2+(i//7)%5+(i//28)+(i+j*3)%4+
                  (4 if day.weekday() in (4,5) else 0),
                  'id_promocion':None,'selecciones_promocion':[], 'opciones':[],
                  'comentario':TAG+' · VENTA FICTICIA'} for j,m in enumerate(menu)]
        result.append((day,lines))
    return result


def weekly_receipts(daily):
    result = {}
    index=0
    while index<len(daily):
        stop=index+1
        while stop<len(daily) and stop-index<7 and daily[stop][0]==daily[stop-1][0]+timedelta(days=1):
            stop+=1
        quantities = defaultdict(Decimal)
        for _, consumption in daily[index:stop]:
            for product, quantity in consumption.items():
                quantities[product] += quantity
        result[daily[index][0]] = dict(quantities)
        index=stop
    return result


def inspect():
    if db.engine.url.host not in ('localhost','127.0.0.1','::1'):
        raise RuntimeError('Solo base local loopback autorizada.')
    if scalar("SELECT count(*) FROM local WHERE id_local=4 AND lower(nombre)='sheraton' AND estado_registro=1") != 1:
        raise RuntimeError('Local Sheraton no coincide.')
    if scalar("SELECT count(*) FROM actividad_usuario WHERE descripcion=:tag AND accion='CARGAR_DEMO'",tag=TAG):
        raise RuntimeError('Lote ya aplicado; no se duplica.')
    if scalar('SELECT count(*) FROM inventario_jornada WHERE id_local=4 AND cerrado_en IS NULL'):
        raise RuntimeError('Jornada abierta: se preserva; cerrar antes de preparar historia.')
    if scalar('SELECT count(*) FROM inventario_ronda WHERE id_local=4 AND cerrado_en IS NULL'):
        raise RuntimeError('Conteo abierto: se preserva.')
    existing=rows('SELECT * FROM inventario_jornada WHERE id_local=4 ORDER BY fecha')
    if not existing or {j['fecha'] for j in existing if j['fecha']<date(2026,10,21)} != {date(2026,9,26)}:
        raise RuntimeError('Historia previa distinta de la demo esperada desde 21 octubre.')
    if any(not j['reporte'] for j in existing):
        raise RuntimeError('Cierre existente sin reporte verificable.')
    products=rows('''SELECT p.*,s.stock_minimo minimo_local FROM producto p LEFT JOIN producto_stock_local s
      ON s.id_producto=p.id_producto AND s.id_local=4 WHERE p.activo ORDER BY p.id_producto''')
    if len(products)!=141:
        raise RuntimeError('Se requieren los 141 insumos autorizados.')
    user=scalar('''SELECT min(u.id_usuario) FROM usuario u JOIN usuario_local ul USING(id_usuario)
      JOIN usuario_perfiles up USING(id_usuario) WHERE ul.id_local=4 AND ul.estado_registro=1
      AND up.id_perfil=2 AND up.estado_registro=1 AND u.estado_registro=1''')
    if user is None:
        raise RuntimeError('Falta gerente Sheraton.')
    menu=rows('''SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,pv.precio FROM presentacion_venta pv
      JOIN item_carta ic USING(id_item_carta) WHERE pv.activo AND ic.activo AND pv.precio>0
      AND pv.id_presentacion_venta=ANY(:ids) AND NOT EXISTS(SELECT 1 FROM grupo_salsa gs
      WHERE gs.activo AND gs.id_presentacion_venta=pv.id_presentacion_venta) ORDER BY 1''',
      ids=[8,9,16,24,34,36,46,52,53,118,124])
    menu=[m for m in menu if consumos([{**m,'cantidad':1,'opciones':[],'id_promocion':None,'selecciones_promocion':[]}])]
    if len(menu)<5:
        raise RuntimeError('Recetas insuficientes.')
    occupied={j['fecha'] for j in existing}
    schedule=[(day,lines) for day,lines in sale_schedule(menu,START,date(2026,10,20)) if day not in occupied]
    return user,products,existing,schedule


def backup():
    target=ROOT/'backend/instance/migration_backups'/TAG/datetime.now().strftime('%Y%m%d-%H%M%S')
    target.mkdir(parents=True,exist_ok=False)
    url=db.engine.url
    result=subprocess.run([r'C:/Program Files/PostgreSQL/18/bin/pg_dump.exe','-h',url.host,
      '-p',str(url.port or 5432),'-U',url.username,'-d',url.database,'-Fc','--no-owner','--no-privileges',
      '-f',str(target/'before.dump')],env={**os.environ,'PGPASSWORD':url.password or ''},capture_output=True)
    if result.returncode or not (target/'before.dump').exists() or (target/'before.dump').stat().st_size<1000:
        raise RuntimeError('Respaldo falló; no se aplica.')
    return target


def audit(user, action, identity, note):
    db.session.execute(text('''INSERT INTO actividad_usuario(id_usuario,modulo,accion,id_registro_afectado,
      descripcion,id_perfil_utilizado,id_local) VALUES(:u,'INVENTARIO_OPERATIVO',:a,:i,:n,2,4)'''),
      dict(u=user,a=action,i=identity,n=note))


def apply():
    db.session.execute(text("SET LOCAL lock_timeout='8s'"))
    tables=('inventario_jornada','inventario_jornada_inicio','inventario_evento','inventario_ronda',
      'inventario_conteo','inventario_conteo_historial','orden_compra','orden_compra_detalle',
      'orden_compra_estado_historial','factura_recepcion','factura_recepcion_detalle',
      'movimiento_inventario','movimiento_inventario_detalle','salon_pedido','salon_pedido_linea',
      'salon_cobro','salon_cobro_pedido','producto','producto_stock_local','inventario_saldo_inicial','actividad_usuario')
    db.session.execute(text('LOCK TABLE '+','.join(tables)+' IN SHARE ROW EXCLUSIVE MODE'))
    db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext('inventario-dia:4'))"))
    user,products,existing,schedule=inspect()
    # Hash every pre-existing row, including details and every other store.
    originals={}
    for table in tables:
        old=rows(f'SELECT * FROM {table} ORDER BY 1,2')
        key=next(iter(old[0])) if old else None
        originals[table]=(key,list({r[key] for r in old}) if key else [],digest(old))
    other_before={t:digest(rows(f'SELECT * FROM {t} WHERE id_local<>4 ORDER BY 1,2')) for t in
      ('inventario_jornada','inventario_evento','inventario_ronda','orden_compra','salon_cobro','movimiento_inventario','inventario_stock_teorico')}
    stock_before=rows('SELECT * FROM inventario_stock_teorico ORDER BY 1,2')
    consumed=[(day,{p:q.quantize(Decimal('.001')) for p,q in consumos(lines).items()}) for day,lines in schedule]
    purchases=weekly_receipts(consumed)
    inventory={p['id_producto']:Decimal(0) for p in products}
    productmap={p['id_producto']:p for p in products}
    ids=dict(jornadas=[],ordenes=[],recepciones=[],cobros=[],rondas=[],movimientos=[])
    for index,(day,lines) in enumerate(schedule):
        opening=datetime.combine(day,datetime.min.time(),LIMA)+timedelta(hours=10)
        closing=opening+timedelta(hours=13)
        # Direct historical insert intentionally bypasses forward-only opening API,
        # while all normal receipt/movement/payment triggers remain enabled.
        jid=scalar('''INSERT INTO inventario_jornada(id_local,fecha,abierto_por,abierto_en)
          VALUES(4,:d,:u,:t) RETURNING id_jornada''',d=day,u=user,t=opening)
        ids['jornadas'].append(jid)
        bulk('INSERT INTO inventario_jornada_inicio VALUES(:j,:p,:q)',[dict(j=jid,p=p,q=q) for p,q in inventory.items()])
        if day in purchases:
            order=scalar('''INSERT INTO orden_compra(codigo,estado_orden_compra,usuario_registro,fecha_registro,id_local)
              VALUES(:code,'ENVIADA',:u,:d,4) RETURNING id_orden_compra''',code=f'DSH4-{day:%Y%m%d}',u=user,d=day)
            ids['ordenes'].append(order)
            groups=defaultdict(list)
            for pid,q in purchases[day].items():
                groups[productmap[pid]['id_proveedor']].append((pid,q))
                inventory[pid]+=q
            bulk('''INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada,id_proveedor)
              VALUES(:o,:p,:q,:v)''',[dict(o=order,p=p,q=q,v=v) for v,items in groups.items() for p,q in items])
            for provider,items in groups.items():
                receipt=scalar('''INSERT INTO factura_recepcion(id_orden_compra,id_proveedor,numero_factura,fecha_recepcion,usuario_recepcion)
                  VALUES(:o,:v,:code,:d,:u) RETURNING id_factura_recepcion''',o=order,v=provider,
                  code=f'DEMO-DSH4-{day:%Y%m%d}-{provider}',d=day,u=user)
                ids['recepciones'].append(receipt)
                bulk('''INSERT INTO factura_recepcion_detalle(id_factura_recepcion,id_producto,cantidad_recibida)
                  VALUES(:r,:p,:q)''',[dict(r=receipt,p=p,q=q) for p,q in items])
            db.session.execute(text("UPDATE orden_compra SET estado_orden_compra='RECEPCIONADA' WHERE id_orden_compra=:o"),dict(o=order))
            audit(user,'COMPRA_PRUEBA',order,TAG+' · recepción ficticia, sin documento fiscal ni envío externo')
        for slot in range(2):
            sold=[dict(line) for j,line in enumerate(lines) if j%2==slot]
            moment=opening+timedelta(hours=7+slot*3)
            key=str(uuid.uuid5(uuid.NAMESPACE_URL,f'{TAG}:{day}:{slot}'))
            hashed=hashlib.sha256(key.encode()).hexdigest()
            pid=scalar('''INSERT INTO salon_pedido(id_local,mesa,id_usuario,creado_en,envio_clave,envio_hash)
              VALUES(4,'M01',:u,:t,CAST(:key AS uuid),:h) RETURNING id_pedido''',u=user,t=moment,key=key,h=hashed)
            for pos,line in enumerate(sold):
                lid=scalar('''INSERT INTO salon_pedido_linea(id_pedido,posicion,id_presentacion,nombre,precio,cantidad,comentario,opciones)
                  VALUES(:p,:pos,:id_presentacion,:nombre,:precio,:cantidad,:comentario,'[]'::jsonb) RETURNING id_linea''',
                  p=pid,pos=pos,**line)
                line.update(ids_lineas=[lid],enviada=True)
            db.session.execute(text("UPDATE salon_pedido SET estado='ENVIADO',enviado_en=:t WHERE id_pedido=:p"),dict(t=moment,p=pid))
            move=scalar('''INSERT INTO movimiento_inventario(codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,
              usuario_registro,id_local,observacion,registrado_en) VALUES(:code,'SALIDA','VENTA_SALON',:d,:u,4,:note,:t)
              RETURNING id_movimiento_inventario''',code=f'DSH4-V-{day:%Y%m%d}-{slot}',d=day,u=user,note=TAG+' · consumo receta ficticio',t=moment.replace(tzinfo=None))
            ids['movimientos'].append(move)
            amounts={p:q.quantize(Decimal('.001')) for p,q in consumos(sold).items()}
            bulk('INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:m,:p,:q)',
              [dict(m=move,p=p,q=q) for p,q in amounts.items()])
            for p,q in amounts.items():
                inventory[p]-=q
            total=sum(line['precio']*line['cantidad'] for line in sold)
            snapshot=serial(dict(tipo='BOLETA',metodo='EFECTIVO',documento='',cliente='',local='Sheraton',mesa='M01',
              total=total,fiscal=False,lineas=sold,prueba=TAG,nota='VENTA FICTICIA LOCAL; NO COMPROBANTE FISCAL'))
            paid=scalar('''INSERT INTO salon_cobro(id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,total,comprobante,id_movimiento,creado_en)
              VALUES(4,:u,'M01',CAST(:key AS uuid),:h,'BOLETA','EFECTIVO',:total,CAST(:r AS jsonb),:m,:t) RETURNING id_cobro''',
              u=user,key=key,h=hashed,total=total,r=json.dumps(snapshot),m=move,t=moment)
            ids['cobros'].append(paid)
            db.session.execute(text('INSERT INTO salon_cobro_pedido VALUES(:p,:c)'),dict(p=pid,c=paid))
        if min(inventory.values())<0:
            raise RuntimeError('Saldo histórico negativo; se revierte.')
        db.session.execute(text('UPDATE inventario_evento SET registrado_en=:t WHERE id_jornada=:j'),dict(t=closing-timedelta(hours=1),j=jid))
        content=reporte(dict(id_jornada=jid,id_local=4))
        if any(abs(Decimal(str(p['final']))-inventory[p['id_producto']])>Decimal('.0001') for p in content['inventario']):
            raise RuntimeError('Inventario histórico no concilia con recetas.')
        content.update(prueba=TAG,nota='Histórico FICTICIO; apertura cero, compras equilibradas al consumo; sin ajuste del stock actual')
        db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=:t,cerrado_por=:u,reporte=CAST(:r AS jsonb) WHERE id_jornada=:j'),
          dict(t=closing,u=user,r=json.dumps(content),j=jid))
        if index%14==0:
            print('Historia preparada:',day,flush=True)
    if any(inventory.values()) or stock_before!=rows('SELECT * FROM inventario_stock_teorico ORDER BY 1,2'):
        raise RuntimeError('La historia alteraría el stock actual; se revierte.')
    # Complete missing daily physical-count fixtures; leave all original rounds intact.
    for offset in range((END-START).days+1):
        day=START+timedelta(days=offset)
        if scalar('''SELECT count(DISTINCT c.id_producto) FROM inventario_ronda r JOIN inventario_conteo c USING(id_ronda)
          WHERE r.id_local=4 AND (r.creado_en AT TIME ZONE 'America/Lima')::date=:d''',d=day)==141:
            continue
        moment=datetime.combine(day,datetime.min.time(),LIMA)+timedelta(hours=23)
        rid=scalar('''INSERT INTO inventario_ronda(id_local,nombre,creado_por,creado_en,cerrado_en)
          VALUES(4,:n,:u,:t,:t) RETURNING id_ronda''',n=f'DEMO retrospectivo Sheraton {day:%d/%m/%Y}',u=user,t=moment)
        ids['rondas'].append(rid)
        finals=scalar("SELECT reporte FROM inventario_jornada WHERE id_local=4 AND fecha=:d",d=day)['inventario']
        theory={p['id_producto']:Decimal(str(p['final'])) for p in finals}
        bulk('''INSERT INTO inventario_conteo(id_ronda,id_producto,teorico,contado,contado_por,contado_en,estado,
          observacion,revisado_por,revisado_en,justificacion,justificado_por,justificado_en,contado_perfil,contado_perfil_nombre)
          VALUES(:r,:p,:v,:q,:u,:t,'REVISADO',:n,:u,:t,:why,:u,:t,2,'Gerente')''',
          [dict(r=rid,p=p['id_producto'],v=theory[p['id_producto']],q=fictional_count(p,day),u=user,t=moment,
            n=TAG+' · conteo FICTICIO retrospectivo; no observación física',
            why=TAG+' · diferencia simulada justificada, sin ajuste de stock ni sustitución del cierre') for p in products])
        db.session.execute(text('''INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo,creado_en)
          SELECT id_ronda,id_producto,:u,'revisar','{}'::jsonb,to_jsonb(c),:t FROM inventario_conteo c WHERE id_ronda=:r'''),dict(u=user,t=moment,r=rid))
        audit(user,'CONTEO_PRUEBA',rid,TAG+' · 141 conteos retrospectivos ficticios justificados; sin ajuste')
    for table,(key,identities,before) in originals.items():
        after=rows(f'SELECT * FROM {table} WHERE {key}=ANY(:ids) ORDER BY 1,2',ids=identities) if key else []
        if digest(after)!=before:
            raise RuntimeError('Registro previo modificado en '+table)
    other_after={t:digest(rows(f'SELECT * FROM {t} WHERE id_local<>4 ORDER BY 1,2')) for t in other_before}
    if other_before!=other_after:
        raise RuntimeError('Otra sede modificada; se revierte.')
    daily=rows('''SELECT j.fecha,count(*) productos,
      bool_and((p->>'inicial')::numeric+(p->>'entradas')::numeric-(p->>'salidas')::numeric=(p->>'final')::numeric) conciliado
      FROM inventario_jornada j CROSS JOIN LATERAL jsonb_array_elements(j.reporte->'inventario') p
      WHERE j.id_local=4 AND j.fecha BETWEEN :s AND :e GROUP BY j.fecha ORDER BY j.fecha''',s=START,e=END)
    counts=rows('''SELECT (r.creado_en AT TIME ZONE 'America/Lima')::date fecha,count(DISTINCT c.id_producto) productos
      FROM inventario_ronda r JOIN inventario_conteo c USING(id_ronda) WHERE r.id_local=4
      AND (r.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :s AND :e GROUP BY 1 ORDER BY 1''',s=START,e=END)
    if len(daily)!=123 or len(counts)!=123 or any(d['productos']!=141 or not d['conciliado'] for d in daily) or any(c['productos']!=141 for c in counts):
        raise RuntimeError('Cobertura diaria incompleta.')
    weekly=rows('''SELECT date_trunc('week',creado_en AT TIME ZONE 'America/Lima')::date semana,count(*) cobros,
      count(DISTINCT (creado_en AT TIME ZONE 'America/Lima')::date) dias,sum(total) total
      FROM salon_cobro WHERE id_local=4 AND (creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :s AND :e
      GROUP BY 1 ORDER BY 1''',s=START,e=END)
    audit(user,'CARGAR_DEMO',4,TAG)
    return dict(marca=TAG,desde=START,hasta=END,dias=123,productos=141,lineas_diarias=17343,
      nuevos={k:len(v) for k,v in ids.items()},ids=ids,validacion_diaria=daily,conteos_diarios=counts,
      ventas_semanales=weekly,cierres_previos_preservados=len(existing),stock_actual_sin_cambios=True,
      stock_actual=rows('SELECT id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=4 ORDER BY id_producto'),
      otras_sedes_antes=other_before,otras_sedes_despues=other_after,
      nota='FICTICIO LOCAL. Compras históricas=consumo de recetas; variación neta 0. Conteos retrospectivos justificados sin ajuste. No emisión fiscal ni envío externo.')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    with create_app().app_context():
        _,products,existing,schedule=inspect()
        print(json.dumps(dict(marca=TAG,modo='aplicar' if args.apply else 'solo_plan',dias=123,productos=len(products),
          jornadas_nuevas=len(schedule),cobros_nuevos=len(schedule)*2,cierres_preservados=len(existing),variacion_stock=0)))
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
        print(json.dumps(serial({k:v for k,v in result.items() if k not in ('ids','stock_actual','validacion_diaria','conteos_diarios')}),ensure_ascii=True))
        print('Respaldo y manifiesto:',target)


if __name__=='__main__':
    main()
