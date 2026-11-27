import re

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad, registrar_cambio


def modificar_categoria(id_categoria, id_usuario, accion, datos):
    """Administracion global; las categorias ocupadas deben vaciarse primero."""
    if not isinstance(datos, dict):
        return {"mensaje": "Datos invalidos"}, 400
    try:
        # Serializa cambios del catalogo y altas de items durante la comprobacion.
        db.session.execute(select(func.public.carta_editor_bloquear_categorias()))
        db.session.execute(select(func.public.carta_editor_bloquear_articulos()))
        actual = db.session.execute(select(func.public.carta_admin_categoria(id_categoria).table_valued('id_categoria_carta', 'nombre', 'prefijo', 'siguiente_numero', 'activo'))).mappings().first()
        if actual is None and accion != 'crear':
            db.session.rollback()
            return {"mensaje": "La categoria no existe"}, 404
        anterior = dict(actual) if actual else None
        items = db.session.execute(select(func.public.carta_admin_articulos(id_categoria).table_valued('id_item_carta', 'codigo', 'id_categoria_carta'))).mappings().all()
        if accion in ('editar', 'desactivar') and items:
            db.session.rollback()
            return {"mensaje": "Reasigna primero todos los articulos, incluidos los inactivos, para editar o desactivar esta categoria."}, 409
        if accion in ('crear', 'editar'):
            nombre = datos.get('nombre')
            prefijo = datos.get('prefijo')
            if not isinstance(nombre, str) or not isinstance(prefijo, str):
                raise ValueError('Ingresa nombre y prefijo')
            nombre, prefijo = nombre.strip(), prefijo.strip().upper()
            if not 1 <= len(nombre) <= 100 or not re.fullmatch(r'[A-Z]{1,5}', prefijo):
                raise ValueError('Nombre de hasta 100 caracteres y prefijo de 1 a 5 letras')
            repetida = db.session.execute(select(func.public.carta_admin_categoria_duplicada(id_categoria, nombre, prefijo))).first()
            if repetida:
                db.session.rollback()
                return {'mensaje': 'El nombre o prefijo ya esta registrado'}, 409
            # Los codigos de items reasignados permanecen reservados globalmente.
            numero = db.session.execute(select(func.public.carta_admin_siguiente_numero('^' + prefijo + '-[0-9]+$'))).scalar_one()
            numero = max(numero, actual['siguiente_numero'] if actual else 1)
            if numero > 2147483647:
                raise ValueError('El prefijo no tiene numeracion disponible')
            if accion == 'crear':
                id_categoria = db.session.execute(select(func.public.carta_admin_crear_categoria(nombre, prefijo, numero))).scalar_one()
            else:
                db.session.execute(select(func.public.carta_admin_editar_categoria(nombre, prefijo, numero, id_categoria)))
        elif accion == 'reasignar':
            destino = datos.get('id_categoria_nueva')
            if type(destino) is not int or destino == id_categoria:
                raise ValueError('Selecciona otra categoria de destino')
            valido = db.session.execute(select(func.public.carta_admin_categoria_activa(destino))).first()
            if not valido or not items:
                raise ValueError('Selecciona una categoria activa y un origen con articulos')
            for item in items:
                previo = dict(item)
                nuevo = {**previo, 'id_categoria_carta': destino}
                registrar_cambio(id_usuario, 'CARTA', 'REASIGNAR', 'item_carta', item['id_item_carta'], previo, nuevo)
            db.session.execute(select(func.public.carta_admin_reasignar_articulos(destino, id_categoria)))
        elif accion in ('desactivar', 'reactivar'):
            db.session.execute(select(func.public.carta_admin_estado_categoria(accion == 'reactivar', id_categoria)))
        else:
            raise ValueError('Accion invalida')
        nuevo = dict(db.session.execute(select(func.public.carta_admin_categoria(id_categoria).table_valued('id_categoria_carta', 'nombre', 'prefijo', 'siguiente_numero', 'activo'))).mappings().one())
        registrar_cambio(id_usuario, 'CARTA', accion.upper(), 'categoria_carta', id_categoria, anterior, nuevo)
        registrar_actividad(id_usuario, 'CARTA', accion.upper(), id_categoria,
                            f"{accion}: categoria {nuevo['nombre']}" + (f"; {len(items)} articulos al destino {datos['id_categoria_nueva']}" if accion == 'reasignar' else ''))
        db.session.commit()
        return {'mensaje': 'Articulos reasignados correctamente' if accion == 'reasignar' else 'Categoria creada correctamente' if accion == 'crear' else 'Categoria actualizada correctamente', 'id_categoria_carta': id_categoria}, 201 if accion == 'crear' else 200
    except ValueError as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'El cambio entra en conflicto con datos existentes. Actualiza el listado.'}, 409
    except Exception:
        db.session.rollback()
        raise
