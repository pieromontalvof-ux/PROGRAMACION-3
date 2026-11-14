"""Carga autorizada de pruebas de Miraflores, 01/10–03/11/2026.

Sin --apply solo inspecciona. Requiere respaldo privado para aplicar. No crea
ventas ni altera catálogos, otras sedes, órdenes previas o jornadas ya cerradas.
"""
import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, ROUND_CEILING
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
from dotenv import dotenv_values
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from psycopg2.extras import execute_batch

ROOT=Path(__file__).resolve().parents[2]
TAG='DEMO-MIR-20261001-1103'
START=date(2026,10,1); END=date(2026,11,3)
LIMA=timezone(timedelta(hours=-5))
PRIVATE=ROOT/'backend/instance/migration_backups/miraflores-20261103'

def serial(v):
    return json.loads(json.dumps(v,default=lambda x:float(x) if isinstance(x,Decimal) else x.isoformat() if isinstance(x,(date,datetime)) else str(x)))

def rows(c,sql,**p):return [dict(r) for r in c.execute(text(sql),p).mappings()]
def scalar(c,sql,**p):return c.execute(text(sql),p).scalar_one()
def bulk(c,sql,items):
    if not items:return
    statement=re.sub(r'(?<!:):(\w+)',lambda m:'%('+m.group(1)+')s',sql)
    with c.connection.driver_connection.cursor() as cursor:
        execute_batch(cursor,statement,items,page_size=500)
def digest(v):return hashlib.sha256(json.dumps(serial(v),sort_keys=True).encode()).hexdigest()
def dates():return [START+timedelta(days=i) for i in range((END-START).days+1)]

def backup(url):
    PRIVATE.mkdir(parents=True,exist_ok=True)
    target=PRIVATE/(datetime.now().strftime('%Y%m%d-%H%M%S')+'.dump')
    u=make_url(url)
    command=[r'C:/Program Files/PostgreSQL/18/bin/pg_dump.exe','-h',u.host,'-p',str(u.port or 5432),'-U',u.username,'-d',u.database,'-Fc','--no-owner','--no-privileges','-f',str(target)]
    result=subprocess.run(command,env={**os.environ,'PGPASSWORD':u.password or ''},capture_output=True)
    if result.returncode or not target.exists() or target.stat().st_size<1000:
        raise RuntimeError('No se pudo respaldar; no se aplica la carga.')
    return target

def inspect(c):
    local=scalar(c,"SELECT id_local FROM local WHERE lower(nombre)='miraflores' AND estado_registro=1")
    days=rows(c,'SELECT * FROM inventario_jornada WHERE id_local=:l ORDER BY fecha',l=local)
    if any(d['fecha']>END for d in days):raise RuntimeError('Ya hay jornadas posteriores al periodo solicitado.')
    if scalar(c,"SELECT count(*) FROM actividad_usuario WHERE descripcion=:tag AND accion='CARGAR_DEMO'",tag=TAG):raise RuntimeError('Lote ya aplicado. No se duplica.')
    if scalar(c,'SELECT count(*) FROM salon_pedido_actual WHERE id_local=:l',l=local):raise RuntimeError('Hay pedidos de salón abiertos; no se cierran automáticamente.')
    if scalar(c,'SELECT count(*) FROM inventario_ronda WHERE id_local=:l AND cerrado_en IS NULL',l=local):raise RuntimeError('Hay un conteo abierto; no se reemplaza.')
    manager=scalar(c,'''SELECT min(u.id_usuario) FROM usuario u JOIN usuario_local ul USING(id_usuario)
      JOIN usuario_perfiles up USING(id_usuario) WHERE ul.id_local=:l AND ul.estado_registro=1
      AND up.id_perfil=2 AND up.estado_registro=1 AND u.estado_registro=1''',l=local)
    if manager is None:raise RuntimeError('Falta responsable gerente del local.')
    products=rows(c,'''SELECT p.id_producto,p.nombre,p.codigo,p.unidad,p.presentacion,p.id_proveedor,
      s.stock_actual FROM producto p JOIN inventario_stock_teorico s USING(id_producto)
      WHERE p.activo AND s.id_local=:l ORDER BY p.id_producto''',l=local)
    return local,manager,days,products

def stock(c,local):return {r['id_producto']:r['stock_actual'] for r in rows(c,'SELECT id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=:l ORDER BY id_producto',l=local)}

def report(c,jid,local):
    products=rows(c,'''SELECT p.id_producto,p.codigo,p.nombre,p.unidad,coalesce(i.cantidad,0) inicial,
      coalesce(e.entradas,0) entradas,coalesce(e.salidas,0) salidas,
      coalesce(i.cantidad,0)+coalesce(e.entradas,0)-coalesce(e.salidas,0) final
      FROM producto p LEFT JOIN inventario_jornada_inicio i ON i.id_producto=p.id_producto AND i.id_jornada=:j
      LEFT JOIN (SELECT id_producto,sum(greatest(cantidad,0)) entradas,sum(greatest(-cantidad,0)) salidas
      FROM inventario_evento WHERE id_jornada=:j GROUP BY id_producto)e ON e.id_producto=p.id_producto
      WHERE i.id_producto IS NOT NULL OR e.id_producto IS NOT NULL OR p.activo ORDER BY p.nombre''',j=jid)
    reasons=rows(c,'''SELECT id_producto,motivo,sum(greatest(cantidad,0)) entradas,sum(greatest(-cantidad,0)) salidas
      FROM inventario_evento WHERE id_jornada=:j GROUP BY id_producto,motivo ORDER BY motivo''',j=jid)
    for p in products:p['motivos']=[m for m in reasons if m['id_producto']==p['id_producto']]
    sales=rows(c,'''SELECT (linea->>'id_presentacion')::integer id_presentacion,linea->>'nombre' nombre,NULL::integer hora,
      sum((linea->>'cantidad')::numeric) cantidad,sum((linea->>'cantidad')::numeric*(linea->>'precio')::numeric) total
      FROM salon_cobro c CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') linea
      WHERE c.id_local=:l AND c.id_jornada=:j GROUP BY 1,2 ORDER BY cantidad DESC,total DESC,nombre''',l=local,j=jid)
    return serial({'inventario':products,'ventas':sales})

def audit(c,local,user,module,action,identity,description,moment):
    c.execute(text('''INSERT INTO actividad_usuario(id_usuario,modulo,accion,id_registro_afectado,descripcion,
      id_perfil_utilizado,id_local,fecha_actividad) VALUES(:u,:m,:a,:i,:d,2,:l,:t)'''),
      dict(u=user,m=module,a=action,i=identity,d=description,l=local,t=moment.replace(tzinfo=None)))

def apply(c):
    c.execute(text("SET LOCAL lock_timeout='8s'"));c.execute(text("SET LOCAL statement_timeout='30s'"))
    c.execute(text('''LOCK TABLE inventario_jornada,inventario_jornada_inicio,inventario_evento,
      inventario_ronda,inventario_conteo,inventario_conteo_historial,orden_compra,orden_compra_detalle,
      orden_compra_estado_historial,factura_recepcion,factura_recepcion_detalle,movimiento_inventario,
      movimiento_inventario_detalle,salon_pedido,salon_cobro,producto,actividad_usuario IN SHARE ROW EXCLUSIVE MODE'''))
    local,user,existing,products=inspect(c)
    c.execute(text("SELECT pg_advisory_xact_lock(hashtext(:key))"),dict(key=f'inventario-dia:{local}'))
    protected={}
    for table in ['inventario_jornada','inventario_ronda','inventario_evento','orden_compra','movimiento_inventario','salon_cobro','inventario_saldo_inicial']:
        protected[table]=digest(rows(c,f'SELECT * FROM {table} WHERE id_local<>:l ORDER BY 1,2',l=local))
    closed=[d for d in existing if d['cerrado_en'] is not None]
    old_orders=rows(c,'SELECT * FROM orden_compra WHERE id_local=:l ORDER BY id_orden_compra',l=local)
    old_sales=digest(rows(c,'SELECT * FROM salon_cobro ORDER BY id_cobro'))
    before=stock(c,local);delta=defaultdict(Decimal)
    chosen=[p for p in products if p['codigo'] in ['V-001','V-002','V-003','V-004','V-005','V-007','V-008','S-001','S-012','S-019','S-020','SS-001','SS-002','C-009','B-001','B-002','CV-007','CV-009','CV-035','S-027']]
    if len(chosen)<15:raise RuntimeError('El catálogo cambió; revisar selección.')
    reasons=['Deterioro de perecibles (simulado)','Pérdida de preparación (simulada)','Rotura o derrame (simulado)','Vencimiento de prueba (simulado)']
    counts={'ordenes':0,'recepciones':0,'mermas':0,'jornadas_nuevas':0,'jornadas_existentes_cerradas':0,'cierres_preservados':len([d for d in closed if START<=d['fecha']<=END]),'inventarios':0,'lineas_conteo':0,'eventos_nuevos':0}
    ids={k:[] for k in ['ordenes','recepciones','mermas','jornadas','rondas']}
    schedule=[]
    for day in dates():
        existing_day=next((d for d in existing if d['fecha']==day),None)
        opening=datetime.combine(day,datetime.min.time(),LIMA)+timedelta(hours=10)
        closing=opening+timedelta(hours=13,minutes=50)
        if existing_day and existing_day['cerrado_en']:
            content=existing_day['reporte']
            if not content or not content.get('inventario'):raise RuntimeError('Cierre histórico sin inventario verificable.')
        else:
            if existing_day:
                jid=existing_day['id_jornada'];counts['jornadas_existentes_cerradas']+=1
            else:
                jid=scalar(c,'SELECT inventario_abrir_jornada(:l,:u,:d)',l=local,u=user,d=day)
                if scalar(c,'SELECT fecha FROM inventario_jornada WHERE id_jornada=:j',j=jid)!=day:raise RuntimeError('Fecha operativa distinta.')
                c.execute(text('UPDATE inventario_jornada SET abierto_en=:t WHERE id_jornada=:j'),dict(t=opening,j=jid))
                counts['jornadas_nuevas']+=1
            ids['jornadas'].append(jid)
            # Reposición semanal; las recepciones, no las órdenes, crean stock.
            if day.weekday()==0 or (existing_day and day==max(d['fecha'] for d in existing)):
                order=scalar(c,'''INSERT INTO orden_compra(codigo,estado_orden_compra,usuario_registro,fecha_registro,id_local)
                  VALUES(:code,'ENVIADA',:u,:d,:l) RETURNING id_orden_compra''',code=f'DMIR-{day:%Y%m%d}',u=user,d=day,l=local)
                ids['ordenes'].append(order);counts['ordenes']+=1
                current=stock(c,local);groups=defaultdict(list)
                for p in chosen:
                    # Pequeños lotes semanales, múltiplos exactos de la presentación.
                    lots=Decimal(1 if p['presentacion']>=5 else 2)
                    if current[p['id_producto']]<0:
                        lots+=(-current[p['id_producto']]/p['presentacion']).to_integral_value(rounding=ROUND_CEILING)
                    quantity=p['presentacion']*lots
                    c.execute(text('''INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada,id_proveedor)
                      VALUES(:o,:p,:q,:v)'''),dict(o=order,p=p['id_producto'],q=quantity,v=p['id_proveedor']))
                    groups[p['id_proveedor']].append((p,quantity))
                for provider,items in groups.items():
                    receipt=scalar(c,'''INSERT INTO factura_recepcion(id_orden_compra,id_proveedor,numero_factura,fecha_recepcion,usuario_recepcion)
                      VALUES(:o,:v,:code,:d,:u) RETURNING id_factura_recepcion''',o=order,v=provider,code=f'DEMO-MIR-{day:%Y%m%d}-{provider}',d=day,u=user)
                    ids['recepciones'].append(receipt);counts['recepciones']+=1
                    bulk(c,'''INSERT INTO factura_recepcion_detalle(id_factura_recepcion,id_producto,cantidad_recibida)
                      VALUES(:r,:p,:q)''',[dict(r=receipt,p=p['id_producto'],q=q) for p,q in items])
                    for p,q in items:delta[p['id_producto']]+=q
                c.execute(text("UPDATE orden_compra SET estado_orden_compra='RECEPCIONADA',usuario_modificacion=:u,fecha_modificacion=:t WHERE id_orden_compra=:o"),dict(u=user,t=opening.replace(tzinfo=None),o=order))
                c.execute(text('''INSERT INTO orden_compra_estado_historial(id_orden_compra,estado_anterior,estado_nuevo,motivo,usuario_modificacion,fecha_modificacion)
                  VALUES(:o,'ENVIADA','RECEPCIONADA',:reason,:u,:t)'''),dict(o=order,reason=TAG+' - recepción ficticia completa, sin envío externo',u=user,t=opening.replace(tzinfo=None)))
                audit(c,local,user,'COMPRAS','COMPRA_PRUEBA',order,TAG+' - compra y recepción simuladas',opening)
            movement=scalar(c,'''INSERT INTO movimiento_inventario(codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local,observacion,registrado_en)
              VALUES(:code,'SALIDA','MERMA',:d,:u,:l,:note,:t) RETURNING id_movimiento_inventario''',
              code=f'MMIR-{day:%Y%m%d}',d=day,u=user,l=local,note=TAG+' - '+reasons[(day-START).days%4],t=(opening+timedelta(hours=11)).replace(tzinfo=None))
            current=stock(c,local);waste=[]
            for offset in range(4):
                p=chosen[((day-START).days*3+offset)%len(chosen)]
                wanted=Decimal(1) if p['unidad']=='C62' else Decimal('0.05')*(((day-START).days+offset)%4+1)
                available=current[p['id_producto']]
                quantity=min(wanted,max(Decimal(0),available)).quantize(Decimal('.001'))
                if quantity>0:waste.append(dict(m=movement,p=p['id_producto'],q=quantity));delta[p['id_producto']]-=quantity
            if not waste:raise RuntimeError('No hay existencias para las mermas; no se genera salida vacía.')
            bulk(c,'INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:m,:p,:q)',waste)
            ids['mermas'].append(movement);counts['mermas']+=1
            # El evento mantiene la fecha simulada, sin cambiar triggers ni datos previos.
            c.execute(text('''UPDATE inventario_evento SET registrado_en=:t WHERE id_jornada=:j AND
              ((origen='MOVIMIENTO' AND id_origen=:m) OR (origen='RECEPCION' AND id_origen=ANY(:rs)))'''),
              dict(t=opening+timedelta(hours=11),j=jid,m=movement,rs=ids['recepciones'] or [0]))
            content=report(c,jid,local)
            assert all(Decimal(str(p['inicial']))+Decimal(str(p['entradas']))-Decimal(str(p['salidas']))==Decimal(str(p['final'])) for p in content['inventario'])
            expected=stock(c,local)
            assert all(abs(expected[p['id_producto']]-Decimal(str(p['final'])))<Decimal('.001') for p in content['inventario'])
            c.execute(text('''UPDATE inventario_jornada SET cerrado_en=:t,cerrado_por=:u,reporte=CAST(:r AS jsonb) WHERE id_jornada=:j'''),dict(t=closing,u=user,r=json.dumps(content),j=jid))
            audit(c,local,user,'INVENTARIO_OPERATIVO','CIERRE_PRUEBA',jid,TAG+' - cierre con inventario teórico; no es verificación física',closing)
        # Conteo simulado por día: no ajusta el saldo teórico.
        rid=scalar(c,'''INSERT INTO inventario_ronda(id_local,nombre,creado_por,creado_en,cerrado_en)
          VALUES(:l,:name,:u,:t,:close) RETURNING id_ronda''',l=local,name=f'DEMO - Inventario Miraflores {day:%d/%m/%Y}',u=user,t=closing-timedelta(minutes=35),close=closing)
        ids['rondas'].append(rid);counts['inventarios']+=1
        inventory=[]
        for p in content['inventario']:
            theoretical=Decimal(str(p['final']));counted=max(Decimal(0),theoretical)
            inventory.append(dict(r=rid,p=p['id_producto'],v=theoretical,q=counted,u=user,t=closing-timedelta(minutes=10),note=TAG+' - conteo ficticio, no observación física',reason=TAG+' - igualdad simulada' if theoretical>=0 else TAG+' - saldo negativo preexistente, sin ajuste'))
        bulk(c,'''INSERT INTO inventario_conteo(id_ronda,id_producto,teorico,contado,contado_por,contado_en,estado,observacion,revisado_por,revisado_en,justificacion,justificado_por,justificado_en,contado_perfil,contado_perfil_nombre)
          VALUES(:r,:p,:v,:q,:u,:t,'REVISADO',:note,:u,:t,:reason,:u,:t,2,'Gerente')''',inventory)
        c.execute(text('''INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo,creado_en)
          SELECT id_ronda,id_producto,:u,'revisar','{}'::jsonb,to_jsonb(c),:t FROM inventario_conteo c WHERE id_ronda=:r'''),dict(u=user,t=closing,r=rid))
        counts['lineas_conteo']+=len(inventory)
        schedule.append({'fecha':str(day),'jornada_existente':bool(existing_day),'inventario':rid})
        print('Día preparado:',day,flush=True)
    after=stock(c,local)
    assert all(after[p]==v+delta[p] for p,v in before.items())
    assert all(after[p]>=min(Decimal(0),v) for p,v in before.items())
    for table,value in protected.items():assert digest(rows(c,f'SELECT * FROM {table} WHERE id_local<>:l ORDER BY 1,2',l=local))==value,table
    for d in closed:assert rows(c,'SELECT * FROM inventario_jornada WHERE id_jornada=:j',j=d['id_jornada'])[0]==d
    for o in old_orders:assert rows(c,'SELECT * FROM orden_compra WHERE id_orden_compra=:o',o=o['id_orden_compra'])[0]==o
    assert old_sales==digest(rows(c,'SELECT * FROM salon_cobro ORDER BY id_cobro'))
    assert scalar(c,'SELECT count(*) FROM inventario_jornada WHERE id_local=:l AND fecha BETWEEN :s AND :e AND cerrado_en IS NOT NULL',l=local,s=START,e=END)==34
    counts['eventos_nuevos']=scalar(c,"SELECT count(*) FROM inventario_evento WHERE (origen='MOVIMIENTO' AND id_origen=ANY(:ms)) OR (origen='RECEPCION' AND id_origen=ANY(:rs))",ms=ids['mermas'],rs=ids['recepciones'])
    audit(c,local,user,'INVENTARIO_OPERATIVO','CARGAR_DEMO',local,TAG,datetime.now(LIMA))
    return {'marca':TAG,'local':'Miraflores','desde':str(START),'hasta':str(END),'totales':counts,'ids':ids,'dias':schedule,
      'stock_antes':before,'stock_despues':after,'variacion':dict(delta),'ventas_nuevas':0,'otras_sedes_sin_cambios':True,'cierres_previos_sin_cambios':True}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');parser.add_argument('--test-url-file');args=parser.parse_args()
    cloud=dotenv_values(ROOT/'backend/.env.railway')['RAILWAY_DATABASE_URL']
    url=Path(args.test_url_file).read_text().strip() if args.test_url_file else cloud
    engine=create_engine(url,connect_args={'connect_timeout':20})
    with engine.connect() as c:
        c.execute(text('SET TRANSACTION READ ONLY'))
        local,user,existing,products=inspect(c)
        print(json.dumps({'marca':TAG,'local':local,'periodo':[str(START),str(END)],'cierres_preservados':sum(bool(d['cerrado_en']) and START<=d['fecha']<=END for d in existing),'jornada_abierta':[str(d['fecha']) for d in existing if not d['cerrado_en']],'productos':len(products),'modo':'aplicar' if args.apply else 'solo_plan'},ensure_ascii=True))
    if not args.apply:return
    saved=None if args.test_url_file else backup(url)
    with engine.begin() as c:result=apply(c)
    PRIVATE.mkdir(parents=True,exist_ok=True)
    destination=PRIVATE/('rehearsal.json' if args.test_url_file else 'resultado.json')
    destination.write_text(json.dumps(serial(result),ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result['totales']));print('Carga confirmada. Resultado:',destination)
    if saved:print('Respaldo previo:',saved)

if __name__=='__main__':main()
