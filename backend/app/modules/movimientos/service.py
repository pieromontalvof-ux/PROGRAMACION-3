from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy import bindparam, func, select

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad
from app.modules.movimientos.repository import (
    buscar_movimiento_creado,
    buscar_producto_activo_movimiento,
    crear_cabecera_movimiento,
    crear_detalle_movimiento,
    generar_codigo_movimiento,
    listar_detalles_movimiento_creado,
    listar_productos_activos_movimiento,
    listar_proveedores_activos_movimiento,
    proveedor_activo_movimiento_existe,
)


def motivos_registrables():
    return [dict(fila) for fila in db.session.execute(select(func.public.catalogo_motivos_movimiento().table_valued('valor', 'etiqueta', 'tipo_movimiento', 'requiere_local', 'requiere_proveedor'))).mappings()]


def configuracion_motivo(codigo):
    return db.session.execute(select(func.public.configuracion_motivo_movimiento(codigo).table_valued('tipo_movimiento', 'requiere_local', 'requiere_proveedor', 'registrable', 'motivo_recepcion'))).mappings().first()


def obtener_formulario_movimiento():
    from app.core.local_scope import ejecutar_local
    locales = ejecutar_local(select(func.public.mov_locales_destino(bindparam("id_local_actual")).table_valued("id_local", "nombre"))).mappings().all()
    productos = listar_productos_activos_movimiento()
    proveedores = listar_proveedores_activos_movimiento()

    return {
        "locales": [dict(l) for l in locales],
        "motivos": motivos_registrables(),
        "categorias": sorted({
            producto["categoria"]
            for producto in productos
        }),
        "productos": [
            {
                "id_producto": producto["id_producto"],
                "codigo": producto["codigo"],
                "nombre": producto["nombre"],
                "unidad": producto["unidad"],
                "id_categoria": producto["id_categoria"],
                "categoria": producto["categoria"],
            }
            for producto in productos
        ],
        "proveedores": [
            {
                "id_proveedor": proveedor["id_proveedor"],
                "nombre": proveedor["nombre"],
            }
            for proveedor in proveedores
        ],
    }, 200


def _convertir_fecha_movimiento(valor):
    if not isinstance(valor, str):
        return None

    try:
        return date.fromisoformat(valor)
    except ValueError:
        return None


def _limpiar_texto_opcional(valor):
    if valor is None:
        return None

    texto = str(valor).strip()

    return texto or None


def _validar_relacion_movimiento(
    configuracion,
    local_relacionado,
    id_proveedor,
):
    if configuracion["requiere_local"]:
        if not local_relacionado:
            return "Debes indicar el local relacionado"

        if id_proveedor is not None:
            return (
                "Este movimiento no debe tener proveedor"
            )

        return None

    if configuracion["requiere_proveedor"]:
        if id_proveedor is None:
            return "Debes seleccionar un proveedor"

        if local_relacionado is not None:
            return (
                "Este movimiento no debe tener local relacionado"
            )

        if not proveedor_activo_movimiento_existe(
            id_proveedor
        ):
            return "El proveedor no existe o está inactivo"

        return None

    if local_relacionado is not None:
        return "La merma no debe tener un local relacionado"

    if id_proveedor is not None:
        return "La merma no debe tener un proveedor"

    return None


def _validar_detalles_movimiento(detalles):
    if not isinstance(detalles, list) or not detalles:
        return None, "Agrega al menos un producto"

    ids_recibidos = set()
    detalles_validados = []

    for detalle in detalles:
        if not isinstance(detalle, dict):
            return None, "Cada detalle debe ser un objeto"

        try:
            id_producto = int(detalle.get("id_producto"))
        except (TypeError, ValueError):
            return None, "Se recibió un producto inválido"

        if id_producto in ids_recibidos:
            return None, (
                f"El producto {id_producto} está repetido"
            )

        producto = buscar_producto_activo_movimiento(
            id_producto
        )

        if producto is None:
            return None, (
                f"El producto {id_producto} no existe "
                "o está inactivo"
            )

        try:
            cantidad = Decimal(
                str(detalle.get("cantidad"))
            )
        except (InvalidOperation, TypeError, ValueError):
            return None, (
                f"La cantidad de {producto['nombre']} "
                "no es válida"
            )

        if not cantidad.is_finite() or cantidad <= 0 or cantidad >= Decimal("1000000000") or cantidad.as_tuple().exponent < -3:
            return None, (
                f"La cantidad de {producto['nombre']} "
                "debe ser mayor que cero"
            )

        ids_recibidos.add(id_producto)
        detalles_validados.append({
            "id_producto": id_producto,
            "cantidad": cantidad,
        })

    return detalles_validados, None


def _serializar_movimiento(id_movimiento):
    movimiento = buscar_movimiento_creado(id_movimiento)
    detalles = listar_detalles_movimiento_creado(
        id_movimiento
    )

    return {
        "id_movimiento_inventario":
            movimiento["id_movimiento_inventario"],
        "codigo": movimiento["codigo"],
        "tipo_movimiento": movimiento["tipo_movimiento"],
        "motivo_movimiento":
            movimiento["motivo_movimiento"],
        "fecha_movimiento":
            movimiento["fecha_movimiento"].isoformat(),
        "registrado_por": movimiento["registrado_por"],
        "local_relacionado":
            movimiento["local_relacionado"],
        "id_proveedor": movimiento["id_proveedor"],
        "proveedor": movimiento["proveedor"],
        "observacion": movimiento["observacion"],
        "detalles": [
            {
                "id_producto": detalle["id_producto"],
                "codigo": detalle["codigo"],
                "nombre": detalle["nombre"],
                "unidad": detalle["unidad"],
                "cantidad": float(detalle["cantidad"]),
            }
            for detalle in detalles
        ],
    }


def registrar_movimiento(id_usuario, datos):
    if not isinstance(datos, dict):
        return {
            "mensaje": "Debes enviar un objeto JSON válido"
        }, 400

    motivo = str(
        datos.get("motivo_movimiento", "")
    ).strip().upper()
    configuracion = configuracion_motivo(motivo)

    if configuracion and not configuracion['registrable']:
        return {"mensaje": "Este motivo se registra desde su flujo de origen"}, 400

    if configuracion is None:
        return {
            "mensaje": "Selecciona un motivo válido"
        }, 400

    fecha_movimiento = _convertir_fecha_movimiento(
        datos.get("fecha_movimiento")
    )

    if fecha_movimiento is None:
        return {
            "mensaje": "Selecciona una fecha válida"
        }, 400

    local_relacionado = _limpiar_texto_opcional(
        datos.get("local_relacionado")
    )
    observacion = _limpiar_texto_opcional(
        datos.get("observacion")
    )

    id_proveedor = datos.get("id_proveedor")

    if id_proveedor in (None, ""):
        id_proveedor = None
    else:
        try:
            id_proveedor = int(id_proveedor)
        except (TypeError, ValueError):
            return {
                "mensaje": "El proveedor seleccionado no es válido"
            }, 400

    destino = None
    seguimiento = configuracion['motivo_recepcion'] is not None
    if seguimiento:
        from app.modules.movimientos.tracking import validar_salida
        destino = validar_salida(datos, fecha_movimiento, configuracion['requiere_local'])
    elif configuracion['requiere_local'] and datos.get('id_local_destino') is not None:
        from app.modules.movimientos.tracking import destino_local
        destino = destino_local(datos['id_local_destino'])
    if destino:
        local_relacionado = destino['nombre']

    error_relacion = _validar_relacion_movimiento(
        configuracion,
        local_relacionado,
        id_proveedor,
    )

    if error_relacion:
        return {"mensaje": error_relacion}, 400

    detalles, error_detalles = (
        _validar_detalles_movimiento(
            datos.get("detalles")
        )
    )

    if error_detalles:
        return {"mensaje": error_detalles}, 400

    if local_relacionado and len(local_relacionado) > 150:
        return {
            "mensaje": "El nombre del local es demasiado largo"
        }, 400

    if observacion and len(observacion) > 500:
        return {
            "mensaje": (
                "La observación no puede superar "
                "los 500 caracteres"
            )
        }, 400

    try:
        codigo = generar_codigo_movimiento()

        id_movimiento = crear_cabecera_movimiento(
            codigo=codigo,
            tipo_movimiento=(
                configuracion["tipo_movimiento"]
            ),
            motivo_movimiento=motivo,
            fecha_movimiento=fecha_movimiento,
            id_usuario=id_usuario,
            local_relacionado=local_relacionado,
            id_proveedor=id_proveedor,
            observacion=observacion,
        )

        for detalle in detalles:
            crear_detalle_movimiento(
                id_movimiento=id_movimiento,
                id_producto=detalle["id_producto"],
                cantidad=detalle["cantidad"],
            )

        if seguimiento:
            from app.modules.movimientos.tracking import registrar_salida
            registrar_salida(id_movimiento, destino)

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="MOVIMIENTO_INVENTARIO",
            accion="CREAR",
            id_registro_afectado=id_movimiento,
            descripcion=(
                f"Registró el movimiento {codigo} "
                f"de tipo {motivo}"
            ),
        )

        db.session.commit()

        return {
            "mensaje": "Movimiento registrado correctamente",
            "movimiento": _serializar_movimiento(
                id_movimiento
            ),
        }, 201

    except Exception:
        db.session.rollback()
        raise