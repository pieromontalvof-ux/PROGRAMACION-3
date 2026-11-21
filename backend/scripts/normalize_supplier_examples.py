"""Normalize synthetic invoices, preserving gross totals, stock and provenance."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parents[1]/'.env')
from app import create_app
from app.core.extensions import db
from sqlalchemy import text
import json
from app.modules.recepciones.invoices import calcular_factura
with create_app().app_context():
 if '--apply' not in sys.argv: raise SystemExit('Usa --apply para corregir únicamente los ejemplos locales.')
 if db.engine.url.host not in ('localhost','127.0.0.1','::1'): raise RuntimeError('Solo base local.')
 providers=db.session.execute(text('SELECT id_proveedor,nombre,datos_comerciales FROM proveedor ORDER BY id_proveedor')).mappings().all()
 profiles={}
 for p in providers:
  i=p['id_proveedor'];d=dict(p['datos_comerciales'] or {})
  if not d.get('ruc'):
   prefix=f'2099{i:06d}';v=11-sum(int(a)*b for a,b in zip(prefix,[5,4,3,2,7,6,5,4,3,2]))%11;d['ruc']=prefix+str(0 if v==10 else 1 if v==11 else v)
  if not d.get('direccion') or 'fictici' in d['direccion'].lower():d['direccion']=f'Av. Los Industriales {150+i*23}, Lima'
  if not d.get('contacto') or 'demostraci' in d['contacto'].lower():d['contacto']=f'Área comercial · {p["nombre"]}'
  profiles[i]={'nombre':p['nombre'],**d}
  db.session.execute(text('UPDATE proveedor SET datos_comerciales=CAST(:d AS jsonb) WHERE id_proveedor=:id'),dict(d=json.dumps(d),id=i))
 invoices=db.session.execute(text("SELECT id_factura_recepcion,id_proveedor,datos_factura FROM factura_recepcion WHERE datos_factura->>'datos_ficticios'='true' OR numero_factura LIKE 'DEMO%' OR numero_factura LIKE 'DSHI-%'")).mappings().all()
 for f in invoices:
  old=f['datos_factura']
  if not old:continue
  lines=[dict(id_producto=l['id_producto'],cantidad_facturada=l['cantidad_facturada'],costo_total=l['total'],afectacion_igv='GRAVADO',igv_porcentaje=18) for l in old['lineas']]
  new=calcular_factura(dict(fecha_emision=old['fecha_emision'],moneda=old['moneda'],lineas=lines))
  for n,l in zip(new['lineas'],old['lineas']):n.update({k:l[k] for k in ('nombre','codigo','unidad') if k in l})
  old.update(new);old['proveedor']=profiles[f['id_proveedor']];old['datos_ficticios']=True
  db.session.execute(text('UPDATE factura_recepcion SET datos_factura=CAST(:d AS jsonb) WHERE id_factura_recepcion=:id'),dict(d=json.dumps(old),id=f['id_factura_recepcion']))
 db.session.commit();print(f'Perfiles completos: {len(profiles)}. Facturas de ejemplo corregidas: {len(invoices)}. Totales e inventario conservados.')
