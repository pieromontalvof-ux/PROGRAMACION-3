from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad, registrar_cambio
from .measurements import FIELDS, listar_medidas_menaje, obtener_menaje_con_bloqueo, validated


def guardar_menaje(id_usuario, accion, datos, id_menaje=None):
    if not isinstance(datos, dict):
        return {'mensaje': 'Datos invalidos'}, 400
    try:
        db.session.execute(select(func.public.carta_admin_menaje_bloquear()))
        anterior = None
        if id_menaje is not None:
            filas = obtener_menaje_con_bloqueo(id_menaje, edicion=True)
            if not filas:
                db.session.rollback()
                return {'mensaje': 'El menaje no existe'}, 404
            anterior = filas[0]
        if accion in ('desactivar', 'eliminar') and db.session.execute(select(func.public.carta_admin_menaje_tiene_presentaciones(id_menaje))).scalar():
            db.session.rollback()
            return {'mensaje': 'El menaje tiene presentaciones asignadas, incluidas inactivas. Cambia su menaje en Presentaciones de venta antes de continuar.'}, 409
        if accion in ('crear', 'editar'):
            nombre = datos.get('nombre')
            if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 100:
                raise ValueError('Ingresa un nombre de hasta 100 caracteres')
            nombre = nombre.strip()
            medidas=validated(datos,anterior)
            if db.session.execute(select(func.public.carta_admin_menaje_nombre_existe(nombre, id_menaje or 0))).scalar():
                db.session.rollback()
                return {'mensaje': 'Ya existe un menaje con ese nombre'}, 409
            if accion == 'crear':
                id_menaje = db.session.execute(select(func.public.carta_admin_menaje_crear(nombre))).scalar_one()
            else:
                db.session.execute(select(func.public.carta_admin_menaje_editar(nombre, id_menaje)))
            changed=any(medidas[key] != (anterior or {}).get(key) for key in FIELDS)
            origen='REGISTRADO' if changed else (anterior or {}).get('origen_medidas')
            db.session.execute(select(func.public.carta_admin_menaje_guardar_medidas(id_menaje, medidas['capacidad'], medidas['unidad_capacidad'], medidas['diametro_cm'], medidas['altura_cm'], medidas['largo_cm'], medidas['ancho_cm'], origen)))
        elif accion in ('desactivar', 'reactivar'):
            db.session.execute(select(func.public.carta_admin_menaje_estado(accion == 'reactivar', id_menaje)))
        elif accion == 'eliminar':
            db.session.execute(select(func.public.carta_admin_menaje_borrar_medidas(id_menaje)))
            db.session.execute(select(func.public.carta_admin_menaje_eliminar(id_menaje)))
        else:
            raise ValueError('Accion invalida')
        nuevo = None if accion == 'eliminar' else listar_medidas_menaje(id_menaje)[0]
        registrar_cambio(id_usuario, 'CARTA', accion.upper(), 'menaje', id_menaje, anterior, nuevo)
        registrar_actividad(id_usuario, 'CARTA', accion.upper(), id_menaje, f"{accion}: menaje {(nuevo or anterior)['nombre']}")
        db.session.commit()
        return {'mensaje': 'Menaje eliminado' if accion == 'eliminar' else 'Menaje guardado correctamente', 'id_menaje': id_menaje}, 201 if accion == 'crear' else 200
    except ValueError as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'El menaje tiene referencias o un nombre duplicado. Actualiza el listado.'}, 409
    except Exception:
        db.session.rollback()
        raise
