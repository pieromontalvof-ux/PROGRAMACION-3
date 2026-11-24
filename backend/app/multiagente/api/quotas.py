"""Durable token accounting; separate transactions never commit business changes."""
import json
from datetime import datetime, timezone, timedelta
from uuid import uuid4
from contextlib import contextmanager
from contextvars import ContextVar
from flask import has_request_context, has_app_context
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import text
from app.core.extensions import db

_principal = ContextVar('ia_quota_principal', default=None)


def principal():
    inherited = _principal.get()
    if inherited is not None:
        return inherited
    if has_request_context():
        try:
            claims = get_jwt()
            if get_jwt_identity():
                return {'usuario': int(get_jwt_identity()), 'perfil': int(claims['id_perfil']), 'local': int(claims['id_local'])}
        except RuntimeError:
            pass
    return None


@contextmanager
def accounting_scope(scope):
    token = _principal.set(scope)
    try:
        yield
    finally:
        _principal.reset(token)


def periods(now=None):
    # Peru uses UTC-05 without seasonal changes; also works on Windows without tzdata.
    day = (now or datetime.now(timezone.utc)).astimezone(timezone(timedelta(hours=-5))).date()
    return day, day.replace(day=1)


def validate_limit(value):
    if value is not None and (type(value) is not int or not 0 <= value <= 10**12):
        raise ValueError('El límite debe ser un entero entre 0 y 1 billón, o vacío para sin límite.')
    return value


def exceeds(limit, used, amount):
    return limit is not None and used + amount > limit


def reservation_size(body):
    payload = json.loads(body)
    output = payload.get('max_output_tokens', 0)
    if type(output) is not int or output <= 0:
        raise ValueError('La llamada necesita un máximo de tokens de salida.')
    return len(body) + output


def lock(connection):
    connection.execute(text('SELECT pg_advisory_xact_lock(20261124, 17)'))


def ready(connection):
    return connection.execute(text("SELECT to_regclass('public.ia_cuota_config')")).scalar() is not None


def is_enabled():
    with db.engine.connect() as connection:
        return bool(connection.execute(text('SELECT consultas_habilitadas FROM public.ia_cuota_config WHERE id=1')).scalar_one())


def ensure_enabled():
    from .provider import AssistantError
    if not has_app_context():
        return
    with db.engine.connect() as connection:
        if not ready(connection):
            raise AssistantError('Falta aplicar la migración de límites de IA.', 503)
        enabled = connection.execute(text('SELECT consultas_habilitadas FROM public.ia_cuota_config WHERE id=1')).scalar_one()
        if not enabled:
            raise AssistantError('El asistente está desactivado por el administrador.', 503)


def set_enabled(enabled, administrator):
    from .provider import AssistantError
    if type(enabled) is not bool:
        raise AssistantError('Selecciona un estado válido para el asistente.', 400)
    with db.engine.begin() as connection:
        lock(connection)
        old = connection.execute(text('SELECT consultas_habilitadas FROM public.ia_cuota_config WHERE id=1')).scalar_one()
        connection.execute(text('UPDATE public.ia_cuota_config SET consultas_habilitadas=:enabled,actualizado_por=:admin,actualizado_en=now() WHERE id=1'), {'enabled': enabled, 'admin': administrator})
        connection.execute(text('''INSERT INTO public.ia_cuota_auditoria(administrador,anterior,nuevo)
          VALUES(:admin,CAST(:old AS jsonb),CAST(:new AS jsonb))'''),
          {'admin': administrator, 'old': json.dumps({'consultas_habilitadas': old}), 'new': json.dumps({'consultas_habilitadas': enabled})})


def reserve(body):
    from .provider import AssistantError
    scope = principal()
    if scope is None and not has_app_context():
        return None
    if scope is None:
        raise AssistantError('La llamada de IA necesita un usuario responsable del consumo.', 503)
    user = scope['usuario']
    payload = json.loads(body)
    amount = reservation_size(body)
    day, month = periods()
    with db.engine.begin() as connection:
        if not ready(connection):
            raise AssistantError('Falta aplicar la migración de límites de IA. Contacta al administrador.', 503)
        lock(connection)
        config = connection.execute(text('SELECT * FROM public.ia_cuota_config WHERE id=1')).mappings().one()
        if not config['consultas_habilitadas']:
            raise AssistantError('El asistente está desactivado por el administrador.', 503)
        custom = connection.execute(text('SELECT * FROM public.ia_cuota_usuario WHERE id_usuario=:u'), {'u': user}).mappings().first()
        limits = custom or config
        usage = connection.execute(text('''SELECT
          COALESCE(sum(total) FILTER(WHERE dia=:d AND id_usuario=:u),0) ud,
          COALESCE(sum(total) FILTER(WHERE id_usuario=:u),0) um,
          COALESCE(sum(total) FILTER(WHERE dia=:d),0) gd, COALESCE(sum(total),0) gm
          FROM public.ia_consumo WHERE mes=:m'''), {'u': user, 'd': day, 'm': month}).mappings().one()
        if config['activo']:
            # Byte bound is valid for textual BPE input. Media need a separate counter.
            if any(marker in body for marker in (b'input_image', b'input_file', b'input_audio')):
                raise AssistantError('Con cuotas activas, utiliza texto; los adjuntos requieren un contador multimedia.', 400)
            capped = any(value is not None for value in (limits['diario'], limits['mensual'], config['global_diario'], config['global_mensual']))
            if capped and any(tool.get('type') != 'function' for tool in payload.get('tools', [])):
                raise AssistantError('La búsqueda web y otras herramientas externas necesitan un presupuesto independiente: pueden añadir tokens que no están en la solicitud. Esta llamada no se envió.', 429)
            for limit, used, label in ((limits['diario'], usage['ud'], 'diario del usuario'),
                    (limits['mensual'], usage['um'], 'mensual del usuario'),
                    (config['global_diario'], usage['gd'], 'diario general'),
                    (config['global_mensual'], usage['gm'], 'mensual general')):
                if exceeds(limit, used, amount):
                    raise AssistantError(f'No hay saldo suficiente en el límite {label} para reservar esta llamada. Contacta al administrador.', 429)
        identity = str(uuid4())
        connection.execute(text('''INSERT INTO public.ia_consumo
          (id,id_usuario,id_perfil,id_local,dia,mes,modelo,reservado,total,estado)
          VALUES(:id,:u,:p,:l,:d,:m,:model,:n,:n,'RESERVADO')'''),
          {'id': identity, 'u': user, 'p': scope['perfil'], 'l': scope['local'],
           'd': day, 'm': month, 'model': str(payload.get('model', ''))[:150], 'n': amount})
        return identity


def settle(identity, data=None, released=False):
    if identity is None:
        return
    usage = (data or {}).get('usage') or {}
    incoming, outgoing = usage.get('input_tokens'), usage.get('output_tokens')
    confirmed = all(type(v) is int and v >= 0 for v in (incoming, outgoing))
    state = 'LIBERADO' if released else 'CONFIRMADO' if confirmed else 'INCIERTO'
    with db.engine.begin() as connection:
        connection.execute(text('''UPDATE public.ia_consumo SET estado=:s,
          entrada=:i,salida=:o,total=CASE WHEN :released THEN 0 WHEN :confirmed THEN :t ELSE reservado END,
          terminado_en=now() WHERE id=:id AND estado='RESERVADO' '''),
          {'s': state, 'i': incoming if confirmed else None, 'o': outgoing if confirmed else None,
           'released': released, 'confirmed': confirmed, 't': incoming + outgoing if confirmed else 0, 'id': identity})


def report():
    from .provider import AssistantError
    day, month = periods()
    with db.engine.connect() as connection:
        if not ready(connection):
            raise AssistantError('Falta aplicar 20261124_ai_quotas.sql.', 503)
        config = dict(connection.execute(text('SELECT activo,diario,mensual,global_diario,global_mensual,consultas_habilitadas FROM public.ia_cuota_config WHERE id=1')).mappings().one())
        users = connection.execute(text('''SELECT u.id_usuario,
          concat_ws(' ',u.nombres,u.apellido_paterno,u.apellido_materno) nombre,
          u.correo_electronico correo, q.id_usuario IS NOT NULL personalizado,
          CASE WHEN q.id_usuario IS NULL THEN c.diario ELSE q.diario END diario,
          CASE WHEN q.id_usuario IS NULL THEN c.mensual ELSE q.mensual END mensual,
          COALESCE(sum(x.total) FILTER(WHERE x.dia=:d),0) consumo_diario,
          COALESCE(sum(x.total),0) consumo_mensual,
          COALESCE(sum(x.total) FILTER(WHERE x.estado IN ('RESERVADO','INCIERTO')),0) pendiente
          FROM public.usuario u CROSS JOIN public.ia_cuota_config c
          LEFT JOIN public.ia_cuota_usuario q ON q.id_usuario=u.id_usuario
          LEFT JOIN public.ia_consumo x ON x.id_usuario=u.id_usuario AND x.mes=:m
          WHERE c.id=1 GROUP BY u.id_usuario,q.id_usuario,c.id ORDER BY nombre'''), {'d': day, 'm': month}).mappings().all()
        rows = [dict(r) for r in users]
        roles = [dict(r) for r in connection.execute(text('SELECT id_perfil AS id,nombre FROM public.perfiles WHERE estado_registro=1 ORDER BY nombre')).mappings()]
        locations = [dict(r) for r in connection.execute(text('SELECT id_local AS id,nombre FROM public.local WHERE estado_registro=1 ORDER BY nombre')).mappings()]
        role_assignments = connection.execute(text('''SELECT up.id_usuario,p.id_perfil AS id,p.nombre
          FROM public.usuario_perfiles up JOIN public.perfiles p USING(id_perfil)
          WHERE up.estado_registro=1 AND p.estado_registro=1 ORDER BY p.nombre''')).mappings().all()
        local_assignments = connection.execute(text('''SELECT ul.id_usuario,l.id_local AS id,l.nombre
          FROM public.usuario_local ul JOIN public.local l USING(id_local)
          WHERE ul.estado_registro=1 AND l.estado_registro=1 ORDER BY l.nombre''')).mappings().all()
        by_role, by_local = {}, {}
        for assigned in role_assignments:
            by_role.setdefault(assigned['id_usuario'], []).append({'id': assigned['id'], 'nombre': assigned['nombre']})
        for assigned in local_assignments:
            by_local.setdefault(assigned['id_usuario'], []).append({'id': assigned['id'], 'nombre': assigned['nombre']})
        # PostgreSQL SUM(bigint) is numeric/Decimal; Flask would serialize it as text.
        for row in rows:
            row['roles'] = by_role.get(row['id_usuario'], [])
            row['locales'] = locations if any(role['id'] == 1 for role in row['roles']) else by_local.get(row['id_usuario'], [])
            for field in ('consumo_diario', 'consumo_mensual', 'pendiente'):
                row[field] = int(row[field])
        return {'configuracion': config, 'usuarios': rows, 'roles': roles, 'locales': locations, 'dia': day.isoformat(), 'mes': month.isoformat()}


def save(data, administrator, user=None):
    from .provider import AssistantError
    fields = ('diario', 'mensual') if user else ('diario', 'mensual', 'global_diario', 'global_mensual')
    try:
        values = {key: validate_limit(data[key]) for key in fields}
        if not user:
            if type(data['activo']) is not bool:
                raise ValueError('Activo debe ser verdadero o falso.')
            values['activo'] = data['activo']
    except (KeyError, ValueError) as error:
        raise AssistantError(str(error), 400) from None
    with db.engine.begin() as connection:
        if not ready(connection):
            raise AssistantError('Falta aplicar la migración de límites.', 503)
        lock(connection)
        table = 'ia_cuota_usuario' if user else 'ia_cuota_config'
        key = 'id_usuario' if user else 'id'
        identity = user or 1
        if user and not connection.execute(text('SELECT 1 FROM public.usuario WHERE id_usuario=:id'), {'id': user}).scalar():
            raise AssistantError('Usuario no encontrado.', 404)
        previous = connection.execute(text(f'SELECT * FROM public.{table} WHERE {key}=:id'), {'id': identity}).mappings().first()
        connection.execute(text(f'''INSERT INTO public.{table} ({key},{','.join(values)},actualizado_por)
          VALUES (:id,{','.join(':'+k for k in values)},:admin)
          ON CONFLICT ({key}) DO UPDATE SET {','.join(k+'=EXCLUDED.'+k for k in values)},
          actualizado_por=:admin,actualizado_en=now()'''), {**values, 'id': identity, 'admin': administrator})
        old = {k: previous[k] for k in values} if previous else {}
        connection.execute(text('''INSERT INTO public.ia_cuota_auditoria(administrador,id_usuario,anterior,nuevo)
          VALUES(:a,:u,CAST(:old AS jsonb),CAST(:new AS jsonb))'''),
          {'a': administrator, 'u': user, 'old': json.dumps(old), 'new': json.dumps(values)})


def inherit(user, administrator):
    from .provider import AssistantError
    with db.engine.begin() as connection:
        if not ready(connection):
            raise AssistantError('Falta aplicar la migración de límites.', 503)
        lock(connection)
        old = connection.execute(text('DELETE FROM public.ia_cuota_usuario WHERE id_usuario=:u RETURNING diario,mensual'), {'u': user}).mappings().first()
        if old:
            connection.execute(text('''INSERT INTO public.ia_cuota_auditoria(administrador,id_usuario,anterior,nuevo)
              VALUES(:a,:u,CAST(:old AS jsonb),'{}'::jsonb)'''),
              {'a': administrator, 'u': user, 'old': json.dumps(dict(old))})
