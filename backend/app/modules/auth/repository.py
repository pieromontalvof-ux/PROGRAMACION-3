from sqlalchemy import func, select

from app.core.extensions import db


def buscar_usuario(correo: str, clave: str):
    """
    Busca al usuario únicamente por sus credenciales.

    No selecciona ningún perfil porque el usuario puede tener
    varios perfiles asignados.
    """
    filas = func.public.auth_buscar_usuario(correo, clave).table_valued(
        'id_usuario', 'dni', 'nombres', 'apellido_paterno', 'apellido_materno', 'celular',
        'correo_electronico'
    )
    return db.session.execute(select(filas)).mappings().first()


def buscar_usuario_por_id(id_usuario: int):
    """
    Obtiene los datos personales del usuario sin escoger
    automáticamente uno de sus perfiles.
    """
    filas = func.public.auth_buscar_usuario_por_id(id_usuario).table_valued(
        'id_usuario', 'dni', 'nombres', 'apellido_paterno', 'apellido_materno', 'celular',
        'correo_electronico'
    )
    return db.session.execute(select(filas)).mappings().first()


def listar_perfiles_usuario(id_usuario: int):
    """
    Devuelve todos los perfiles activos asignados al usuario.
    """
    filas = func.public.auth_listar_perfiles_usuario(id_usuario).table_valued(
        'id_perfil', 'nombre', 'descripcion'
    )
    return db.session.execute(select(filas)).mappings().all()


def obtener_perfil_usuario(
    id_usuario: int,
    id_perfil: int,
):
    """
    Obtiene un perfil solamente cuando se encuentra asignado
    y activo para el usuario indicado.
    """
    filas = func.public.auth_obtener_perfil_usuario(id_usuario, id_perfil).table_valued(
        'id_perfil', 'nombre', 'descripcion'
    )
    return db.session.execute(select(filas)).mappings().first()


def usuario_tiene_perfil(
    id_usuario: int,
    id_perfil: int,
) -> bool:
    """
    Comprueba que el usuario continúa activo y que el perfil
    del JWT todavía está asignado.
    """
    return bool(db.session.execute(select(func.public.auth_usuario_tiene_perfil(id_usuario, id_perfil))).scalar())


def listar_puestos_usuario(id_usuario: int):
    filas = func.public.auth_listar_puestos_usuario(id_usuario).table_valued(
        'id_puesto_laboral', 'nombre', 'descripcion'
    )
    return db.session.execute(select(filas)).mappings().all()


def obtener_puesto_usuario(id_usuario: int, id_puesto_laboral: int):
    filas = func.public.auth_obtener_puesto_usuario(id_usuario, id_puesto_laboral).table_valued(
        'id_puesto_laboral', 'nombre', 'descripcion'
    )
    return db.session.execute(select(filas)).mappings().first()


def obtener_menu(id_perfil: int):
    """
    Obtiene únicamente el menú y los permisos del perfil activo.
    Los permisos de otros perfiles del usuario no se suman.
    """
    filas = func.public.auth_obtener_menu(id_perfil).table_valued(
        'id_opcion_menu', 'codigo', 'nombre', 'url_menu', 'descripcion', 'id_padre', 'icono',
        'tipo_opcion', 'es_configurable', 'puede_consultar', 'puede_crear', 'puede_editar',
        'puede_revisar', 'puede_cerrar', 'puede_desactivar', 'puede_reactivar', 'puede_eliminar',
        'puede_configurar', 'orden'
    )
    return db.session.execute(select(filas)).mappings().all()


def listar_locales_usuario(id_usuario: int, id_perfil: int):
    locales = func.public.locales_permitidos(id_usuario, id_perfil).table_valued(
        'id_local', 'codigo', 'nombre', 'direccion'
    )
    return db.session.execute(select(locales).order_by(locales.c.nombre)).mappings().all()


def obtener_local_usuario(id_usuario: int, id_local: int, id_perfil: int):
    return next((local for local in listar_locales_usuario(id_usuario, id_perfil)
                 if local["id_local"] == id_local), None)


def perfil_requiere_puesto_activo(id_perfil: int) -> bool:
    consulta = select(func.public.auth_perfil_requiere_puesto(id_perfil))
    return bool(db.session.execute(consulta).scalar())


def perfil_puede_cambiar_local(id_perfil: int) -> bool:
    consulta = select(func.public.auth_perfil_puede_cambiar_local(id_perfil))
    return bool(db.session.execute(consulta).scalar())
