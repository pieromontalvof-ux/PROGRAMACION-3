from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad, registrar_cambio
from app.modules.recetas import editor_repository as repo
from .measurements import validated,SELECT_SQL,FIELDS


def guardar_menaje(id_usuario, accion, datos, id_menaje=None):
    if not isinstance(datos, dict):
        return {'mensaje': 'Datos invalidos'}, 400
    try:
        repo.ejecutar('LOCK TABLE menaje IN SHARE ROW EXCLUSIVE MODE')
        anterior = None
        if id_menaje is not None:
            filas = repo.filas(SELECT_SQL+' WHERE m.id_menaje=:id FOR UPDATE OF m', {'id': id_menaje})
            if not filas:
                db.session.rollback()
                return {'mensaje': 'El menaje no existe'}, 404
            anterior = filas[0]
        if accion in ('desactivar', 'eliminar') and repo.ejecutar('SELECT EXISTS(SELECT 1 FROM presentacion_venta WHERE id_menaje=:id)', {'id': id_menaje}).scalar():
            db.session.rollback()
            return {'mensaje': 'El menaje tiene presentaciones asignadas, incluidas inactivas. Cambia su menaje en Presentaciones de venta antes de continuar.'}, 409
        if accion in ('crear', 'editar'):
            nombre = datos.get('nombre')
            if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 100:
                raise ValueError('Ingresa un nombre de hasta 100 caracteres')
            nombre = nombre.strip()
            medidas=validated(datos,anterior)
            if repo.ejecutar('SELECT EXISTS(SELECT 1 FROM menaje WHERE lower(trim(nombre))=lower(:nombre) AND id_menaje<>:id)', {'nombre': nombre, 'id': id_menaje or 0}).scalar():
                db.session.rollback()
                return {'mensaje': 'Ya existe un menaje con ese nombre'}, 409
            if accion == 'crear':
                id_menaje = repo.ejecutar('INSERT INTO menaje(nombre,activo) VALUES (:nombre,true) RETURNING id_menaje', {'nombre': nombre}).scalar_one()
            else:
                repo.ejecutar('UPDATE menaje SET nombre=:nombre WHERE id_menaje=:id', {'id': id_menaje, 'nombre': nombre})
            changed=any(medidas[key] != (anterior or {}).get(key) for key in FIELDS)
            origen='REGISTRADO' if changed else (anterior or {}).get('origen_medidas')
            repo.ejecutar('''INSERT INTO menaje_medida(id_menaje,capacidad,unidad_capacidad,diametro_cm,altura_cm,largo_cm,ancho_cm,origen_medidas)
                VALUES(:id,:capacidad,:unidad_capacidad,:diametro_cm,:altura_cm,:largo_cm,:ancho_cm,:origen)
                ON CONFLICT(id_menaje) DO UPDATE SET capacidad=EXCLUDED.capacidad,
                unidad_capacidad=EXCLUDED.unidad_capacidad,diametro_cm=EXCLUDED.diametro_cm,altura_cm=EXCLUDED.altura_cm,
                largo_cm=EXCLUDED.largo_cm,ancho_cm=EXCLUDED.ancho_cm,origen_medidas=EXCLUDED.origen_medidas''',{'id':id_menaje,'origen':origen,**medidas})
        elif accion in ('desactivar', 'reactivar'):
            repo.ejecutar('UPDATE menaje SET activo=:activo WHERE id_menaje=:id', {'id': id_menaje, 'activo': accion == 'reactivar'})
        elif accion == 'eliminar':
            repo.ejecutar('DELETE FROM menaje_medida WHERE id_menaje=:id', {'id': id_menaje})
            repo.ejecutar('DELETE FROM menaje WHERE id_menaje=:id', {'id': id_menaje})
        else:
            raise ValueError('Accion invalida')
        nuevo = None if accion == 'eliminar' else repo.filas(SELECT_SQL+' WHERE m.id_menaje=:id', {'id': id_menaje})[0]
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
