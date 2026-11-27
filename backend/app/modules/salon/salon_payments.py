"""Cobro interno, cierre de mesa y consumo del local en una sola transacción."""
import hashlib
import json
import re
import uuid
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import bindparam, func, select
from werkzeug.exceptions import BadRequest, Conflict, Forbidden, NotFound

from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.extensions import db
from app.modules.salon.salon_orders import contexto, obtener, nombre_presentacion
from app.modules.auditoria.service import registrar_actividad

salon_payments_bp = Blueprint('salon_payments', __name__)


def preparado():
    if not db.session.execute(select(func.public.salon_cobros_instalados())).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260926_pagos_salon.sql')


def huella(datos):
    return hashlib.sha256(json.dumps(datos, sort_keys=True, default=str).encode()).hexdigest()


def cuenta(mesa, sesion):
    pedido = obtener(mesa, sesion)  # Propietario o responsable del mismo local.
    filas = db.session.execute(select(func.public.salon_lineas_cobro(bindparam('local'), bindparam('mesa')).table_valued(
        'id_linea', 'id_pedido', 'posicion', 'id_presentacion', 'nombre', 'precio', 'cantidad',
        'comentario', 'opciones', 'id_promocion', 'selecciones_promocion', 'id_barra_libre',
        'id_usuario',
    )), {'local': sesion['id_local'], 'mesa': mesa}).mappings().all()
    pedidos = db.session.execute(select(func.public.salon_pedidos_cobro(bindparam('local'), bindparam('mesa')).table_valued(
        'id_pedido', 'version', 'estado', 'id_usuario',
    )),
        {'local': sesion['id_local'], 'mesa': mesa}).mappings().all()
    revision = huella({'pedidos': [dict(p) for p in pedidos], 'lineas': [dict(l) for l in filas]})
    return pedido, filas, pedidos, revision


@salon_payments_bp.get('/mesas/<mesa>/cuenta')
@jwt_required()
def consultar_cuenta(mesa):
    sesion = contexto(mesa)
    preparado()
    pedido, _, _, revision = cuenta(mesa, sesion)
    return jsonify(**pedido, revision=revision, local=sesion['local'], usuario=sesion['usuario'])


def validar(datos):
    if not isinstance(datos, dict):
        raise BadRequest('Datos de pago inválidos')
    try:
        clave = str(uuid.UUID(str(datos.get('clave'))))
    except (ValueError, TypeError, AttributeError):
        raise BadRequest('Falta el identificador del cobro')
    tipo, metodo = datos.get('tipo'), datos.get('metodo')
    if tipo not in ('BOLETA', 'BOLETA_ELECTRONICA', 'FACTURA'):
        raise BadRequest('Selecciona el tipo de comprobante')
    if metodo not in ('EFECTIVO', 'TARJETA'):
        raise BadRequest('Selecciona efectivo o tarjeta')
    documento, cliente = datos.get('documento', ''), datos.get('cliente', '')
    if not isinstance(documento, str) or not isinstance(cliente, str):
        raise BadRequest('Datos del cliente inválidos')
    documento, cliente = documento.strip(), cliente.strip()
    if tipo == 'BOLETA':
        documento = cliente = ''
    else:
        longitud = 11 if tipo == 'FACTURA' else 8
        if not re.fullmatch(r'[0-9]{%d}' % longitud, documento) or not 1 <= len(cliente) <= 200:
            raise BadRequest('Ingresa RUC de 11 dígitos y razón social' if tipo == 'FACTURA'
                             else 'Ingresa DNI de 8 dígitos y nombres y apellidos')
    revision = datos.get('revision')
    if not isinstance(revision, str) or not re.fullmatch('[a-f0-9]{64}', revision):
        raise BadRequest('Abre nuevamente la cuenta antes de pagar')
    return {'clave': clave, 'tipo': tipo, 'metodo': metodo, 'documento': documento,
            'cliente': cliente, 'revision': revision}


def consumos(lineas):
    """Las promociones cobran una vez, pero consumen cada presentación elegida y repuesta."""
    totales = defaultdict(Decimal)

    def producto(identidad, cantidad, unidad):
        registro = db.session.execute(select(func.public.salon_producto_consumo(bindparam('id')).table_valued(
            'nombre', 'unidad',
        )),
                                      {'id': identidad}).mappings().first()
        if not registro or registro['unidad'] != unidad or cantidad <= 0:
            raise Conflict('Revisa las unidades y cantidades de los ingredientes antes de cobrar')
        totales[identidad] += cantidad

    def consumir_presentacion(identidad_presentacion, cantidad_unidades, opciones):
        receta = db.session.execute(select(func.public.salon_receta_activa(bindparam('id'))), {'id': identidad_presentacion}).scalar()
        detalles = [] if receta is None else db.session.execute(select(func.public.salon_detalles_receta(bindparam('id')).table_valued(
            'id_receta_detalle', 'id_receta', 'tipo_componente', 'id_producto', 'id_subproducto',
            'cantidad', 'unidad',
        )), {'id': receta}).mappings().all()
        fila = db.session.execute(select(func.public.salon_nombre_presentacion(bindparam('id'))),
            {'id': identidad_presentacion}).mappings().first()
        if not detalles or not fila:
            raise Conflict('Falta configurar la receta de la presentación. No se registró el cobro.')
        for detalle in detalles:
            cantidad = detalle['cantidad'] * cantidad_unidades
            if detalle['tipo_componente'] == 'PRODUCTO':
                producto(detalle['id_producto'], cantidad, detalle['unidad'])
            else:
                sub = db.session.execute(select(func.public.salon_subproducto(bindparam('id')).table_valued(
                    'id_subproducto', 'codigo', 'nombre', 'rendimiento', 'unidad', 'instruccion',
                    'activo',
                )),
                                         {'id': detalle['id_subproducto']}).mappings().one()
                ingredientes = db.session.execute(select(func.public.salon_ingredientes_subproducto(bindparam('id')).table_valued(
                    'id_subproducto_detalle', 'id_subproducto', 'id_producto', 'cantidad', 'unidad',
                )),
                                                  {'id': detalle['id_subproducto']}).mappings().all()
                if not ingredientes or sub['rendimiento'] <= 0 or sub['unidad'] != detalle['unidad']:
                    raise Conflict(f"Revisa el rendimiento y los ingredientes de {sub['nombre']}")
                for ingrediente in ingredientes:
                    producto(ingrediente['id_producto'], cantidad * ingrediente['cantidad'] / sub['rendimiento'], ingrediente['unidad'])
        for opcion in opciones:
            # Los pedidos nuevos guardan la identidad; los anteriores conservan el ID de opción.
            identidad = opcion.get('id_producto')
            if identidad is None:
                identidad = db.session.execute(select(func.public.salon_producto_salsa(bindparam('id'), bindparam('presentacion'))),
                    {'id': opcion['id'], 'presentacion': identidad_presentacion}).scalar()
            if identidad is None:
                raise Conflict('No se puede identificar una opción enviada. Revisa la receta antes de cobrar.')
            producto(identidad, Decimal(str(opcion['cantidad'])) * cantidad_unidades, opcion['unidad'])

    for linea in lineas:
        if linea['id_promocion'] is not None:
            for seleccion in linea['selecciones_promocion']:
                consumir_presentacion(seleccion['id_presentacion'], linea['cantidad'], seleccion['opciones'])
        else:
            consumir_presentacion(linea['id_presentacion'], linea['cantidad'], linea['opciones'])
    redondeados = {identidad: valor.quantize(Decimal('.001'), rounding=ROUND_HALF_UP)
                  for identidad, valor in totales.items()}
    if any(v <= 0 or v >= Decimal('1000000000') for v in redondeados.values()):
        raise Conflict('El consumo calculado excede la precisión admitida por el inventario')
    return redondeados


def respuesta(fila):
    return {**fila['comprobante'], 'id': fila['id_cobro'], 'numero': f"INT-{fila['id_cobro']:08d}",
            'fecha': fila['creado_en'].isoformat()}


def filtros_diario(args, hoy=None):
    from datetime import date, datetime, time, timedelta, timezone
    zona=timezone(timedelta(hours=-5))
    hoy=hoy or datetime.now(zona).date()
    try:
        desde=date.fromisoformat(args.get('desde') or hoy.isoformat())
        hasta=date.fromisoformat(args.get('hasta') or hoy.isoformat())
        pagina=int(args.get('pagina','1'))
    except (ValueError,TypeError):
        raise BadRequest('Revisa las fechas y la pagina del diario.')
    if desde>hasta or hasta==date.max or pagina<1 or pagina>100000:
        raise BadRequest('El rango de fechas o la pagina no es valido.')
    tipo=args.get('tipo','')
    metodo=args.get('metodo','')
    codigo=args.get('codigo','').strip()
    if tipo not in ('','BOLETA','BOLETA_ELECTRONICA','FACTURA') or metodo not in ('','EFECTIVO','TARJETA') or len(codigo)>30:
        raise BadRequest('Filtros de venta no validos.')
    return {'inicio':datetime.combine(desde,time.min,zona),
            'fin':datetime.combine(hasta+timedelta(days=1),time.min,zona),
            'tipo':tipo,'metodo':metodo,'codigo':codigo,'pagina':pagina}


@salon_payments_bp.get('/ventas')
@jwt_required()
def diario_ventas():
    from .salon_daily_closures import listar_cierres_diarios

    sesion=contexto()
    if not perfil_tiene_capacidad(sesion['perfil'], 'supervisar_salon'):
        raise Forbidden('Solo gerentes y supervisores pueden consultar el diario de ventas.')
    preparado()
    filtros=filtros_diario(request.args)
    params={**filtros,'local':sesion['id_local'],'offset':(filtros['pagina']-1)*20}
    # One statement gives the list and totals the same database snapshot.
    row=db.session.execute(select(func.public.salon_diario(
        bindparam('local'), bindparam('inicio'), bindparam('fin'), bindparam('tipo'), bindparam('metodo'), bindparam('codigo'), bindparam('offset'),
    ).table_valued(
        'cantidad', 'total', 'efectivo', 'tarjeta', 'ventas',
    )),params).mappings().one()
    ventas=[]
    for venta in row['ventas']:
        ventas.append({**venta,'numero':f"INT-{venta['id_cobro']:08d}"})
    cierres = listar_cierres_diarios(sesion['id_local'], filtros['inicio'].date(), filtros['fin'].date())
    return jsonify(local=sesion['local'],ventas=ventas,cierres_diarios=cierres,pagina=filtros['pagina'],por_pagina=20,
        cantidad=row['cantidad'],total=float(row['total']),efectivo=float(row['efectivo']),tarjeta=float(row['tarjeta']))


@salon_payments_bp.get('/comprobantes/<int:identidad>')
@jwt_required()
def comprobante(identidad):
    sesion = contexto()
    preparado()
    fila = db.session.execute(select(func.public.salon_comprobante(bindparam('id'), bindparam('local')).table_valued(
        'id_cobro', 'id_local', 'id_usuario', 'mesa', 'clave', 'solicitud_hash', 'tipo', 'metodo',
        'documento', 'cliente', 'total', 'comprobante', 'id_movimiento', 'creado_en', 'id_cliente',
    )),
                              {'id': identidad, 'local': sesion['id_local']}).mappings().first()
    if not fila:
        raise NotFound('Comprobante no encontrado en este local')
    if fila['id_usuario'] != sesion['id_usuario'] and not perfil_tiene_capacidad(sesion['perfil'], 'supervisar_salon'):
        raise Forbidden('No tienes acceso a este comprobante')
    resultado=respuesta(fila)
    estado = None
    if db.session.execute(select(func.public.salon_jornadas_instaladas())).scalar():
        estado=db.session.execute(select(func.public.salon_comprobante_editable(bindparam('id')).table_valued(
            'editable',
        )),{'id':identidad}).mappings().first()
    resultado['editable']=bool(estado and estado['editable'] and perfil_tiene_capacidad(sesion['perfil'], 'supervisar_salon') and not resultado.get('anulacion'))
    return jsonify(resultado)


@salon_payments_bp.post('/mesas/<mesa>/emitir')
@jwt_required()
def emitir(mesa):
    sesion = contexto(mesa)
    preparado()
    datos = validar(request.get_json(silent=True))
    cliente_id=(request.get_json(silent=True) or {}).get('id_cliente')
    if cliente_id:
        from app.modules.clientes.service import obtener as obtener_cliente
        try: cliente_id=str(uuid.UUID(str(cliente_id)))
        except ValueError: raise BadRequest('Cliente invalido')
        registro=obtener_cliente(sesion['id_local'],cliente_id)
        if not registro or registro['numero_documento']!=datos['documento'] or registro['nombre']!=datos['cliente']:
            raise Conflict('Los datos cambiaron. Selecciona nuevamente el cliente del local.')
        datos['id_cliente']=cliente_id
    solicitud_hash = huella({**datos, 'mesa': mesa})
    try:
        # Reintentos y operaciones sobre la mesa se serializan antes de consultar el estado.
        for clave in (f"salon-cobro:{sesion['id_local']}:{datos['clave']}", f"salon:{sesion['id_local']}:{mesa}"):
            db.session.execute(select(func.public.salon_bloqueo(bindparam('clave'))), {'clave': clave})
        previo = db.session.execute(select(func.public.salon_cobro_previo(bindparam('local'), bindparam('clave')).table_valued(
            'id_cobro', 'id_local', 'id_usuario', 'mesa', 'clave', 'solicitud_hash', 'tipo', 'metodo',
            'documento', 'cliente', 'total', 'comprobante', 'id_movimiento', 'creado_en', 'id_cliente',
        )),
                                    {'local': sesion['id_local'], 'clave': datos['clave']}).mappings().first()
        if previo:
            if previo['id_usuario'] != sesion['id_usuario'] or previo['solicitud_hash'] != solicitud_hash:
                raise Conflict('El identificador de cobro ya se utilizó con otros datos')
            return jsonify(respuesta(previo))
        pedido, lineas, pedidos, revision = cuenta(mesa, sesion)
        if datos['revision'] != revision:
            raise Conflict('La cuenta cambió o ya fue pagada. Regresa a la mesa y revisa los productos.')
        if not lineas or any(p['estado'] != 'ENVIADO' for p in pedidos):
            raise Conflict('Envía o cancela los productos pendientes antes de pagar una cuenta con productos enviados')
        # Evita que una edición de receta deje un consumo calculado a medias.
        db.session.execute(select(func.public.salon_bloquear_recetas()))
        consumo = consumos(lineas)
        total = sum(l['precio'] * l['cantidad'] for l in lineas)
        snapshot = {'tipo': datos['tipo'], 'metodo': datos['metodo'], 'documento': datos['documento'],
                    'cliente': datos['cliente'], 'local': sesion['local'], 'mesa': mesa,
                    'usuario': sesion['usuario'], 'total': float(total), 'fiscal': False,
                    'lineas': pedido['lineas']}
        # Comparte el mismo bloqueo de numeración que los movimientos manuales.
        db.session.execute(select(func.public.salon_bloquear_codigo()))
        numero = db.session.execute(select(func.public.salon_siguiente_movimiento())).scalar_one()
        movimiento = db.session.execute(select(func.public.salon_crear_movimiento(
            bindparam('codigo'), bindparam('usuario'), bindparam('local'), bindparam('observacion'),
        )),
            {'codigo': f'MI-{numero:03d}', 'usuario': sesion['id_usuario'], 'local': sesion['id_local'],
             'observacion': f'Cobro de Salón, mesa {mesa}'}).scalar_one()
        for identidad, cantidad in sorted(consumo.items()):
            db.session.execute(select(func.public.salon_detalle_movimiento(bindparam('movimiento'), bindparam('producto'), bindparam('cantidad'))),
                {'movimiento': movimiento, 'producto': identidad, 'cantidad': cantidad})
        cobro = db.session.execute(select(func.public.salon_crear_cobro(
            bindparam('local'), bindparam('usuario'), bindparam('mesa'), bindparam('clave'), bindparam('hash'), bindparam('tipo'), bindparam('metodo'), bindparam('documento'), bindparam('cliente'), bindparam('total'), bindparam('snapshot'), bindparam('movimiento'),
        ).table_valued(
            'id_cobro', 'id_local', 'id_usuario', 'mesa', 'clave', 'solicitud_hash', 'tipo', 'metodo',
            'documento', 'cliente', 'total', 'comprobante', 'id_movimiento', 'creado_en', 'id_cliente',
        )), {**datos, 'local': sesion['id_local'], 'usuario': sesion['id_usuario'], 'mesa': mesa,
                'hash': solicitud_hash, 'total': total, 'snapshot': json.dumps(snapshot, ensure_ascii=False),
                'movimiento': movimiento}).mappings().one()
        if cliente_id:
            db.session.execute(select(func.public.salon_cliente_cobro(bindparam('cliente'), bindparam('id'))), {'cliente':cliente_id,'id':cobro['id_cobro']})
        for p in pedidos:
            db.session.execute(select(func.public.salon_vincular_pedido(bindparam('cobro'), bindparam('pedido'))),
                               {'cobro': cobro['id_cobro'], 'pedido': p['id_pedido']})
        registrar_actividad(sesion['id_usuario'], 'SALON', 'COBRAR_MESA', cobro['id_cobro'],
            f"Cobró {mesa}: S/ {total:.2f}, {datos['metodo']}, comprobante interno INT-{cobro['id_cobro']:08d}",
            id_perfil_utilizado=sesion['perfil'], id_local=sesion['id_local'])
        resultado = respuesta(cobro)
        from app.modules.facturacion.service import enqueue_source
        enqueue_source('VENTA', cobro['id_cobro'], sesion['id_local'])
        db.session.commit()
        return jsonify(resultado), 201
    except Exception:
        db.session.rollback()
        raise

@salon_payments_bp.post('/comprobantes/<int:identidad>/<accion>')
@jwt_required()
def modificar_venta(identidad, accion):
    from app.modules.salon.salon_sale_changes import verificar_dia
    from app.modules.inventarios.operativo import bloqueo
    if accion not in ('anular', 'cambiar-tipo'):
        raise NotFound('Acción no encontrada')
    sesion = contexto()
    if not perfil_tiene_capacidad(sesion['perfil'], 'supervisar_salon'):
        raise Forbidden('Solo gerente y supervisor pueden modificar ventas.')
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict): raise BadRequest('Datos inválidos.')
    motivo = datos.get('motivo', '')
    referencia = datos.get('referencia', '')
    if not isinstance(motivo,str) or not 5 <= len(motivo.strip()) <= 1000:
        raise BadRequest('Escribe un motivo de 5 a 1000 caracteres.')
    if not isinstance(referencia,str) or len(referencia)>40:
        raise BadRequest('Número de reemplazo inválido.')
    try:
        bloqueo(sesion['id_local'])
        fila = db.session.execute(select(func.public.salon_cambio_bloqueado(bindparam('id'), bindparam('local')).table_valued(
            'id_cobro', 'id_local', 'id_usuario', 'mesa', 'clave', 'solicitud_hash', 'tipo', 'metodo',
            'documento', 'cliente', 'total', 'comprobante', 'id_movimiento', 'creado_en', 'id_jornada',
            'id_cliente', 'jornada_fecha', 'cerrado_en', 'hoy', 'fecha_venta',
        )),
            {'id':identidad,'local':sesion['id_local']}).mappings().first()
        if not fila: raise NotFound('Venta no encontrada en este local.')
        verificar_dia(fila['fecha_venta'],fila['jornada_fecha'],fila['cerrado_en'],fila['hoy'])
        recibo = dict(fila['comprobante'])
        if recibo.get('anulacion'): raise Conflict('La venta ya está anulada.')
        historial = list(recibo.get('historial', []))
        if datos.get('version') != len(historial): raise Conflict('La venta cambió. Recarga el detalle.')
        evento = dict(accion=accion,motivo=motivo.strip(),referencia=referencia.strip(),
                      usuario=sesion['id_usuario'],fecha=db.session.execute(select(func.public.salon_reloj())).scalar().isoformat())
        if accion == 'anular':
            if referencia.strip() == f'INT-{identidad:08d}': raise BadRequest('El reemplazo debe ser otro comprobante.')
            recibo['anulacion'] = evento
        else:
            tipo=datos.get('tipo')
            documento=datos.get('documento','')
            cliente=datos.get('cliente','')
            if tipo not in ('BOLETA_ELECTRONICA','FACTURA') or tipo == fila['tipo']:
                raise BadRequest('Selecciona otro tipo de comprobante.')
            longitud=8 if tipo=='BOLETA_ELECTRONICA' else 11
            if not isinstance(documento,str) or not re.fullmatch(r'\d{%d}' % longitud,documento):
                raise BadRequest('Revisa el DNI o RUC.')
            if not isinstance(cliente,str) or not 1<=len(cliente.strip())<=200: raise BadRequest('Indica el nombre o razón social.')
            evento['anterior']={k:recibo.get(k) for k in ('tipo','documento','cliente')}
            recibo.update(tipo=tipo,documento=documento,cliente=cliente.strip())
            evento['nuevo']={k:recibo[k] for k in ('tipo','documento','cliente')}
            db.session.execute(select(func.public.salon_actualizar_cliente(
                bindparam('tipo'), bindparam('doc'), bindparam('cliente'), bindparam('id'),
            )),
                {'id':identidad,'tipo':tipo,'doc':documento,'cliente':cliente.strip()})
        historial.append(evento); recibo['historial']=historial
        db.session.execute(select(func.public.salon_guardar_comprobante(bindparam('c'), bindparam('id'))), {'id':identidad,'c':json.dumps(recibo)})
        from app.modules.facturacion.service import enqueue_source, invalidate_sale
        if accion=='anular':
            invalidate_sale(identidad,sesion['id_local'])
        else:
            enqueue_source('VENTA',identidad,sesion['id_local'])
        registrar_actividad(sesion['id_usuario'],'SALON',accion.upper(),identidad,motivo.strip(),id_local=sesion['id_local'])
        db.session.commit()
        return jsonify(ok=True)
    except Exception:
        db.session.rollback(); raise
