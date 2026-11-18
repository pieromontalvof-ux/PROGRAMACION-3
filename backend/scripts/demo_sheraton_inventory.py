"""Inventarios FICTICIOS locales de Sheraton, 1 al 14 de noviembre de 2026.

Sin --apply inspecciona. Preserva cierres anteriores: los conteos ficticios del
1..10 son observaciones simuladas con diferencias justificadas, no ajustes del
saldo. La reposición del 11 abastece todos los productos mediante recepciones.
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

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
from app import create_app
from app.core.extensions import db
from app.modules.inventarios.operativo import reporte
from app.modules.auditoria.service import registrar_actividad
from sqlalchemy import text

TAG = 'DEMO-SHERATON-INVENTARIOS-20261101-14'
START, END = date(2026, 11, 1), date(2026, 11, 14)
LIMA = timezone(timedelta(hours=-5))


def serial(value):
    return json.loads(json.dumps(value,default=lambda v:float(v) if isinstance(v,Decimal)
                                else v.isoformat() if isinstance(v,(date,datetime)) else str(v)))


def dates():
    return [START + timedelta(days=i) for i in range(14)]


def fictional_count(product, day):
    """Cantidad positiva reproducible, variada y expresada en unidad base."""
    minimum = product['stock_minimo'] or product['presentacion'] or Decimal(1)
    base = max(Decimal('0.1'), minimum)
    factor = Decimal(['0.45', '0.8', '1.2', '2.5', '4'][product['id_producto'] % 5])
    variation = Decimal(100 + (product['id_producto'] * 7 + day.day * 3) % 25) / 100
    quantum = Decimal(1) if product['unidad'] == 'C62' else Decimal('.001')
    return max(quantum, (base * factor * variation).quantize(quantum, rounding=ROUND_CEILING))


def rows(sql, **params):
    return [dict(r) for r in db.session.execute(text(sql), params).mappings()]


def scalar(sql, **params):
    return db.session.execute(text(sql), params).scalar_one()


def digest(value):
    return hashlib.sha256(json.dumps(serial(value), sort_keys=True).encode()).hexdigest()


def stock():
    return {r['id_producto']: r['stock_actual'] for r in rows('SELECT id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=4 ORDER BY id_producto')}


def inspect():
    if db.engine.url.host not in ('localhost', '127.0.0.1', '::1'):
        raise RuntimeError('Solo se permite base local loopback.')
    if scalar("SELECT count(*) FROM local WHERE id_local=4 AND lower(nombre)='sheraton' AND estado_registro=1") != 1:
        raise RuntimeError('No corresponde al local Sheraton autorizado.')
    if scalar("SELECT count(*) FROM actividad_usuario WHERE descripcion=:tag AND accion='CARGAR_DEMO'", tag=TAG):
        raise RuntimeError('Lote ya aplicado; no se duplica.')
    if scalar('SELECT count(*) FROM inventario_jornada WHERE id_local=4 AND fecha>:d', d=date(2026,11,10)):
        raise RuntimeError('Hay jornadas posteriores al histórico esperado; revisar sin reemplazarlas.')
    if scalar('SELECT count(*) FROM inventario_ronda WHERE id_local=4 AND cerrado_en IS NULL'):
        raise RuntimeError('Hay un conteo abierto; se preserva.')
    products = rows('''SELECT p.id_producto,p.nombre,p.unidad,p.presentacion,p.id_proveedor,
      sl.stock_minimo,sl.stock_maximo FROM producto p
      LEFT JOIN producto_stock_local sl ON sl.id_producto=p.id_producto AND sl.id_local=4
      WHERE p.activo ORDER BY p.id_producto''')
    if len(products) != 141 or any(p['id_proveedor'] is None for p in products):
        raise RuntimeError('Catálogo distinto de los 141 insumos con proveedor esperados.')
    user = scalar('''SELECT min(u.id_usuario) FROM usuario u JOIN usuario_local ul USING(id_usuario)
      JOIN usuario_perfiles up USING(id_usuario) WHERE ul.id_local=4 AND ul.estado_registro=1
      AND up.id_perfil=2 AND up.estado_registro=1 AND u.estado_registro=1''')
    if user is None:
        raise RuntimeError('Falta gerente asignado a Sheraton.')
    return user, products


def backup():
    target = ROOT/'backend/instance/migration_backups'/TAG/datetime.now().strftime('%Y%m%d-%H%M%S')
    target.mkdir(parents=True, exist_ok=False)
    url = db.engine.url
    completed = subprocess.run([r'C:/Program Files/PostgreSQL/18/bin/pg_dump.exe', '-h', url.host,
        '-p', str(url.port or 5432), '-U', url.username, '-d', url.database, '-Fc', '--no-owner',
        '--no-privileges', '-f', str(target/'before.dump')],
        env={**os.environ,'PGPASSWORD':url.password or ''}, capture_output=True)
    if completed.returncode or not (target/'before.dump').exists() or (target/'before.dump').stat().st_size < 1000:
        raise RuntimeError('Respaldo falló; no se aplica.')
    return target


def audit(user, action, identity, description):
    registrar_actividad(user,'INVENTARIO_OPERATIVO',action,identity,TAG+' · '+description,
                       id_perfil_utilizado=2,id_local=4)


def apply():
    db.session.execute(text("SET LOCAL lock_timeout='8s'"))
    db.session.execute(text('''LOCK TABLE inventario_jornada,inventario_jornada_inicio,inventario_evento,
      inventario_ronda,inventario_conteo,inventario_conteo_historial,orden_compra,orden_compra_detalle,
      orden_compra_estado_historial,factura_recepcion,factura_recepcion_detalle,movimiento_inventario,
      movimiento_inventario_detalle,producto,producto_stock_local,actividad_usuario IN SHARE ROW EXCLUSIVE MODE'''))
    db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext('inventario-dia:4'))"))
    user, products = inspect()
    protected_tables = ('inventario_stock_teorico','inventario_jornada','inventario_evento','inventario_ronda',
                        'orden_compra','movimiento_inventario','salon_cobro','producto_stock_local','inventario_saldo_inicial')
    protected = {t:digest(rows(f'SELECT * FROM {t} WHERE id_local<>4 ORDER BY 1,2')) for t in protected_tables}
    closed = rows('SELECT * FROM inventario_jornada WHERE id_local=4 ORDER BY fecha')
    sales = digest(rows('SELECT * FROM salon_cobro ORDER BY id_cobro'))
    catalog = digest(rows('SELECT * FROM producto ORDER BY id_producto'))
    before = stock()
    delta = defaultdict(Decimal)
    ids = dict(jornadas=[],rondas=[],ordenes=[],recepciones=[],mermas=[])
    schedule = []
    for day in dates():
        opening = datetime.combine(day, datetime.min.time(), LIMA) + timedelta(hours=10)
        closing = opening + timedelta(hours=13)
        existing = next((j for j in closed if j['fecha']==day),None)
        if existing:
            if not existing['cerrado_en'] or not existing['reporte']:
                raise RuntimeError('Cierre previo no verificable; no se modifica.')
            content = existing['reporte']
        else:
            jid = scalar('SELECT inventario_abrir_jornada(4,:u,:d)',u=user,d=day)
            if scalar('SELECT fecha FROM inventario_jornada WHERE id_jornada=:j',j=jid) != day:
                raise RuntimeError('La jornada no corresponde a la fecha simulada.')
            ids['jornadas'].append(jid)
            db.session.execute(text('UPDATE inventario_jornada SET abierto_en=:t WHERE id_jornada=:j'),dict(t=opening,j=jid))
            if day.day == 11:
                order = scalar('''INSERT INTO orden_compra(codigo,estado_orden_compra,usuario_registro,fecha_registro,id_local)
                  VALUES('DSHI-20261111','ENVIADA',:u,:d,4) RETURNING id_orden_compra''',u=user,d=day)
                ids['ordenes'].append(order)
                groups = defaultdict(list)
                for p in products:
                    pid = p['id_producto']
                    quantum = Decimal(1) if p['unidad']=='C62' else Decimal('.001')
                    # Siempre una entrada; stock previo alto se preserva, no se reduce artificialmente.
                    quantity = max(p['presentacion'] or quantum, fictional_count(p,day)-before[pid])
                    quantity = quantity.quantize(quantum,rounding=ROUND_CEILING)
                    delta[pid] += quantity
                    db.session.execute(text('''INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada,id_proveedor)
                      VALUES(:o,:p,:q,:v)'''),dict(o=order,p=pid,q=quantity,v=p['id_proveedor']))
                    groups[p['id_proveedor']].append((pid,quantity))
                for provider, lines in groups.items():
                    receipt = scalar('''INSERT INTO factura_recepcion(id_orden_compra,id_proveedor,numero_factura,fecha_recepcion,usuario_recepcion)
                      VALUES(:o,:v,:code,:d,:u) RETURNING id_factura_recepcion''',o=order,v=provider,code=f'DSHI-20261111-{provider}',d=day,u=user)
                    ids['recepciones'].append(receipt)
                    for pid,quantity in lines:
                        db.session.execute(text('''INSERT INTO factura_recepcion_detalle(id_factura_recepcion,id_producto,cantidad_recibida)
                          VALUES(:r,:p,:q)'''),dict(r=receipt,p=pid,q=quantity))
                db.session.execute(text("UPDATE orden_compra SET estado_orden_compra='RECEPCIONADA',usuario_modificacion=:u,fecha_modificacion=:t WHERE id_orden_compra=:o"),dict(u=user,t=opening.replace(tzinfo=None),o=order))
                db.session.execute(text('''INSERT INTO orden_compra_estado_historial(id_orden_compra,estado_anterior,estado_nuevo,motivo,usuario_modificacion,fecha_modificacion)
                  VALUES(:o,'ENVIADA','RECEPCIONADA',:tag,:u,:t)'''),dict(o=order,tag=TAG+' · recepción ficticia sin envío externo',u=user,t=opening.replace(tzinfo=None)))
                audit(user,'COMPRA_PRUEBA',order,'reposición ficticia de todos los insumos')
            move = scalar('''INSERT INTO movimiento_inventario(codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local,observacion,registrado_en)
              VALUES(:code,'SALIDA','MERMA',:d,:u,4,:note,:t) RETURNING id_movimiento_inventario''',
              code=f'DSHI-M-{day:%Y%m%d}',d=day,u=user,note=TAG+' · merma ficticia de preparación',t=(closing-timedelta(hours=1)).replace(tzinfo=None))
            ids['mermas'].append(move)
            current = stock()
            for offset in range(4):
                p = products[((day.day-11)*4+offset)%len(products)]
                quantum = Decimal(1) if p['unidad']=='C62' else Decimal('.001')
                quantity = min(current[p['id_producto']]/Decimal(20), Decimal(1) if p['unidad']=='C62' else Decimal('.05')*(offset+1))
                quantity = quantity.quantize(quantum)
                if quantity > 0:
                    db.session.execute(text('INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:m,:p,:q)'),dict(m=move,p=p['id_producto'],q=quantity))
                    delta[p['id_producto']] -= quantity
            db.session.execute(text('UPDATE inventario_evento SET registrado_en=:t WHERE id_jornada=:j'),dict(t=closing-timedelta(hours=1),j=jid))
            content = reporte(dict(id_jornada=jid,id_local=4))
            current = stock()
            assert all(abs(current[p['id_producto']]-Decimal(str(p['final'])))<Decimal('.001') for p in content['inventario'])
            db.session.execute(text('UPDATE inventario_jornada SET cerrado_en=:t,cerrado_por=:u,reporte=CAST(:r AS jsonb) WHERE id_jornada=:j'),dict(t=closing,u=user,r=json.dumps(content),j=jid))
            audit(user,'CIERRE_PRUEBA',jid,'cierre ficticio conciliado con recepciones y mermas')
        theoretical = {p['id_producto']:Decimal(str(p['final'])) for p in content['inventario']}
        rid = scalar('''INSERT INTO inventario_ronda(id_local,nombre,creado_por,creado_en,cerrado_en)
          VALUES(4,:name,:u,:t,:close) RETURNING id_ronda''',name=f'DEMO · Inventario Sheraton {day:%d/%m/%Y}',u=user,t=closing-timedelta(minutes=40),close=closing)
        ids['rondas'].append(rid)
        differences = 0
        for p in products:
            value = theoretical[p['id_producto']]
            counted = fictional_count(p,day) if existing else value
            differences += counted != value
            justification = ('conteo ficticio retrospectivo; diferencia simulada sin ajuste del histórico ni del stock'
                             if counted != value else 'igualdad simulada con saldo teórico; no observación física')
            db.session.execute(text('''INSERT INTO inventario_conteo(id_ronda,id_producto,teorico,contado,contado_por,contado_en,estado,
              observacion,revisado_por,revisado_en,justificacion,justificado_por,justificado_en,contado_perfil,contado_perfil_nombre)
              VALUES(:r,:p,:v,:q,:u,:t,'REVISADO',:note,:u,:t,:reason,:u,:t,2,'Gerente')'''),
              dict(r=rid,p=p['id_producto'],v=value,q=counted,u=user,t=closing-timedelta(minutes=10),
                   note=TAG+' · conteo FICTICIO, no verificación física',reason=TAG+' · '+justification))
        db.session.execute(text('''INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo,creado_en)
          SELECT id_ronda,id_producto,:u,'revisar','{}'::jsonb,to_jsonb(c),:t FROM inventario_conteo c WHERE id_ronda=:r'''),dict(u=user,t=closing,r=rid))
        audit(user,'CONTEO_PRUEBA',rid,'141 insumos ficticios; sin ajuste de saldo')
        schedule.append(dict(fecha=day,ronda=rid,conteos=len(products),diferencias_simuladas=differences,cierre_previo_preservado=bool(existing)))
    after = stock()
    assert all(after[p]==v+delta[p] and after[p]>0 for p,v in before.items())
    assert len(ids['rondas'])==14
    assert scalar('SELECT count(*) FROM inventario_conteo WHERE id_ronda=ANY(:ids)',ids=ids['rondas'])==1974
    assert all(rows('SELECT * FROM inventario_jornada WHERE id_jornada=:j',j=j['id_jornada'])[0]==j for j in closed)
    assert sales==digest(rows('SELECT * FROM salon_cobro ORDER BY id_cobro'))
    assert catalog==digest(rows('SELECT * FROM producto ORDER BY id_producto'))
    for table, before_digest in protected.items():
        assert before_digest==digest(rows(f'SELECT * FROM {table} WHERE id_local<>4 ORDER BY 1,2')), table
    protected_after = {t:digest(rows(f'SELECT * FROM {t} WHERE id_local<>4 ORDER BY 1,2')) for t in protected_tables}
    daily_validation = rows('''SELECT j.fecha,count(*) productos,
        bool_and((p->>'inicial')::numeric+(p->>'entradas')::numeric-(p->>'salidas')::numeric=(p->>'final')::numeric) conciliado
        FROM inventario_jornada j CROSS JOIN LATERAL jsonb_array_elements(j.reporte->'inventario') p
        WHERE j.id_local=4 AND j.fecha BETWEEN :s AND :e GROUP BY j.fecha ORDER BY j.fecha''',s=START,e=END)
    assert len(daily_validation)==14 and all(v['productos']==141 and v['conciliado'] for v in daily_validation)
    registrar_actividad(user,'INVENTARIO_OPERATIVO','CARGAR_DEMO',4,TAG,id_perfil_utilizado=2,id_local=4)
    minimums = {p['id_producto']:p['stock_minimo'] or Decimal(0) for p in products}
    return dict(marca=TAG,local=4,desde=START,hasta=END,ids=ids,dias=schedule,inventarios=14,lineas_conteo=1974,
        productos_con_stock_positivo=sum(v>0 for v in after.values()),bajo_minimo=sum(v<minimums[p] for p,v in after.items()),
        sobre_minimo=sum(v>minimums[p] for p,v in after.items()),stock_antes=before,stock_despues=after,variacion=dict(delta),
        cierres_previos_preservados=len(closed),otras_sedes_sin_cambios=True,ventas_previas_sin_cambios=True,
        evidencia_otras_sedes_antes=protected,evidencia_otras_sedes_despues=protected_after,validacion_reportes=daily_validation,
        nota='1..10: conteos positivos simulados con diferencias justificadas, sin modificar cierres; 11: reposición ficticia; 11..14: cierre y conteo conciliados.')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    with create_app().app_context():
        user,products=inspect()
        print(json.dumps(dict(marca=TAG,local=4,host_local=True,inventarios=14,insumos=len(products),conteos=1974,modo='aplicar' if args.apply else 'solo_plan')))
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
        print(json.dumps({k:v for k,v in result.items() if k not in ('stock_antes','stock_despues','variacion','dias','ids')},default=str,ensure_ascii=True))
        print('Manifiesto y respaldo:',target)


if __name__=='__main__':
    main()
