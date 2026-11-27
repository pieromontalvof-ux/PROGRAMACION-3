"""Acciones de responsable: reautenticacion, traslado, reasignacion y anulacion."""
import re
from datetime import timedelta
from flask import Blueprint,jsonify,request
from flask_jwt_extended import jwt_required,create_access_token,decode_token
from sqlalchemy import bindparam, func, select
from werkzeug.exceptions import BadRequest,Forbidden,Conflict,Unauthorized
from werkzeug.security import check_password_hash
from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.extensions import db
from app.modules.salon.salon_orders import contexto,obtener
from app.modules.salon.salon_layout import leer
from app.modules.auditoria.service import registrar_actividad

salon_control_bp=Blueprint('salon_control',__name__)

@salon_control_bp.get('/estado-mesas')
@jwt_required()
def estado():
 s=contexto()
 mesas=db.session.execute(select(func.public.salon_mesas_control(bindparam('local')).table_valued(
     'mesa', 'id_usuario', 'usuario', 'desde',
 )),{'local':s['id_local']}).mappings().all()
 return jsonify(mesas=[{**dict(m),'desde':m['desde'].isoformat()} for m in mesas])

@salon_control_bp.post('/autorizar')
@jwt_required()
def autorizar():
 s=contexto();d=request.get_json(silent=True)
 if not isinstance(d,dict):raise BadRequest('Datos invalidos')
 accion=d.get('accion')
 if accion not in ('eliminar','mover','reasignar'):raise BadRequest('Accion invalida')
 if not perfil_tiene_capacidad(s['perfil'], 'supervisar_salon' if accion=='eliminar' else 'administrar_salon'):raise Forbidden('No tienes permiso para esta accion')
 pin=d.get('pin','')
 if not isinstance(pin,str) or not re.fullmatch(r'[0-9]{4}',pin):raise BadRequest('Ingresa tu PIN de 4 digitos')
 fila=db.session.execute(select(func.public.salon_bloquear_pin(bindparam('id')).table_valued(
     'id_usuario', 'pin_hash', 'version', 'fallos', 'bloqueado_hasta', 'actualizado_en', 'bloqueado',
 )),{'id':s['id_usuario']}).mappings().one()
 if fila['bloqueado'] or not check_password_hash(fila['pin_hash'],pin):
  if not fila['bloqueado']:
   db.session.execute(select(func.public.salon_fallo_pin(bindparam('id'))),{'id':s['id_usuario']})
  db.session.commit()
  raise Unauthorized('PIN incorrecto o bloqueado temporalmente')
 db.session.execute(select(func.public.salon_reiniciar_pin(bindparam('id'))),{'id':s['id_usuario']})
 token=create_access_token(identity=str(s['id_usuario']),expires_delta=timedelta(minutes=2),additional_claims={
  'tipo_token':'salon_autorizacion','accion':accion,'id_local':s['id_local'],'pin_version':fila['version'],'pin_actualizado':fila['actualizado_en'].isoformat()})
 db.session.commit();return jsonify(autorizacion=token)

def consumir(s,d,accion):
 if not perfil_tiene_capacidad(s['perfil'], 'supervisar_salon' if accion=='eliminar' else 'administrar_salon'):raise Forbidden('Accion no autorizada')
 try:t=decode_token(d.get('autorizacion',''))
 except Exception:raise Forbidden('Autoriza nuevamente con tu PIN')
 pin=db.session.execute(select(func.public.salon_pin_vigente(bindparam('id')).table_valued(
     'version', 'actualizado_en',
 )),{'id':s['id_usuario']}).mappings().one()
 if (t.get('tipo_token')!='salon_autorizacion' or t.get('accion')!=accion or t.get('sub')!=str(s['id_usuario']) or t.get('id_local')!=s['id_local'] or t.get('pin_version')!=pin['version'] or t.get('pin_actualizado')!=pin['actualizado_en'].isoformat()):raise Forbidden('La autorizacion no corresponde a esta accion o sesion')
 usado=db.session.execute(select(func.public.salon_consumir_autorizacion(bindparam('id'))),{'id':t['jti']}).scalar()
 if not usado:raise Conflict('Esta autorizacion ya fue utilizada. Ingresa de nuevo tu PIN.')

def bloquear(s,mesas):
 disponibles={e['codigo'] for e in leer(s['id_local'])['elementos'] if e['tipo']!='barra'}
 for mesa in sorted(set(mesas)):
  if mesa not in disponibles:raise BadRequest('Mesa no disponible en este local')
  db.session.execute(select(func.public.salon_bloqueo(bindparam('clave'))),{'clave':f"salon:{s['id_local']}:{mesa}"})

def pedidos(s,mesa):
 return db.session.execute(select(func.public.salon_pedidos(bindparam('local'), bindparam('mesa')).table_valued(
     'id_pedido', 'id_local', 'mesa', 'id_usuario', 'estado', 'version', 'creado_en', 'enviado_en',
     'envio_clave', 'envio_hash',
 )),{'local':s['id_local'],'mesa':mesa}).mappings().all()

@salon_control_bp.get('/miembros')
@jwt_required()
def miembros():
 s=contexto()
 if not perfil_tiene_capacidad(s['perfil'], 'administrar_salon'):raise Forbidden('Solo gerente')
 filas=db.session.execute(select(func.public.salon_meseros(bindparam('local')).table_valued(
     'id_usuario', 'nombre',
 )),{'local':s['id_local']}).mappings()
 return jsonify(usuarios=[dict(f) for f in filas])

@salon_control_bp.post('/mesas/<mesa>/<accion>')
@jwt_required()
def operar(mesa,accion):
 s=contexto(mesa);d=request.get_json(silent=True)
 if not isinstance(d,dict) or accion not in ('eliminar','mover','reasignar'):raise BadRequest('Accion invalida')
 try:
  # Mismo orden que el editor de distribucion y los envios: mapa, mesas, PIN.
  destino=d.get('destino') if accion=='mover' else mesa
  if not isinstance(destino,str):raise BadRequest('Selecciona la mesa destino')
  bloquear(s,[mesa,destino]);consumir(s,d,accion)
  filas=pedidos(s,mesa)
  if not filas:raise Conflict('La mesa ya no tiene pedidos')
  if accion=='eliminar':
   ids=d.get('ids_lineas')
   if not isinstance(ids,list) or not ids or len(ids)>1000 or any(type(i) is not int for i in ids) or len(ids)!=len(set(ids)):raise BadRequest('Selecciona un producto enviado')
   validas=db.session.execute(select(func.public.salon_lineas_anulables(bindparam('local'), bindparam('mesa'), bindparam('ids')).table_valued(
       'id_linea', 'nombre', 'cantidad',
   )),{'local':s['id_local'],'mesa':mesa,'ids':ids}).mappings().all()
   if len(validas)!=len(ids):raise Conflict('El producto cambio o ya fue eliminado. Recarga la mesa.')
   reposiciones=db.session.execute(select(func.public.salon_reposiciones_anulables(bindparam('ids')).table_valued(
       'id_linea', 'nombre', 'cantidad',
   )),{'ids':ids}).mappings().all()
   anulables=[*validas,*reposiciones]
   for linea in anulables:db.session.execute(select(func.public.salon_anular_linea(bindparam('id'), bindparam('usuario'))),{'id':linea['id_linea'],'usuario':s['id_usuario']})
   descripcion=f"Elimino de {mesa}: "+', '.join(f"{l['cantidad']} x {l['nombre']}" for l in anulables)
  else:
   if any(p['estado']=='BORRADOR' for p in filas):raise Conflict('Envia o cancela el borrador guardado antes de mover o reasignar')
   usuario=filas[0]['id_usuario']
   if accion=='mover':
    if destino==mesa or pedidos(s,destino):raise Conflict('Elige otra mesa que este libre')
    descripcion=f'Traslado {mesa} a {destino}; responsable {usuario}'
   else:
    usuario=d.get('id_usuario')
    if type(usuario) is not int:raise BadRequest('Selecciona un miembro de equipo')
    valido=db.session.execute(select(func.public.salon_mesero_bloqueado(bindparam('id'), bindparam('local'))),{'id':usuario,'local':s['id_local']}).scalar()
    if not valido:raise BadRequest('El miembro no tiene acceso activo a Salon en este local')
    descripcion=f"Reasigno {mesa}: usuario {filas[0]['id_usuario']} a usuario {usuario}"
   for p in filas:
    db.session.execute(select(func.public.salon_asignar_pedido(bindparam('id'), bindparam('mesa'), bindparam('usuario'))),{'id':p['id_pedido'],'mesa':destino,'usuario':usuario})
  registrar_actividad(s['id_usuario'],'SALON',accion.upper(),filas[0]['id_pedido'],descripcion,id_perfil_utilizado=s['perfil'],id_local=s['id_local'])
  db.session.commit()
  return jsonify(mensaje='Operacion registrada',pedido=obtener(mesa,s) if accion=='eliminar' else None)
 except Exception:
  db.session.rollback();raise
