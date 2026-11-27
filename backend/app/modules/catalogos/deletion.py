from flask import Blueprint, jsonify
from flask_jwt_extended import get_jwt_identity
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from app.core.extensions import db
from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import registrar_cambio, registrar_actividad

deletion_bp = Blueprint('catalog_deletion', __name__)
def eliminar_registro(entidad, identidad, usuario):
    try:
        consulta = select(func.public.catalogos_eliminar_registro(entidad, identidad))
        resultado = db.session.execute(consulta).scalar_one()
        if resultado is None:
            db.session.rollback()
            return {'mensaje': 'El registro ya no existe'}, 404
        if 'conflicto' in resultado:
            db.session.rollback()
            return {'mensaje': resultado['conflicto']}, 409
        fila = resultado['registro']
        registrar_cambio(usuario, 'CATALOGOS', 'ELIMINAR', resultado['tabla'], identidad,
                         {'registro': fila, 'detalles': resultado['detalles']}, None)
        registrar_actividad(usuario, 'CATALOGOS', 'ELIMINAR', identidad,
                            f'Elimino {entidad}: {fila.get("nombre", identidad)}')
        db.session.commit()
        return {'mensaje': 'Registro eliminado correctamente'}, 200
    except ValueError as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 409
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'No se puede eliminar: el registro sigue asociado a otros datos.'}, 409
    except Exception:
        db.session.rollback()
        raise


@deletion_bp.delete('/<entidad>/<int:identidad>')
def eliminar(entidad, identidad):
    datos = func.public.catalogos_entidad_eliminable(entidad).table_valued('opcion')
    opcion = db.session.execute(select(datos.c.opcion)).scalar_one_or_none()
    if opcion is None:
        return jsonify({'mensaje': 'Apartado no valido'}), 404

    @requiere_permiso(opcion, 'eliminar')
    def autorizado():
        respuesta, estado = eliminar_registro(entidad, identidad, int(get_jwt_identity()))
        return jsonify(respuesta), estado

    return autorizado()
