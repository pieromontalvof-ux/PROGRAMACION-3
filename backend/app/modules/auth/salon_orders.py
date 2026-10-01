"""Pedidos de Salón: edición del borrador y envío inmutable por mesa/local."""
import hashlib
import uuid
import json
import re
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict, Forbidden
from app.core.extensions import db
from app.modules.auth.salon import validar_sesion_salon
from app.modules.auth.salon_layout import leer
from app.modules.auditoria.service import registrar_actividad

salon_orders_bp=Blueprint('salon_orders',__name__)


def nombre_presentacion(nombre):
    # También corrige nombres capturados en pedidos anteriores sin alterar sus registros.
    return re.sub(r'(\d+)\.0+(?=\s+(?:UNI|PORCIÓN|PORCION)\b)', r'\1', nombre)


def contexto(mesa=None):
    sesion=validar_sesion_salon()
    if mesa is not None:
        db.session.execute(text('SELECT pg_advisory_xact_lock_shared(hashtext(:clave))'),{'clave':f"salon-layout:{sesion['id_local']}"})
        if mesa not in {e['codigo'] for e in leer(sesion['id_local'])['elementos'] if e['tipo']!='barra'}:
            raise BadRequest('Mesa invalida')
    if not db.session.execute(text("SELECT to_regclass('public.salon_pedido') IS NOT NULL")).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260923_pedidos_salon.sql')
    if not db.session.execute(text("SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='salon_pedido' AND column_name='envio_clave')")).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260923_envios_adicionales_salon.sql')
    if not db.session.execute(text("SELECT to_regclass('public.salon_pedido_actual')")).scalar():
        raise Conflict('Ejecuta 20260923_control_salon.sql')
    return sesion


def catalogo():
    productos=[dict(p) for p in db.session.execute(text('''
      SELECT pv.id_presentacion_venta AS id,ic.nombre,pv.contenido,pv.unidad,pv.precio,
        cc.id_categoria_carta AS id_categoria,cc.nombre AS categoria
      FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
      JOIN categoria_carta cc USING(id_categoria_carta)
      WHERE pv.activo AND ic.activo AND cc.activo ORDER BY cc.nombre,ic.nombre,pv.contenido
    ''')).mappings()]
    grupos=db.session.execute(text('''SELECT gs.id_grupo_salsa,gs.id_presentacion_venta,
       gs.cantidad_maxima,gs.permite_repetir,gso.id_grupo_salsa_opcion AS id,
       p.nombre,gso.cantidad,p.unidad,gso.id_producto
       FROM grupo_salsa gs LEFT JOIN grupo_salsa_opcion gso ON gso.id_grupo_salsa=gs.id_grupo_salsa AND gso.activo
       LEFT JOIN producto p ON p.id_producto=gso.id_producto AND p.activo
       WHERE gs.activo ORDER BY gs.id_grupo_salsa,p.nombre''')).mappings().all()
    por_presentacion={}
    for g in grupos:
        grupo=por_presentacion.setdefault(g['id_presentacion_venta'],{
            'maximo':g['cantidad_maxima'],'repetir':g['permite_repetir'],'opciones':[]})
        if g['id'] and g['nombre']:
            grupo['opciones'].append({'id':g['id'],'nombre':g['nombre'],'id_producto':g['id_producto'],
                                     'cantidad':float(g['cantidad']),'unidad':g['unidad']})
    for p in productos:
        p['nombre']=f"{p['nombre']} · {format(p['contenido'].normalize(), 'f')} {p['unidad']}"
        p['precio']=float(p['precio'])
        p['contenido']=float(p['contenido'])
        p['grupo']=por_presentacion.get(p['id'])
    return productos


def obtener(mesa,sesion,escritura=False):
    db.session.execute(text('SELECT pg_advisory_xact_lock_shared(hashtext(:clave))'),{'clave':f"salon:{sesion['id_local']}:{mesa}"})
    pedidos=db.session.execute(text('SELECT * FROM salon_pedido_actual WHERE id_local=:local AND mesa=:mesa ORDER BY id_pedido'),
        {'local':sesion['id_local'],'mesa':mesa}).mappings().all()
    if any(p['id_usuario']!=sesion['id_usuario'] for p in pedidos) and (escritura or sesion.get('perfil') not in (2,3)):
        raise Forbidden('Esta mesa está siendo atendida por otro usuario')
    borrador=next((p for p in pedidos if p['estado']=='BORRADOR'),None)
    filas=db.session.execute(text('''SELECT l.id_linea,l.id_presentacion,l.nombre,l.precio,l.cantidad,l.comentario,l.opciones,
        p.estado='ENVIADO' AS enviada FROM salon_pedido_linea l JOIN salon_pedido_actual p USING(id_pedido)
        WHERE p.id_local=:local AND p.mesa=:mesa AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea) ORDER BY p.id_pedido,l.posicion'''),
        {'local':sesion['id_local'],'mesa':mesa}).mappings().all()
    enviados={}
    pendientes=[]
    total=0
    for fila in filas:
        l=dict(fila)
        l['nombre']=nombre_presentacion(l['nombre'])
        l['ids_lineas']=[l.pop('id_linea')]
        total+=l['precio']*l['cantidad']
        l['precio']=float(l['precio'])
        if l['enviada']:
            opciones=sorted(l['opciones'],key=lambda o: json.dumps(o,sort_keys=True))
            clave=(l['id_presentacion'],l['nombre'],l['precio'],l['comentario'],json.dumps(opciones,sort_keys=True))
            if clave in enviados:
                enviados[clave]['cantidad']+=l['cantidad']
                enviados[clave]['ids_lineas']+=l['ids_lineas']
            else: enviados[clave]=l
        else: pendientes.append(l)
    fecha=next((p['enviado_en'] for p in reversed(pedidos) if p['enviado_en']),None)
    return {'id_borrador':borrador['id_pedido'] if borrador else None,'mesa':mesa,
            'puede_editar':all(p['id_usuario']==sesion['id_usuario'] for p in pedidos),
            'version':borrador['version'] if borrador else 0,
            'estado':'BORRADOR' if pendientes or not enviados else 'ENVIADO',
            'enviado_en':fecha.isoformat() if fecha else None,
            'lineas':list(enviados.values())+pendientes,'total':float(total)}


@salon_orders_bp.get('/carta')
@jwt_required()
def carta():
    validar_sesion_salon()
    return jsonify(productos=catalogo())


@salon_orders_bp.get('/mis-mesas')
@jwt_required()
def mis_mesas():
    sesion=contexto()
    mesas=db.session.execute(text('''SELECT mesa,CASE WHEN bool_or(estado='BORRADOR') THEN 'BORRADOR' ELSE 'ENVIADO' END AS estado FROM salon_pedido_actual
      WHERE id_local=:local AND id_usuario=:usuario AND EXISTS(
        SELECT 1 FROM salon_pedido_linea l WHERE l.id_pedido=salon_pedido_actual.id_pedido)
      GROUP BY mesa ORDER BY mesa'''),{'local':sesion['id_local'],'usuario':sesion['id_usuario']}).mappings()
    return jsonify(mesas=[dict(m) for m in mesas])


@salon_orders_bp.get('/mesas/<mesa>/pedido')
@jwt_required()
def consultar(mesa):
    return jsonify(obtener(mesa,contexto(mesa)))


def validar_lineas(datos,productos):
    lineas=datos.get('lineas')
    if not isinstance(lineas,list) or len(lineas)>100:
        raise BadRequest('El pedido admite hasta 100 líneas')
    indice={p['id']:p for p in productos}
    resultado=[]
    for linea in lineas:
        if not isinstance(linea,dict) or type(linea.get('id_presentacion')) is not int:
            raise BadRequest('Producto inválido')
        p=indice.get(linea['id_presentacion'])
        if not p: raise Conflict('Un producto ya no está disponible en la carta. Actualiza el pedido.')
        cantidad=linea.get('cantidad')
        comentario=linea.get('comentario','')
        opciones=linea.get('opciones',[])
        if type(cantidad) is not int or not 1<=cantidad<=99:
            raise BadRequest('La cantidad debe estar entre 1 y 99')
        if not isinstance(comentario,str) or len(comentario)>500:
            raise BadRequest('El comentario admite hasta 500 caracteres')
        if not isinstance(opciones,list) or any(type(i) is not int for i in opciones):
            raise BadRequest('Opciones inválidas')
        grupo=p['grupo']
        if not grupo and opciones: raise BadRequest('Este producto no admite opciones')
        elegidas=[]
        if grupo:
            if len(opciones)>grupo['maximo'] or (not grupo['repetir'] and len(set(opciones))!=len(opciones)):
                raise BadRequest('Revisa el máximo de opciones y si se permite repetir')
            permitidas={o['id']:o for o in grupo['opciones']}
            for identidad in opciones:
                if identidad not in permitidas: raise BadRequest('Una opción no está disponible para este producto')
                elegidas.append(permitidas[identidad])
        # Precio y nombres siempre proceden del catálogo, nunca del navegador.
        resultado.append({'id_presentacion':p['id'],'nombre':p['nombre'],'precio':p['precio'],
            'cantidad':cantidad,'comentario':comentario.strip(),'opciones':elegidas})
    return resultado


@salon_orders_bp.put('/mesas/<mesa>/pedido')
@jwt_required()
def guardar(mesa):
    sesion=contexto(mesa)
    datos=request.get_json(silent=True)
    if not isinstance(datos,dict) or type(datos.get('version')) is not int or type(datos.get('enviar',False)) is not bool:
        raise BadRequest('Datos de pedido inválidos')
    try:
        # Serializa también el primer pedido, cuando aún no existe la fila de la mesa.
        db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:clave))"),{'clave':f"salon:{sesion['id_local']}:{mesa}"})
        anterior=obtener(mesa,sesion,escritura=True)
        enviar=datos.get('enviar',False)
        envio_clave=None
        envio_hash=None
        if enviar:
            try: envio_clave=str(uuid.UUID(str(datos.get('envio_clave'))))
            except (ValueError,TypeError,AttributeError): raise BadRequest('Falta el identificador del envío')
            envio_hash=hashlib.sha256(json.dumps(datos.get('lineas'),sort_keys=True).encode()).hexdigest()
            registro_previo=db.session.execute(text('''SELECT p.envio_hash,coalesce(a.mesa,p.mesa) AS mesa,
                EXISTS(SELECT 1 FROM salon_pedido_actual actual WHERE actual.id_pedido=p.id_pedido) AS vigente
                FROM salon_pedido p LEFT JOIN salon_pedido_asignacion a USING(id_pedido)
                WHERE p.id_local=:local AND p.envio_clave=CAST(:clave AS uuid)'''),
                {'local':sesion['id_local'],'clave':envio_clave}).mappings().first()
            if registro_previo and (registro_previo['mesa']!=mesa or not registro_previo['vigente']):
                raise Conflict('Este envio ya fue registrado y trasladado. Vuelve al mapa.')
            previo=registro_previo['envio_hash'] if registro_previo else None
            if previo:
                if previo!=envio_hash: raise Conflict('El envío ya fue registrado con otros datos. Recarga la mesa.')
                return jsonify(anterior)
        if anterior['version']!=datos['version']: raise Conflict('El pedido cambió en otra ventana. Vuelve a abrir la mesa.')
        # Protege precios, disponibilidad y opciones durante la captura del pedido.
        db.session.execute(text('LOCK TABLE presentacion_venta,item_carta,categoria_carta,grupo_salsa,grupo_salsa_opcion,producto IN SHARE MODE'))
        lineas=validar_lineas(datos,catalogo())
        enviar=datos.get('enviar',False)
        if enviar and not lineas: raise BadRequest('Agrega al menos un producto antes de enviar')
        if not lineas and anterior['id_borrador'] is not None:
            db.session.execute(text('DELETE FROM salon_pedido_linea WHERE id_pedido=:id'),{'id':anterior['id_borrador']})
            db.session.execute(text('DELETE FROM salon_pedido WHERE id_pedido=:id'),{'id':anterior['id_borrador']})
            db.session.commit()
            return jsonify(obtener(mesa,sesion))
        if anterior['id_borrador'] is None:
            if not lineas: return jsonify(anterior)
            identidad=db.session.execute(text('''INSERT INTO salon_pedido(id_local,mesa,id_usuario)
              VALUES(:local,:mesa,:usuario) RETURNING id_pedido'''),
              {'local':sesion['id_local'],'mesa':mesa,'usuario':sesion['id_usuario']}).scalar_one()
        else:
            identidad=anterior['id_borrador']
            db.session.execute(text('DELETE FROM salon_pedido_linea WHERE id_pedido=:id'),{'id':identidad})
        for posicion,l in enumerate(lineas):
            db.session.execute(text('''INSERT INTO salon_pedido_linea(id_pedido,posicion,id_presentacion,nombre,precio,cantidad,comentario,opciones)
              VALUES(:pedido,:posicion,:id_presentacion,:nombre,:precio,:cantidad,:comentario,CAST(:opciones AS jsonb))'''),
              {**l,'pedido':identidad,'posicion':posicion,'opciones':json.dumps(l['opciones'],ensure_ascii=False)})
        db.session.execute(text('''UPDATE salon_pedido SET version=:version,estado=:estado,
            enviado_en=CASE WHEN :enviar THEN clock_timestamp() ELSE NULL END,
            envio_clave=CAST(:envio_clave AS uuid),envio_hash=:envio_hash WHERE id_pedido=:id'''),
            {'id':identidad,'version':anterior['version']+1,'estado':'ENVIADO' if enviar else 'BORRADOR','enviar':enviar,'envio_clave':envio_clave,'envio_hash':envio_hash})
        if enviar:
            registrar_actividad(sesion['id_usuario'],'SALON','ENVIAR_PEDIDO',identidad,
                f"Envió pedido de {mesa}: {sum(l['cantidad'] for l in lineas)} productos",
                id_perfil_utilizado=sesion.get('perfil',4),id_local=sesion['id_local'])
        db.session.commit()
        return jsonify(obtener(mesa,sesion))
    except Exception:
        db.session.rollback()
        raise


@salon_orders_bp.delete('/mesas/<mesa>/pedido')
@jwt_required()
def cancelar(mesa):
    sesion=contexto(mesa)
    datos=request.get_json(silent=True) or {}
    try:
        db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:clave))"),{'clave':f"salon:{sesion['id_local']}:{mesa}"})
        anterior=obtener(mesa,sesion,escritura=True)
        if datos.get('version')!=anterior['version']: raise Conflict('La mesa cambió en otra ventana. Recarga el pedido.')
        if anterior['id_borrador'] is not None:
            db.session.execute(text('DELETE FROM salon_pedido_linea WHERE id_pedido=:id'),{'id':anterior['id_borrador']})
            db.session.execute(text('DELETE FROM salon_pedido WHERE id_pedido=:id'),{'id':anterior['id_borrador']})
        db.session.commit()
        return jsonify(obtener(mesa,sesion))
    except Exception:
        db.session.rollback()
        raise
