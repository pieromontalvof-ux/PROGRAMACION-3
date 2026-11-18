"""Complete LOCAL FICTIONAL Sheraton dates through yesterday, incrementally.

Read-only by default; --apply writes one transaction. No backup or report files
are produced, per the user's explicit instruction. Only demonstrably fictional
DEMO closures may have their derived report completed; their source rows survive.
Receipts fund exactly the new recipe consumption, preserving current stock.
"""
import argparse
from collections import defaultdict
from datetime import date,datetime,timedelta
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import sys
import uuid

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'backend'))
from app import create_app
from app.core.extensions import db
from app.modules.auth.salon_payments import consumos
from app.modules.inventarios.operativo import reporte
from scripts.demo_sheraton_four_months import rows,scalar,bulk
from scripts.demo_sheraton_inventory import serial,digest,LIMA
from sqlalchemy import text

START=date(2026,7,15)
TAG='DEMO-SHERATON-COMPLETAR'
TABLES=('inventario_jornada','inventario_jornada_inicio','inventario_evento','inventario_ronda',
    'inventario_conteo','inventario_conteo_historial','orden_compra','orden_compra_detalle',
    'orden_compra_estado_historial','factura_recepcion','factura_recepcion_detalle',
    'movimiento_inventario','movimiento_inventario_detalle','salon_pedido','salon_pedido_linea',
    'salon_cobro','salon_cobro_pedido','producto','producto_stock_local','inventario_saldo_inicial','actividad_usuario')


def missing_days(start,through,existing):
    return [start+timedelta(days=i) for i in range((through-start).days+1)
            if start+timedelta(days=i) not in existing]


def revisable_days(records):
    return [r['fecha'] for r in records if START<=r['fecha'] and r['fecha']!=date(2026,9,26)
            and r['demoproof']]


def rotating_menu(menu,day,already_sold):
    return [m for index,m in enumerate(menu) if index%7==day.weekday()
            and m['id_presentacion'] not in already_sold]


def inspect(through):
    yesterday=datetime.now(LIMA).date()-timedelta(days=1)
    if through<START or through>yesterday:
        raise RuntimeError('Fecha fuera del histórico autorizado hasta ayer Lima.')
    if db.engine.url.host not in ('localhost','127.0.0.1','::1'):
        raise RuntimeError('Solo base local loopback.')
    if scalar("SELECT count(*) FROM local WHERE id_local=4 AND lower(nombre)='sheraton' AND estado_registro=1")!=1:
        raise RuntimeError('Local Sheraton no coincide.')
    if not scalar("SELECT count(*) FROM actividad_usuario WHERE accion='CARGAR_DEMO' AND descripcion='DEMO-SHERATON-4MESES-20260715-20261114'"):
        raise RuntimeError('Falta lote ficticio autorizado original.')
    if scalar('SELECT count(*) FROM inventario_jornada WHERE id_local=4 AND cerrado_en IS NULL'):
        raise RuntimeError('Jornada abierta: no se modifica automáticamente.')
    if scalar('SELECT count(*) FROM inventario_ronda WHERE id_local=4 AND cerrado_en IS NULL'):
        raise RuntimeError('Conteo abierto: no se modifica automáticamente.')
    existing=rows('SELECT * FROM inventario_jornada WHERE id_local=4 ORDER BY fecha')
    for j in existing:
        if START<=j['fecha']<=through and (not j['reporte'] or len(j['reporte'].get('inventario',[]))!=141):
            raise RuntimeError('Jornada existente incompleta: revisar sin sustituirla.')
    days=missing_days(START,through,{j['fecha'] for j in existing})
    evidence=rows('''SELECT j.fecha,
      (coalesce(j.reporte->>'prueba','') LIKE 'DEMO-SHERATON-%' OR
       EXISTS(SELECT 1 FROM actividad_usuario a WHERE a.id_local=4 AND a.accion='CIERRE_PRUEBA'
        AND a.id_registro_afectado=j.id_jornada AND a.descripcion LIKE 'DEMO-SHERATON-INVENTARIOS-20261101-14%') OR
       EXISTS(SELECT 1 FROM salon_cobro c WHERE c.id_jornada=j.id_jornada AND c.comprobante->>'prueba'='DEMO-SHERATON-20261111'))
       AND NOT EXISTS(SELECT 1 FROM salon_cobro c WHERE c.id_jornada=j.id_jornada
         AND coalesce(c.comprobante->>'prueba','') NOT LIKE 'DEMO-SHERATON-%')
       AND NOT EXISTS(SELECT 1 FROM actividad_usuario a WHERE a.accion='CARGAR_DEMO' AND a.descripcion=:tag||':'||j.fecha::text)
       demoproof,
      (SELECT count(*) FROM salon_cobro c WHERE c.id_jornada=j.id_jornada) cobros
      FROM inventario_jornada j WHERE j.id_local=4 AND j.fecha BETWEEN :start AND :through''',through=through,start=START,tag=TAG)
    days=sorted(days+revisable_days(evidence))
    products=rows('SELECT * FROM producto WHERE activo ORDER BY id_producto')
    if len(products)!=141:
        raise RuntimeError('Catálogo distinto de 141 productos.')
    user=scalar('''SELECT min(u.id_usuario) FROM usuario u JOIN usuario_local ul USING(id_usuario)
      JOIN usuario_perfiles up USING(id_usuario) WHERE ul.id_local=4 AND ul.estado_registro=1
      AND up.id_perfil=2 AND up.estado_registro=1 AND u.estado_registro=1''')
    if user is None:
        raise RuntimeError('Falta gerente Sheraton.')
    candidates=rows('''SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,pv.precio
      FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
      WHERE pv.activo AND ic.activo AND pv.precio>0 AND NOT EXISTS(SELECT 1 FROM grupo_salsa gs
      WHERE gs.activo AND gs.id_presentacion_venta=pv.id_presentacion_venta) ORDER BY 1''')
    menu=[]
    omitted=[]
    for m in candidates:
        try:
            used=consumos([{**m,'cantidad':1,'opciones':[],'id_promocion':None,'selecciones_promocion':[]}])
            if used and all(q>0 for q in used.values()):
                menu.append(m)
            else:
                omitted.append(m['id_presentacion'])
        except Exception:
            # An invalid/incomplete recipe is excluded, never replaced by invented ingredients.
            omitted.append(m['id_presentacion'])
    if len(menu)<5:
        raise RuntimeError('Recetas válidas insuficientes.')
    return user,products,existing,days,menu,omitted


def audit(user,day):
    db.session.execute(text('''INSERT INTO actividad_usuario(id_usuario,modulo,accion,id_registro_afectado,
      descripcion,id_perfil_utilizado,id_local) VALUES(:u,'INVENTARIO_OPERATIVO','CARGAR_DEMO',4,:tag,2,4)'''),
      dict(u=user,tag=f'{TAG}:{day.isoformat()}'))


def apply(through):
    db.session.execute(text("SET LOCAL lock_timeout='8s'"))
    db.session.execute(text('LOCK TABLE '+','.join(TABLES)+' IN SHARE ROW EXCLUSIVE MODE'))
    db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext('inventario-dia:4'))"))
    user,products,existing,days,menu,omitted=inspect(through)
    prior={j['fecha']:j for j in existing}
    revised_ids=[prior[d]['id_jornada'] for d in days if d in prior]
    originals={}
    for table in TABLES:
        old=rows(f'SELECT * FROM {table} ORDER BY 1,2')
        if table=='inventario_jornada':
            old=[r for r in old if r['id_jornada'] not in revised_ids]
        key=next(iter(old[0])) if old else None
        originals[table]=(key,list({r[key] for r in old}) if key else [],digest(old))
    stocks=rows('SELECT * FROM inventario_stock_teorico ORDER BY 1,2')
    other_tables=('inventario_jornada','inventario_ronda','inventario_evento','orden_compra','salon_cobro','movimiento_inventario')
    other_before={t:digest(rows(f'SELECT * FROM {t} WHERE id_local<>4 ORDER BY 1,2')) for t in other_tables}
    productmap={p['id_producto']:p for p in products}
    created=[]
    for day in days:
        marker=f'{TAG}:{day.isoformat()}'
        if scalar("SELECT count(*) FROM actividad_usuario WHERE accion='CARGAR_DEMO' AND descripcion=:tag",tag=marker):
            raise RuntimeError('Marca aplicada sin jornada; inconsistencia a revisar.')
        opening=datetime.combine(day,datetime.min.time(),LIMA)+timedelta(hours=10)
        closing=opening+timedelta(hours=13)
        # Forward-only API cannot backdate after future closed dates. An explicit
        # missing-day insert preserves triggers, which use this one open day.
        previous=prior.get(day)
        if previous:
            jid=previous['id_jornada']
            db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=NULL,reporte=NULL WHERE id_jornada=:j'),dict(j=jid))
        else:
            jid=scalar('''INSERT INTO inventario_jornada(id_local,fecha,abierto_por,abierto_en)
              VALUES(4,:d,:u,:t) RETURNING id_jornada''',d=day,u=user,t=opening)
        current={r['id_producto']:r['stock_actual'] for r in stocks if r['id_local']==4}
        if not previous:
            bulk('INSERT INTO inventario_jornada_inicio VALUES(:j,:p,:q)',[dict(j=jid,p=p,q=q) for p,q in current.items()])
        event_floor=scalar('SELECT coalesce(max(id_evento),0) FROM inventario_evento')
        already={r['id_presentacion'] for r in rows('''SELECT DISTINCT (line->>'id_presentacion')::int id_presentacion
          FROM salon_cobro c CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') line
          WHERE c.id_local=4 AND c.id_jornada=:j''',j=jid)}
        batch=rotating_menu(menu,day,already)
        lines=[{**m,'cantidad':1+((day-START).days//7)%3+(index+day.day)%2+
                (3 if day.weekday() in (4,5) else 0),
                'id_promocion':None,'selecciones_promocion':[],'opciones':[]} for index,m in enumerate(batch)]
        if not lines:
            raise RuntimeError('Rotación vacía: revisar sin crear cobro sin contenido.')
        for line in lines:
            line['comentario']=marker+' · VENTA FICTICIA LOCAL'
        portions=[[dict(line) for index,line in enumerate(lines) if index%2==slot] for slot in range(2)]
        amounts=[{p:q.quantize(Decimal('.001')) for p,q in consumos(sold).items()} for sold in portions]
        incoming=defaultdict(Decimal)
        for used in amounts:
            for p,q in used.items():
                incoming[p]+=q
        order=scalar('''INSERT INTO orden_compra(codigo,estado_orden_compra,usuario_registro,fecha_registro,id_local)
          VALUES(:code,'ENVIADA',:u,:d,4) RETURNING id_orden_compra''',code=f'DSHC-{day:%Y%m%d}',u=user,d=day)
        groups=defaultdict(list)
        for pid,q in incoming.items():
            groups[productmap[pid]['id_proveedor']].append((pid,q))
        bulk('''INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada,id_proveedor)
          VALUES(:o,:p,:q,:v)''',[dict(o=order,p=p,q=q,v=v) for v,items in groups.items() for p,q in items])
        for provider,items in groups.items():
            rid=scalar('''INSERT INTO factura_recepcion(id_orden_compra,id_proveedor,numero_factura,fecha_recepcion,usuario_recepcion)
              VALUES(:o,:v,:code,:d,:u) RETURNING id_factura_recepcion''',o=order,v=provider,
              code=f'DEMO-DSHC-{day:%Y%m%d}-{provider}',d=day,u=user)
            bulk('''INSERT INTO factura_recepcion_detalle(id_factura_recepcion,id_producto,cantidad_recibida)
              VALUES(:r,:p,:q)''',[dict(r=rid,p=p,q=q) for p,q in items])
        db.session.execute(text("UPDATE orden_compra SET estado_orden_compra='RECEPCIONADA' WHERE id_orden_compra=:o"),dict(o=order))
        db.session.execute(text('''INSERT INTO orden_compra_estado_historial(id_orden_compra,estado_anterior,estado_nuevo,
          motivo,usuario_modificacion,fecha_modificacion) VALUES(:o,'ENVIADA','RECEPCIONADA',:note,:u,:t)'''),
          dict(o=order,note=marker+' · recepción ficticia sin envío externo',u=user,t=opening.replace(tzinfo=None)))
        for slot,sold in enumerate(portions):
            moment=opening+timedelta(hours=7+slot*3)
            key=str(uuid.uuid5(uuid.NAMESPACE_URL,f'{marker}:{slot}'))
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
              RETURNING id_movimiento_inventario''',code=f'DSHC-V-{day:%Y%m%d}-{slot}',d=day,u=user,
              note=marker+' · consumo ficticio de recetas',t=moment.replace(tzinfo=None))
            bulk('INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:m,:p,:q)',
              [dict(m=move,p=p,q=q) for p,q in amounts[slot].items()])
            total=sum(line['precio']*line['cantidad'] for line in sold)
            snapshot=serial(dict(tipo='BOLETA',metodo='EFECTIVO',documento='',cliente='',local='Sheraton',mesa='M01',
              total=total,fiscal=False,lineas=sold,prueba=marker,nota='FICTICIO LOCAL; NO EMISIÓN FISCAL'))
            paid=scalar('''INSERT INTO salon_cobro(id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,total,comprobante,id_movimiento,creado_en)
              VALUES(4,:u,'M01',CAST(:key AS uuid),:h,'BOLETA','EFECTIVO',:total,CAST(:r AS jsonb),:m,:t) RETURNING id_cobro''',
              u=user,key=key,h=hashed,total=total,r=json.dumps(snapshot),m=move,t=moment)
            db.session.execute(text('INSERT INTO salon_cobro_pedido VALUES(:p,:c)'),dict(p=pid,c=paid))
        db.session.execute(text('UPDATE inventario_evento SET registrado_en=:t WHERE id_jornada=:j AND id_evento>:floor'),
          dict(t=closing-timedelta(hours=1),j=jid,floor=event_floor))
        content=reporte(dict(id_jornada=jid,id_local=4))
        expected={p['id_producto']:Decimal(str(p['final'])) for p in previous['reporte']['inventario']} if previous else current
        if len(content['inventario'])!=141 or any(abs(Decimal(str(p['final']))-expected[p['id_producto']])>Decimal('.0001') for p in content['inventario']):
            raise RuntimeError('Nuevo cierre no concilia stock inicial=final.')
        content.update(prueba=marker,nota='FICTICIO LOCAL: compras iguales a consumo, sin cambio de stock actual.',
          revision_demo=dict(marca=marker,reporte_anterior_sha256=digest(previous['reporte']) if previous else None))
        db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=:t,cerrado_por=:u,reporte=CAST(:r AS jsonb) WHERE id_jornada=:j'),
          dict(t=previous['cerrado_en'] if previous else closing,u=previous['cerrado_por'] if previous else user,r=json.dumps(content),j=jid))
        if previous:
            restored=rows('SELECT * FROM inventario_jornada WHERE id_jornada=:j',j=jid)[0]
            if {k:v for k,v in restored.items() if k!='reporte'}!={k:v for k,v in previous.items() if k!='reporte'}:
                raise RuntimeError('Metadatos originales del cierre alterados.')
            audit(user,day)
            created.append(dict(fecha=day,jornada=jid,reporte_demo_completado=True,productos=141,cobros=2,
              presentaciones=len(lines),insumos_consumidos=len(incoming)))
            continue
        rid=scalar('''INSERT INTO inventario_ronda(id_local,nombre,creado_por,creado_en,cerrado_en)
          VALUES(4,:n,:u,:t,:t) RETURNING id_ronda''',n=f'DEMO - Sheraton {day:%d/%m/%Y}',u=user,t=closing)
        bulk('''INSERT INTO inventario_conteo(id_ronda,id_producto,teorico,contado,contado_por,contado_en,estado,
          observacion,revisado_por,revisado_en,justificacion,justificado_por,justificado_en,contado_perfil,contado_perfil_nombre)
          VALUES(:r,:p,:q,:q,:u,:t,'REVISADO',:n,:u,:t,:why,:u,:t,2,'Gerente')''',
          [dict(r=rid,p=p,q=q,u=user,t=closing,n=marker+' · conteo FICTICIO, no observación física',
            why=marker+' · igualdad simulada con saldo teórico; sin ajuste') for p,q in current.items()])
        db.session.execute(text('''INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo,creado_en)
          SELECT id_ronda,id_producto,:u,'revisar','{}'::jsonb,to_jsonb(c),:t FROM inventario_conteo c WHERE id_ronda=:r'''),dict(u=user,t=closing,r=rid))
        audit(user,day)
        created.append(dict(fecha=day,jornada=jid,ronda=rid,productos=141,cobros=2,presentaciones=len(lines),insumos_consumidos=len(incoming)))
    for table,(key,identities,before) in originals.items():
        after=rows(f'SELECT * FROM {table} WHERE {key}=ANY(:ids) ORDER BY 1,2',ids=identities) if key else []
        if digest(after)!=before:
            raise RuntimeError('Registro previo modificado en '+table)
    if stocks!=rows('SELECT * FROM inventario_stock_teorico ORDER BY 1,2'):
        raise RuntimeError('Stock actual cambiado; se revierte.')
    other_after={t:digest(rows(f'SELECT * FROM {t} WHERE id_local<>4 ORDER BY 1,2')) for t in other_tables}
    if other_before!=other_after:
        raise RuntimeError('Otra sede cambiada; se revierte.')
    coverage=rows('''SELECT fecha,jsonb_array_length(reporte->'inventario') productos,cerrado_en IS NOT NULL cerrado
      FROM inventario_jornada WHERE id_local=4 AND fecha BETWEEN :s AND :e ORDER BY fecha''',s=START,e=through)
    if len(coverage)!=(through-START).days+1 or any(c['productos']!=141 or not c['cerrado'] for c in coverage):
        raise RuntimeError('Cobertura diaria incompleta.')
    return dict(desde=START,hasta=through,dias=len(coverage),productos=141,lineas_diarias=len(coverage)*141,
      creados=created,recetas_elegibles=len(menu),recetas_omitidas=omitted,stock_actual_sin_cambios=True,
      registros_fuente_previos_preservados=True,reportes_demo_completados=len(revised_ids),
      otras_sedes_antes=other_before,otras_sedes_despues=other_after)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--through',type=date.fromisoformat,default=datetime.now(LIMA).date()-timedelta(days=1))
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    with create_app().app_context():
        _,products,existing,days,menu,omitted=inspect(args.through)
        print(json.dumps(serial(dict(modo='aplicar' if args.apply else 'solo_plan',desde=START,hasta=args.through,
          dias=(args.through-START).days+1,productos=len(products),fechas_a_completar=days,
          recetas_elegibles=len(menu),recetas_omitidas=omitted,cobros_nuevos=len(days)*2,
          nota='Solo reportes DEMO probados se completan con rotación semanal; fuentes originales intactas. Sin respaldo ni archivos adicionales.'))))
        db.session.rollback()
        if not args.apply or not days:
            return
        try:
            result=apply(args.through)
            db.session.commit()
        except Exception:
            db.session.rollback()
            raise
        print(json.dumps(serial(result),ensure_ascii=True))


if __name__=='__main__':
    main()
