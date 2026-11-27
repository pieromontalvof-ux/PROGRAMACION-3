"""Salidas y recepciones enlazadas; cada recepción genera una sola entrada de stock."""
from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy import bindparam, func, select
from werkzeug.exceptions import BadRequest, Conflict, NotFound

from app.core.extensions import db
from app.core.local_scope import local_actual, exigir_migracion_locales
from app.modules.auditoria.service import registrar_actividad
from app.modules.movimientos.repository import (
    generar_codigo_movimiento, crear_cabecera_movimiento, crear_detalle_movimiento,
)


def ready():
    exigir_migracion_locales()
    if not db.session.execute(select(func.public.mov_seguimiento_instalado())).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260922_seguimiento_movimientos.sql')


def destino_local(valor):
    if type(valor) is not int or valor == local_actual():
        raise BadRequest('Selecciona otro local como destino')
    destino = db.session.execute(select(func.public.mov_destino_bloqueado(bindparam("id")).table_valued("id_local", "nombre")), {'id': valor}).mappings().first()
    if not destino:
        raise BadRequest('El local destino no está disponible')
    return destino


def validar_salida(datos, fecha, requiere_local):
    ready()
    if fecha != date.today():
        raise BadRequest('Los movimientos con seguimiento se registran con fecha de hoy')
    return destino_local(datos.get('id_local_destino')) if requiere_local else None


def registrar_salida(id_movimiento, destino):
    db.session.execute(select(func.public.mov_registrar_salida(bindparam("id"), bindparam("destino"), bindparam("estado"))), {
        'id': id_movimiento, 'destino': destino['id_local'] if destino else None,
        'estado': 'PENDIENTE_RECEPCION' if destino else 'DEVUELTO',
    })


def listar():
    ready()
    local = local_actual()
    filas = db.session.execute(select(func.public.mov_listar_seguimiento(bindparam("local")).table_valued("id", "codigo", "fecha", "id_local", "id_local_destino", "estado", "motivo", "origen", "destino", "proveedor", "observacion", "registrado_por")), {'local': local}).mappings().all()
    resultado = []
    for f in filas:
        item = dict(f)
        item['fecha'] = f['fecha'].isoformat()
        item['detalles'] = [dict(d) for d in db.session.execute(select(func.public.mov_detalles_seguimiento(bindparam("id")).table_valued("id_producto", "codigo", "nombre", "unidad", "cantidad", "recibido")), {'id': f['id']}).mappings()]
        for d in item['detalles']:
            d['cantidad'],d['recibido'] = float(d['cantidad']),float(d['recibido'])
        item['recepciones'] = [dict(r) for r in db.session.execute(select(func.public.mov_recepciones(bindparam("id")).table_valued("codigo", "guia_proveedor", "fecha", "nombre", "unidad", "cantidad")), {'id': f['id']}).mappings()]
        resultado.append(item)
    return {'movimientos': resultado}


def recibir(id_salida, datos, usuario):
    ready()
    local = local_actual()
    if not isinstance(datos, dict):
        raise BadRequest('Envía los datos de recepción')
    try:
        salida = db.session.execute(select(func.public.mov_salida_bloqueada(bindparam("id"), bindparam("local")).table_valued("id_local", "id_proveedor", "codigo", "id_local_destino", "estado", "motivo_recepcion")), {'id': id_salida,'local': local}).mappings().first()
        if not salida:
            raise NotFound('La guía no existe en este local')
        prestamo = salida['id_local_destino'] is not None
        if local != (salida['id_local_destino'] if prestamo else salida['id_local']):
            raise NotFound('Solo el local destinatario puede aceptar el préstamo')
        if salida['estado'] in ('ACEPTADO','REINTEGRADO'):
            raise Conflict('Esta guía ya fue recibida completamente')
        guia = str(datos.get('guia_proveedor') or '').strip()
        if not prestamo and (not guia or len(guia)>100):
            raise BadRequest('Registra la guía del proveedor (máximo 100 caracteres)')
        if guia and db.session.execute(select(func.public.mov_guia_registrada(bindparam("id"), bindparam("guia"))), {'id':id_salida,'guia':guia}).scalar():
            raise Conflict('Esta guía del proveedor ya fue registrada para esta devolución')
        cantidades = dict(db.session.execute(select(func.public.mov_cantidades(bindparam("id")).table_valued("id_producto", "cantidad")), {'id':id_salida}).all())
        recibidos = dict(db.session.execute(select(func.public.mov_cantidades_recibidas(bindparam("id")).table_valued("id_producto", "cantidad")), {'id':id_salida}).all())
        entrada = cantidades.copy() if prestamo else {}
        if not prestamo:
            detalles = datos.get('detalles')
            if not isinstance(detalles,list) or not detalles:
                raise BadRequest('Agrega las cantidades recibidas')
            for d in detalles:
                if not isinstance(d,dict) or type(d.get('id_producto')) is not int:
                    raise BadRequest('Producto inválido')
                p = d['id_producto']
                try:
                    c = Decimal(str(d.get('cantidad')))
                except InvalidOperation:
                    raise BadRequest('Cantidad inválida')
                if p not in cantidades or p in entrada or not c.is_finite() or c<=0 or c.as_tuple().exponent < -3 or c>cantidades[p]-recibidos.get(p,0):
                    raise BadRequest('La cantidad debe ser positiva, tener hasta 3 decimales y no superar lo pendiente')
                entrada[p] = c
        if not salida['motivo_recepcion']:
            raise Conflict('La guía no tiene un motivo de recepción configurado')
        codigo = generar_codigo_movimiento()
        mid = crear_cabecera_movimiento(codigo,'ENTRADA',salida['motivo_recepcion'],
            date.today(),usuario,str(salida['id_local']) if prestamo else None,salida['id_proveedor'],f"Recepción de {salida['codigo']}")
        for p,c in entrada.items():
            crear_detalle_movimiento(mid,p,c)
        db.session.execute(select(func.public.mov_registrar_reintegro(bindparam("id"), bindparam("salida"), bindparam("guia"))), {'id':mid,'salida':id_salida,'guia':None if prestamo else guia})
        completo = all(recibidos.get(p,0)+entrada.get(p,0)==c for p,c in cantidades.items())
        estado = 'ACEPTADO' if prestamo else ('REINTEGRADO' if completo else 'REINTEGRO_PARCIAL')
        db.session.execute(select(func.public.mov_actualizar_seguimiento(bindparam("estado"), bindparam("id"))), {'estado':estado,'id':id_salida})
        registrar_actividad(id_usuario=usuario,modulo='MOVIMIENTO_INVENTARIO',accion='CREAR',id_registro_afectado=mid,descripcion=f'Recepción {codigo} de {salida["codigo"]}: {estado}')
        db.session.commit()
        return {'mensaje':f'Recepción registrada: {codigo}', 'estado':estado},201
    except Exception:
        db.session.rollback()
        raise
