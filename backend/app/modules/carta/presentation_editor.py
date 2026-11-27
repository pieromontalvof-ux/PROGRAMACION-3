from decimal import Decimal, InvalidOperation

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.core.units import catalogo_unidades, valores_unidades, normalizar_medida, unidad_almacenamiento, obtener_unidad
from app.modules.auditoria.service import registrar_actividad, registrar_cambio
from app.modules.recetas.editor_service import DatosInvalidos, cantidad, identidad
from .measurements import ensure_fits, listar_medidas_menaje, obtener_menaje_con_bloqueo, serialize


def tipos_articulo():
    return db.session.execute(select(func.public.carta_editor_tipos())).scalar_one()


def _filas(consulta, *columnas):
    filas = consulta.table_valued(*columnas)
    return [dict(fila) for fila in db.session.execute(select(filas)).mappings()]


def formulario_presentacion():
    return {"tipos": tipos_articulo(),
            "unidades": valores_unidades('presentacion'),
            "unidades_medida": catalogo_unidades('presentacion'),
            "categorias": _filas(func.public.carta_editor_categorias(), 'id_categoria_carta', 'nombre', 'activo'),
            "menajes": [serialize(row) for row in listar_medidas_menaje()],
            "items": _filas(func.public.carta_editor_articulos(), 'id_item_carta', 'codigo', 'nombre', 'id_categoria_carta', 'tipo', 'activo')}, 200


def guardar_presentacion(id_usuario, datos, id_presentacion=None):
    if not isinstance(datos, dict):
        return {'mensaje': 'Datos invalidos'}, 400
    try:
        # Mismo orden que la administracion de categorias; serializa altas y duplicados.
        db.session.execute(select(func.public.carta_editor_bloquear_categorias()))
        db.session.execute(select(func.public.carta_editor_bloquear_articulos()))
        anterior = None
        if id_presentacion is not None:
            encontrados = _filas(func.public.carta_editor_bloquear_presentacion(id_presentacion), 'id_presentacion_venta', 'id_item_carta', 'id_menaje', 'contenido', 'unidad', 'precio', 'activo')
            if not encontrados:
                db.session.rollback()
                return {'mensaje': 'La presentacion no existe'}, 404
            anterior = encontrados[0]
        id_item = anterior['id_item_carta'] if anterior else datos.get('id_item_carta')
        item = None
        if id_item is not None:
            id_item = identidad(id_item)
            encontrados = _filas(func.public.carta_editor_bloquear_articulo(id_item), 'id_item_carta', 'codigo', 'nombre', 'id_categoria_carta', 'tipo', 'activo')
            if not encontrados:
                raise DatosInvalidos('Selecciona un articulo existente')
            item = encontrados[0]
            if not anterior and not item['activo']:
                raise DatosInvalidos('Selecciona un articulo activo')
        nombre = datos.get('nombre_item')
        tipo = datos.get('tipo_item')
        if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 200:
            raise DatosInvalidos('Ingresa el nombre del articulo (hasta 200 caracteres)')
        nombre = nombre.strip()
        if tipo not in tipos_articulo():
            raise DatosInvalidos('Selecciona un tipo valido')
        categoria = identidad(datos.get('id_categoria_carta'))
        if not item or categoria != item['id_categoria_carta']:
            if not db.session.execute(select(func.public.carta_editor_categoria_activa(categoria))).scalar():
                raise DatosInvalidos('Selecciona una categoria activa')
        if item and not anterior and (nombre != item['nombre'] or tipo != item['tipo'] or categoria != item['id_categoria_carta']):
            raise DatosInvalidos('Para cambiar el articulo utiliza Editar una presentacion existente')
        if db.session.execute(select(func.public.carta_editor_articulo_nombre_existe(nombre, id_item or 0))).scalar():
            raise DatosInvalidos('Ya existe ese articulo; seleccionalo en Articulo existente')
        try:
            contenido, unidad = normalizar_medida(datos.get('contenido'), datos.get('unidad'), 'presentacion')
        except ValueError as error:
            raise DatosInvalidos(str(error)) from None
        contenido = cantidad(contenido)
        unidad = unidad_almacenamiento(unidad)
        menaje = identidad(datos.get('id_menaje'))
        menajes=obtener_menaje_con_bloqueo(menaje)
        if not menajes or not menajes[0].get('activo', True):
            if not anterior or anterior['id_menaje'] != menaje:
                raise DatosInvalidos('Selecciona un menaje activo')
        if menajes:
            try:
                ensure_fits(menajes[0],contenido,unidad)
            except ValueError as error:
                raise DatosInvalidos(str(error)) from None
        try:
            precio = Decimal(str(datos.get('precio')))
            if not precio.is_finite() or precio < 0 or precio > Decimal('99999999.99') or precio != precio.quantize(Decimal('0.01')):
                raise InvalidOperation
        except (InvalidOperation, ValueError):
            raise DatosInvalidos('Precio invalido; usa hasta dos decimales')
        activo = datos.get('activo')
        if not isinstance(activo, bool):
            raise DatosInvalidos('Selecciona el estado de la presentacion')
        if item and tipo == 'DIRECTO' and db.session.execute(select(func.public.carta_editor_articulo_receta_multiple(id_item))).scalar():
            raise DatosInvalidos('Las recetas existentes tienen varios ingredientes; no puedes cambiar a Directo')
        if item is None:
            categoria = identidad(datos.get('id_categoria_carta'))
            secuencia = _filas(func.public.carta_editor_reservar_codigo(categoria), 'prefijo', 'numero')
            if not secuencia:
                raise DatosInvalidos('Selecciona una categoria activa')
            codigo = f"{secuencia[0]['prefijo']}-{secuencia[0]['numero']:03d}"
            if len(codigo) > 10:
                raise DatosInvalidos('El codigo generado excede el limite')
            id_item = db.session.execute(select(func.public.carta_editor_crear_articulo(codigo, nombre, categoria, tipo))).scalar_one()
        else:
            db.session.execute(select(func.public.carta_editor_editar_articulo(nombre, tipo, categoria, id_item)))
        if anterior:
            db.session.execute(select(func.public.carta_editor_editar_presentacion(
                menaje, contenido, unidad, precio, activo, id_presentacion,
            )))
        else:
            id_presentacion = db.session.execute(select(func.public.carta_editor_crear_presentacion(
                id_item, menaje, contenido, unidad, precio, activo,
            ))).scalar_one()
        nuevo_item = _filas(func.public.carta_editor_leer_articulo(id_item), 'id_item_carta', 'codigo', 'nombre', 'id_categoria_carta', 'tipo', 'activo')[0]
        registrar_cambio(id_usuario, 'CARTA', 'EDITAR' if item else 'CREAR', 'item_carta', id_item, item, nuevo_item)
        nuevo = _filas(func.public.carta_editor_leer_presentacion(id_presentacion), 'id_presentacion_venta', 'id_item_carta', 'id_menaje', 'contenido', 'unidad', 'precio', 'activo')[0]
        registrar_cambio(id_usuario, 'CARTA', 'EDITAR' if anterior else 'CREAR', 'presentacion_venta', id_presentacion, anterior, nuevo)
        registrar_actividad(id_usuario, 'CARTA', 'EDITAR' if anterior else 'CREAR', id_presentacion, f'Guardo presentacion de {nombre}')
        db.session.commit()
        return {'mensaje': 'Presentacion guardada. Su receta se configura en Recetas.', 'id_presentacion_venta': id_presentacion}, 200 if anterior else 201
    except DatosInvalidos as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'Ya existe esa presentacion o los datos no cumplen las restricciones. Edita el registro existente.'}, 409
    except Exception:
        db.session.rollback()
        raise
