"""Consulta paginada de eventos y cambios conservando su procedencia."""
from datetime import date
from flask_jwt_extended import get_jwt
from sqlalchemy import func, select
from werkzeug.exceptions import BadRequest, Forbidden
from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.extensions import db
from app.core.local_scope import local_actual


def sanitizar(valor):
    if isinstance(valor, dict):
        return {k: sanitizar(v) for k, v in valor.items()
                if not any(s in k.lower() for s in ('clave', 'password', 'contras', 'token', 'secret', 'hash', 'pin_salon'))}
    if isinstance(valor, list):
        return [sanitizar(v) for v in valor]
    return valor


def historial(args):
    administrador = perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'administrar_globalmente')
    local = None if administrador else local_actual()
    filtro = args.get('local', '')
    globales = filtro == 'global'
    if not administrador and globales:
        raise Forbidden('Solo puedes consultar la actividad de tu local')
    if filtro and not globales:
        try:
            elegido = int(filtro)
            if elegido <= 0: raise ValueError()
        except ValueError:
            raise BadRequest('Local inválido')
        if not administrador and elegido != local:
            raise Forbidden('Solo puedes consultar la actividad de tu local')
        local = elegido
    try:
        pagina = int(args.get('pagina', '1'))
        if not 1 <= pagina <= 100000: raise ValueError()
        desde = date.fromisoformat(args['desde']) if args.get('desde') else None
        hasta = date.fromisoformat(args['hasta']) if args.get('hasta') else None
        if desde and hasta and desde > hasta: raise ValueError()
    except ValueError:
        raise BadRequest('Revisa la página y el intervalo de fechas')
    q = args.get('buscar','').strip()[:150]
    consulta = func.public.auditoria_historial(
        local, globales, desde, hasta, q, f'%{q}%', (pagina-1)*50
    ).table_valued(
        'origen', 'id', 'id_usuario', 'id_perfil_utilizado', 'id_puesto_laboral', 'id_local', 'modulo', 'accion', 'id_registro_afectado', 'descripcion', 'fecha', 'tabla', 'antes', 'despues', 'usuario', 'perfil', 'puesto', 'local', 'usuario_afectado'
    )
    registros = db.session.execute(select(consulta)).mappings().all()
    eventos=[]
    for r in registros[:50]:
        item=dict(r)
        item['fecha']=r['fecha'].isoformat()
        item['antes']=sanitizar(r['antes'])
        item['despues']=sanitizar(r['despues'])
        eventos.append(item)
    opciones = func.public.auditoria_locales(None if administrador else local).table_valued('id_local', 'nombre')
    locales = db.session.execute(select(opciones)).mappings().all()
    return {'eventos':eventos,'pagina':pagina,'hay_mas':len(registros)>50,
            'marca_completa':administrador,'locales':[dict(l) for l in locales]}
