from sqlalchemy import bindparam, func, select

from app.core.extensions import db


def listar_perfiles_permitidos(id_perfil_gestor: int):
    return db.session.execute(
        select(func.public.usuarios_perfiles_permitidos(bindparam('id_perfil_gestor')).table_valued(
            'id_perfil', 'nombre', 'puede_crear', 'puede_editar',
        )),
        {"id_perfil_gestor": id_perfil_gestor},
    ).mappings().all()


def listar_puestos_laborales():
    return db.session.execute(
        select(func.public.usuarios_puestos().table_valued(
            'id_puesto_laboral', 'nombre', 'descripcion',
        )),
    ).mappings().all()


def listar_usuarios_permitidos(id_perfil_gestor, id_local):
    """
    Un usuario es gestionable solamente cuando todos sus perfiles
    activos pueden ser editados por el perfil gestor.

    Esto evita que un Gerente modifique una cuenta que tenga, por
    ejemplo, Gerente y Supervisor simultáneamente.
    """
    return db.session.execute(
        select(func.public.usuarios_listar(bindparam('id_perfil_gestor'), bindparam('id_local')).table_valued(
            'id_usuario', 'dni', 'nombres', 'apellido_paterno', 'apellido_materno', 'celular',
            'correo_electronico', 'estado_registro', 'fecha_creacion', 'ids_puestos_laborales',
            'puestos_laborales', 'ids_perfiles', 'perfiles', 'ids_locales', 'locales',
        )),
        {
            "id_perfil_gestor": id_perfil_gestor,
            "id_local": id_local,
        },
    ).mappings().all()


def perfil_puede_gestionarse(
    id_perfil_gestor: int,
    id_perfil_objetivo: int,
    accion: str,
) -> bool:
    consulta = select(func.public.usuarios_perfil_gestionable(bindparam('id_perfil_gestor'), bindparam('id_perfil_objetivo'), (accion == "crear")))

    return bool(
        db.session.execute(
            consulta,
            {
                "id_perfil_gestor": id_perfil_gestor,
                "id_perfil_objetivo": id_perfil_objetivo,
            },
        ).scalar()
    )


def buscar_usuario_gestionable(
    id_usuario: int,
    id_perfil_gestor: int,
    id_local: int,
):
    """
    Devuelve el usuario únicamente cuando todos sus perfiles
    activos pueden ser editados por el gestor.
    """
    return db.session.execute(
        select(func.public.usuarios_buscar(bindparam('id_usuario'), bindparam('id_perfil_gestor'), bindparam('id_local')).table_valued(
            'id_usuario', 'id', 'ids_perfiles',
        )),
        {
            "id_usuario": id_usuario,
            "id_perfil_gestor": id_perfil_gestor,
            "id_local": id_local,
        },
    ).mappings().first()


def puestos_laborales_existen(ids_puestos_laborales: list[int]) -> bool:
    if not ids_puestos_laborales:
        return True
    return bool(
        db.session.execute(
            select(func.public.usuarios_puestos_existen(bindparam('cantidad'), bindparam('ids_puestos_laborales'))),
            {
                "ids_puestos_laborales": ids_puestos_laborales,
                "cantidad": len(ids_puestos_laborales),
            },
        ).scalar()
    )


def existe_dni(dni: str, excluir_id: int | None = None) -> bool:
    return bool(
        db.session.execute(
            select(func.public.usuarios_dni_existe(bindparam('dni'), bindparam('excluir_id'))),
            {
                "dni": dni,
                "excluir_id": excluir_id,
            },
        ).scalar()
    )


def existe_correo(
    correo: str,
    excluir_id: int | None = None,
) -> bool:
    return bool(
        db.session.execute(
            select(func.public.usuarios_correo_existe(bindparam('correo'), bindparam('excluir_id'))),
            {
                "correo": correo,
                "excluir_id": excluir_id,
            },
        ).scalar()
    )


def crear_usuario(
    datos: dict,
    clave_hash: str,
    id_gestor: int,
):
    return db.session.execute(
        select(func.public.usuarios_crear(
            bindparam('dni'), bindparam('nombres'), bindparam('apellido_paterno'),
            bindparam('apellido_materno'), bindparam('celular'), bindparam('correo'),
            bindparam('clave'), bindparam('id_gestor'),
        )),
        {
            **datos,
            "clave": clave_hash,
            "id_gestor": id_gestor,
        },
    ).scalar_one()


def asignar_perfil(
    id_usuario: int,
    id_perfil: int,
    id_gestor: int,
):
    db.session.execute(
        select(func.public.usuarios_asignar_perfil(bindparam('id_usuario'), bindparam('id_perfil'), bindparam('id_gestor'))),
        {
            "id_usuario": id_usuario,
            "id_perfil": id_perfil,
            "id_gestor": id_gestor,
        },
    )


def sincronizar_perfiles(
    id_usuario: int,
    ids_perfiles: list[int],
    id_gestor: int,
):
    """
    Desactiva las asignaciones anteriores y reactiva o crea las
    seleccionadas. No elimina registros históricos.
    """
    db.session.execute(
        select(func.public.usuarios_desactivar_perfiles(bindparam('id_gestor'), bindparam('id_usuario'))),
        {
            "id_usuario": id_usuario,
            "id_gestor": id_gestor,
        },
    )

    for id_perfil in ids_perfiles:
        asignar_perfil(
            id_usuario=id_usuario,
            id_perfil=id_perfil,
            id_gestor=id_gestor,
        )


def sincronizar_puestos_laborales(
    id_usuario: int,
    ids_puestos_laborales: list[int],
    id_gestor: int,
):
    db.session.execute(
        select(func.public.usuarios_desactivar_puestos(bindparam('id_gestor'), bindparam('id_usuario'))),
        {"id_usuario": id_usuario, "id_gestor": id_gestor},
    )

    for id_puesto in ids_puestos_laborales:
        db.session.execute(
            select(func.public.usuarios_asignar_puesto(bindparam('id_usuario'), bindparam('id_puesto_laboral'), bindparam('id_gestor'))),
            {
                "id_usuario": id_usuario,
                "id_puesto_laboral": id_puesto,
                "id_gestor": id_gestor,
            },
        )


def actualizar_usuario(
    id_usuario: int,
    datos: dict,
    id_gestor: int,
    clave_hash: str | None = None,
):
    db.session.execute(
        select(func.public.usuarios_actualizar(
            bindparam('dni'), bindparam('nombres'), bindparam('apellido_paterno'),
            bindparam('apellido_materno'), bindparam('celular'), bindparam('correo'),
            bindparam('clave'), bindparam('id_gestor'), bindparam('id_usuario'),
        )),
        {
            **datos,
            "id_usuario": id_usuario,
            "id_gestor": id_gestor,
            "clave": clave_hash,
        },
    )


def cambiar_estado_usuario(
    id_usuario: int,
    estado: int,
    id_gestor: int,
):
    db.session.execute(
        select(func.public.usuarios_cambiar_estado(bindparam('estado'), bindparam('id_gestor'), bindparam('id_usuario'))),
        {
            "id_usuario": id_usuario,
            "estado": estado,
            "id_gestor": id_gestor,
        },
    )

def listar_locales_activos():
    return db.session.execute(
        select(func.public.usuarios_locales_activos().table_valued(
            'id_local', 'codigo', 'nombre', 'direccion',
        ))
    ).mappings().all()


def locales_activos_validos(ids_locales: list[int]) -> bool:
    if not ids_locales:
        return False

    cantidad = db.session.execute(
        select(func.public.usuarios_contar_locales(bindparam('ids_locales'))),
        {"ids_locales": ids_locales},
    ).scalar_one()

    return cantidad == len(set(ids_locales))


def sincronizar_locales_usuario(
    id_usuario: int,
    ids_locales: list[int],
    id_gestor: int,
):
    """Desactiva locales anteriores y activa los seleccionados."""
    db.session.execute(
        select(func.public.usuarios_desactivar_locales(bindparam('id_gestor'), bindparam('id_usuario'))),
        {
            "id_usuario": id_usuario,
            "id_gestor": id_gestor,
        },
    )

    for id_local in ids_locales:
        db.session.execute(
            select(func.public.usuarios_asignar_local(bindparam('id_usuario'), bindparam('id_local'), bindparam('id_gestor'))),
            {
                "id_usuario": id_usuario,
                "id_local": id_local,
                "id_gestor": id_gestor,
            },
        )
