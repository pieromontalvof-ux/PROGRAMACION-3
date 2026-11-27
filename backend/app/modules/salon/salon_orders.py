"""Pedidos de Salón: edición del borrador y envío inmutable por mesa/local."""
import hashlib
import uuid
import json
import re
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import bindparam, func, select
from werkzeug.exceptions import BadRequest, Conflict, Forbidden
from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.extensions import db
from app.modules.salon.salon import validar_sesion_salon
from app.modules.salon.salon_layout import leer
from app.modules.auditoria.service import registrar_actividad

salon_orders_bp=Blueprint('salon_orders',__name__)


def nombre_presentacion(nombre):
    # También corrige nombres capturados en pedidos anteriores sin alterar sus registros.
    return re.sub(r'(\d+)\.0+(?=\s+(?:UNI|PORCIÓN|PORCION)\b)', r'\1', nombre)


def contexto(mesa=None):
    sesion=validar_sesion_salon()
    if mesa is not None:
        db.session.execute(select(func.public.salon_bloqueo_compartido(bindparam('clave'))),{'clave':f"salon-layout:{sesion['id_local']}"})
        if mesa not in {e['codigo'] for e in leer(sesion['id_local'])['elementos'] if e['tipo']!='barra'}:
            raise BadRequest('Mesa invalida')
    if not db.session.execute(select(func.public.salon_pedidos_instalados_existe())).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260923_pedidos_salon.sql')
    if not db.session.execute(select(func.public.salon_envios_instalados())).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260923_envios_adicionales_salon.sql')
    if not db.session.execute(select(func.public.salon_promociones_instaladas())).scalar():
        raise Conflict('Falta ejecutar database/migrations/20261016_promociones_reposicion_salon.sql')
    if not db.session.execute(select(func.public.salon_control_instalado())).scalar():
        raise Conflict('Ejecuta 20260923_control_salon.sql')
    return sesion


def catalogo():
    productos=[dict(p) for p in db.session.execute(select(func.public.salon_catalogo().table_valued(
        'id', 'nombre', 'contenido', 'unidad', 'precio', 'id_categoria', 'categoria',
    ))).mappings()]
    grupos=db.session.execute(select(func.public.salon_grupos_salsa().table_valued(
        'id_grupo_salsa', 'id_presentacion_venta', 'cantidad_maxima', 'permite_repetir', 'id', 'nombre',
        'cantidad', 'unidad', 'id_producto',
    ))).mappings().all()
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
    por_id={p['id']:p for p in productos}
    promociones=db.session.execute(select(func.public.salon_promociones_activas().table_valued(
        'id_promocion', 'nombre', 'precio',
    ))).mappings().all()
    resultado_promociones=[]
    for promo in promociones:
        grupos=[]
        for grupo in db.session.execute(select(func.public.salon_grupos_promocion(bindparam('id')).table_valued(
            'id_promocion_grupo', 'cantidad_elegir', 'permite_repetir',
        )),
          {'id':promo['id_promocion']}).mappings():
            opciones=[]
            for opcion in db.session.execute(select(func.public.salon_opciones_promocion(bindparam('promo'), bindparam('grupo')).table_valued(
                'id_presentacion_venta', 'reponible',
            )),
              {'promo':promo['id_promocion'],'grupo':grupo['id_promocion_grupo']}).mappings():
                producto=por_id.get(opcion['id_presentacion_venta'])
                if producto:
                    opciones.append({**producto,'reponible':opcion['reponible']})
            if not opciones or (not grupo['permite_repetir'] and grupo['cantidad_elegir']>len(opciones)):
                grupos=[]
                break
            grupos.append({'id':grupo['id_promocion_grupo'],'cantidad':grupo['cantidad_elegir'],
                           'repetir':grupo['permite_repetir'],'opciones':opciones})
        if grupos:
            resultado_promociones.append({'id':promo['id_promocion'],'nombre':promo['nombre'],
                'precio':float(promo['precio']),'grupos':grupos})
    return {'productos':productos,'promociones':resultado_promociones}


def obtener(mesa,sesion,escritura=False):
    db.session.execute(select(func.public.salon_bloqueo_compartido(bindparam('clave'))),{'clave':f"salon:{sesion['id_local']}:{mesa}"})
    pedidos=db.session.execute(select(func.public.salon_pedidos(bindparam('local'), bindparam('mesa')).table_valued(
        'id_pedido', 'id_local', 'mesa', 'id_usuario', 'estado', 'version', 'creado_en', 'enviado_en',
        'envio_clave', 'envio_hash',
    )),
        {'local':sesion['id_local'],'mesa':mesa}).mappings().all()
    if any(p['id_usuario']!=sesion['id_usuario'] for p in pedidos) and (escritura or not perfil_tiene_capacidad(sesion.get('perfil'), 'supervisar_salon')):
        raise Forbidden('Esta mesa está siendo atendida por otro usuario')
    borrador=next((p for p in pedidos if p['estado']=='BORRADOR'),None)
    filas=db.session.execute(select(func.public.salon_lineas(bindparam('local'), bindparam('mesa')).table_valued(
        'id_linea', 'id_presentacion', 'id_promocion', 'selecciones_promocion', 'id_barra_libre',
        'barra_nombre', 'nombre', 'precio', 'cantidad', 'comentario', 'opciones', 'enviada',
    )),
        {'local':sesion['id_local'],'mesa':mesa}).mappings().all()
    reposiciones_por_barra={}
    for fila in filas:
        if fila['id_barra_libre'] is not None:
            reposiciones_por_barra[fila['id_barra_libre']]=reposiciones_por_barra.get(fila['id_barra_libre'],0)+fila['cantidad']
    enviados={}
    pendientes=[]
    total=0
    for fila in filas:
        l=dict(fila)
        identidad_linea=l['id_linea']
        l['nombre']=nombre_presentacion(l['nombre'])
        l['ids_lineas']=[l.pop('id_linea')]
        if l['id_promocion'] is not None:
            l['cantidad_reposiciones']=reposiciones_por_barra.get(identidad_linea,0)
        total+=l['precio']*l['cantidad']
        l['precio']=float(l['precio'])
        if l['enviada'] and l['id_promocion'] is None and l['id_barra_libre'] is None:
            opciones=sorted(l['opciones'],key=lambda o: json.dumps(o,sort_keys=True))
            clave=(l['id_presentacion'],l['nombre'],l['precio'],l['comentario'],json.dumps(opciones,sort_keys=True))
            if clave in enviados:
                enviados[clave]['cantidad']+=l['cantidad']
                enviados[clave]['ids_lineas']+=l['ids_lineas']
            else: enviados[clave]=l
        elif l['enviada']: enviados[('linea',l['ids_lineas'][0])]=l
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
    contexto()
    return jsonify(**catalogo())


@salon_orders_bp.get('/mis-mesas')
@jwt_required()
def mis_mesas():
    sesion=contexto()
    mesas=db.session.execute(select(func.public.salon_mesas_propias(bindparam('local'), bindparam('usuario')).table_valued(
        'mesa', 'estado',
    )),{'local':sesion['id_local'],'usuario':sesion['id_usuario']}).mappings()
    return jsonify(mesas=[dict(m) for m in mesas])


@salon_orders_bp.get('/mesas/<mesa>/pedido')
@jwt_required()
def consultar(mesa):
    return jsonify(obtener(mesa,contexto(mesa)))


def validar_opciones(producto,opciones):
    if not isinstance(opciones,list) or any(type(i) is not int for i in opciones):
        raise BadRequest('Opciones inválidas')
    grupo=producto['grupo']
    if not grupo and opciones: raise BadRequest('Este producto no admite opciones')
    elegidas=[]
    if grupo:
        if len(opciones)>grupo['maximo'] or (not grupo['repetir'] and len(set(opciones))!=len(opciones)):
            raise BadRequest('Revisa el máximo de opciones y si se permite repetir')
        permitidas={o['id']:o for o in grupo['opciones']}
        for identidad in opciones:
            if identidad not in permitidas: raise BadRequest('Una opción no está disponible para este producto')
            elegidas.append(permitidas[identidad])
    return elegidas


def validar_lineas(datos,catalogo_actual,sesion,mesa):
    lineas=datos.get('lineas')
    if not isinstance(lineas,list) or len(lineas)>100:
        raise BadRequest('El pedido admite hasta 100 líneas')
    indice={p['id']:p for p in catalogo_actual['productos']}
    promociones={p['id']:p for p in catalogo_actual['promociones']}
    resultado=[]
    for linea in lineas:
        if not isinstance(linea,dict):
            raise BadRequest('Producto inválido')
        cantidad=linea.get('cantidad')
        comentario=linea.get('comentario','')
        if type(cantidad) is not int or not 1<=cantidad<=99:
            raise BadRequest('La cantidad debe estar entre 1 y 99')
        if not isinstance(comentario,str) or len(comentario)>500:
            raise BadRequest('El comentario admite hasta 500 caracteres')
        if type(linea.get('id_promocion')) is int:
            promo=promociones.get(linea['id_promocion'])
            if not promo: raise Conflict('La promoción ya no está disponible. Actualiza el pedido.')
            if cantidad!=1: raise BadRequest('Agrega cada promoción como una barra libre independiente')
            selecciones=linea.get('selecciones')
            if not isinstance(selecciones,list) or len(selecciones)>100:
                raise BadRequest('Configura las opciones incluidas en la promoción')
            normalizadas=[]
            ids_seleccionados=set()
            for grupo in promo['grupos']:
                seleccion_grupo=[s for s in selecciones if isinstance(s,dict) and s.get('id_grupo')==grupo['id']]
                if len(seleccion_grupo)!=grupo['cantidad']:
                    raise BadRequest('Completa la cantidad de opciones de cada grupo')
                ids=[s.get('id_presentacion') for s in seleccion_grupo]
                if any(type(i) is not int for i in ids) or (not grupo['repetir'] and len(ids)!=len(set(ids))):
                    raise BadRequest('Revisa si se pueden repetir las opciones elegidas')
                permitidas={o['id']:o for o in grupo['opciones']}
                for seleccion in seleccion_grupo:
                    producto=permitidas.get(seleccion['id_presentacion'])
                    if not producto: raise BadRequest('Una opción no pertenece a esta promoción')
                    ids_seleccionados.add(id(seleccion))
                    elegidas=validar_opciones(producto,seleccion.get('opciones',[]))
                    normalizadas.append({'id_grupo':grupo['id'],'id_presentacion':producto['id'],
                        'nombre':producto['nombre'],'reponible':producto['reponible'],
                        'grupo':producto['grupo'],'opciones':elegidas})
            if len(ids_seleccionados)!=len(selecciones):
                raise BadRequest('Una opción no pertenece a los grupos de esta promoción')
            resultado.append({'id_presentacion':None,'id_promocion':promo['id'],'id_barra_libre':None,
                'selecciones_promocion':normalizadas,'nombre':promo['nombre'],'precio':promo['precio'],
                'cantidad':1,'comentario':comentario.strip(),'opciones':[]})
            continue
        if type(linea.get('id_presentacion')) is not int:
            raise BadRequest('Producto inválido')
        p=indice.get(linea['id_presentacion'])
        if not p: raise Conflict('Un producto ya no está disponible en la carta. Actualiza el pedido.')
        elegidas=validar_opciones(p,linea.get('opciones',[]))
        barra=linea.get('id_barra_libre')
        if barra is not None:
            if type(barra) is not int or barra<=0:
                raise BadRequest('Selecciona una barra libre válida')
            padre=db.session.execute(select(func.public.salon_promocion_padre(bindparam('id'), bindparam('local'), bindparam('mesa')).table_valued(
                'id_promocion', 'selecciones_promocion',
            )),
              {'id':barra,'local':sesion['id_local'],'mesa':mesa}).mappings().first()
            reponible=padre and any(s.get('id_presentacion')==p['id'] and s.get('reponible')
                for s in padre['selecciones_promocion'])
            if not reponible:
                raise Conflict('Esta presentación no admite reposición en esa barra libre')
        # Precio y nombres siempre proceden del catálogo, nunca del navegador.
        resultado.append({'id_presentacion':p['id'],'id_promocion':None,'id_barra_libre':barra,
            'selecciones_promocion':[],'nombre':p['nombre'],'precio':0 if barra is not None else p['precio'],
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
        db.session.execute(select(func.public.salon_bloqueo(bindparam('clave'))),{'clave':f"salon:{sesion['id_local']}:{mesa}"})
        anterior=obtener(mesa,sesion,escritura=True)
        enviar=datos.get('enviar',False)
        envio_clave=None
        envio_hash=None
        if enviar:
            try: envio_clave=str(uuid.UUID(str(datos.get('envio_clave'))))
            except (ValueError,TypeError,AttributeError): raise BadRequest('Falta el identificador del envío')
            envio_hash=hashlib.sha256(json.dumps(datos.get('lineas'),sort_keys=True).encode()).hexdigest()
            registro_previo=db.session.execute(select(func.public.salon_envio_previo(bindparam('local'), bindparam('clave')).table_valued(
                'envio_hash', 'mesa', 'vigente',
            )),
                {'local':sesion['id_local'],'clave':envio_clave}).mappings().first()
            if registro_previo and (registro_previo['mesa']!=mesa or not registro_previo['vigente']):
                raise Conflict('Este envio ya fue registrado y trasladado. Vuelve al mapa.')
            previo=registro_previo['envio_hash'] if registro_previo else None
            if previo:
                if previo!=envio_hash: raise Conflict('El envío ya fue registrado con otros datos. Recarga la mesa.')
                return jsonify(anterior)
        if anterior['version']!=datos['version']: raise Conflict('El pedido cambió en otra ventana. Vuelve a abrir la mesa.')
        # Protege precios, disponibilidad y opciones durante la captura del pedido.
        db.session.execute(select(func.public.salon_bloquear_catalogo()))
        lineas=validar_lineas(datos,catalogo(),sesion,mesa)
        enviar=datos.get('enviar',False)
        if enviar and not lineas: raise BadRequest('Agrega al menos un producto antes de enviar')
        if not lineas and anterior['id_borrador'] is not None:
            db.session.execute(select(func.public.salon_eliminar_lineas(bindparam('id'))),{'id':anterior['id_borrador']})
            db.session.execute(select(func.public.salon_eliminar_pedido(bindparam('id'))),{'id':anterior['id_borrador']})
            db.session.commit()
            return jsonify(obtener(mesa,sesion))
        if anterior['id_borrador'] is None:
            if not lineas: return jsonify(anterior)
            identidad=db.session.execute(select(func.public.salon_crear_pedido(bindparam('local'), bindparam('mesa'), bindparam('usuario'))),
              {'local':sesion['id_local'],'mesa':mesa,'usuario':sesion['id_usuario']}).scalar_one()
        else:
            identidad=anterior['id_borrador']
            db.session.execute(select(func.public.salon_eliminar_lineas(bindparam('id'))),{'id':identidad})
        for posicion,l in enumerate(lineas):
                        db.session.execute(select(func.public.salon_crear_linea(
                            bindparam('pedido'), bindparam('posicion'), bindparam('id_presentacion'), bindparam('id_promocion'), bindparam('selecciones_promocion'), bindparam('id_barra_libre'), bindparam('nombre'), bindparam('precio'), bindparam('cantidad'), bindparam('comentario'), bindparam('opciones'),
                        )),
                            {**l,'pedido':identidad,'posicion':posicion,
                             'selecciones_promocion':json.dumps(l['selecciones_promocion'],ensure_ascii=False),
                             'opciones':json.dumps(l['opciones'],ensure_ascii=False)})
        db.session.execute(select(func.public.salon_guardar_pedido(
            bindparam('version'), bindparam('estado'), bindparam('enviar'), bindparam('envio_clave'), bindparam('envio_hash'), bindparam('id'),
        )),
            {'id':identidad,'version':anterior['version']+1,'estado':'ENVIADO' if enviar else 'BORRADOR','enviar':enviar,'envio_clave':envio_clave,'envio_hash':envio_hash})
        if enviar:
            registrar_actividad(sesion['id_usuario'],'SALON','ENVIAR_PEDIDO',identidad,
                f"Envió pedido de {mesa}: {sum(l['cantidad'] for l in lineas)} productos",
                id_perfil_utilizado=sesion.get('perfil'),id_local=sesion['id_local'])
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
        db.session.execute(select(func.public.salon_bloqueo(bindparam('clave'))),{'clave':f"salon:{sesion['id_local']}:{mesa}"})
        anterior=obtener(mesa,sesion,escritura=True)
        if datos.get('version')!=anterior['version']: raise Conflict('La mesa cambió en otra ventana. Recarga el pedido.')
        if anterior['id_borrador'] is not None:
            db.session.execute(select(func.public.salon_eliminar_lineas(bindparam('id'))),{'id':anterior['id_borrador']})
            db.session.execute(select(func.public.salon_eliminar_pedido(bindparam('id'))),{'id':anterior['id_borrador']})
        db.session.commit()
        return jsonify(obtener(mesa,sesion))
    except Exception:
        db.session.rollback()
        raise
