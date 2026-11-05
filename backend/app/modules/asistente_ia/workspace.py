"""Durable UI recovery, separate from signed tasks and executable DB drafts.

Revisions survive clears/expiration so a delayed browser save cannot revive a
workspace. Recovery only reads native forms/drafts; it never confirms a change.
"""
import json
from uuid import UUID

from sqlalchemy import (Table, Column, MetaData, Integer, BigInteger, DateTime,
                        JSON, select, update, and_, func, inspect, text)
from sqlalchemy.dialects.postgresql import JSONB, insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from app.core.extensions import db
from . import drafts, forms, tools
from .provider import AssistantError


MAX_BYTES = 200000
EXPIRED = 'La tarea guardada venció o cambió. Inicia una nueva consulta; los cambios ya realizados se conservan.'
table = Table('asistente_ia_workspace', MetaData(),
              Column('id_usuario', Integer, primary_key=True),
              Column('id_perfil', Integer, primary_key=True),
              Column('id_local', Integer, primary_key=True),
              Column('snapshot', JSON(none_as_null=True).with_variant(JSONB(none_as_null=True), 'postgresql')),
              Column('revision', BigInteger, nullable=False),
              Column('actualizado_en', DateTime(timezone=True), nullable=False),
              Column('vence_en', DateTime(timezone=True), nullable=False))


class Conflict(AssistantError):
    def __init__(self, revision):
        super().__init__('La tarea cambió en otra pestaña. Recarga antes de continuar.', 409)
        self.revision = revision


def invalid():
    raise AssistantError('La tarea guardada tiene un formato inválido.', 400)


def object_keys(value, allowed):
    if not isinstance(value, dict) or set(value) - set(allowed):
        invalid()


def string(value, maximum=16000):
    if not isinstance(value, str) or len(value) > maximum:
        invalid()
    return value


def number(value):
    if type(value) is not int or not 0 <= value <= 9007199254740991:
        invalid()
    return value


def boolean(value):
    if type(value) is not bool:
        invalid()
    return value


def identity(value):
    try:
        return str(UUID(value))
    except (ValueError, TypeError, AttributeError):
        invalid()


def plain_json(value, depth=0):
    """Bound display-only query records; reject credentials/transient approvals."""
    if depth > 12:
        invalid()
    if isinstance(value, dict):
        for key, child in value.items():
            string(key, 100)
            if key.lower() in {'token', 'access_token', 'refresh_token', 'authorization',
                               'password', 'contrasena', 'contraseña', 'secret', 'secret_key',
                               'jwt', 'checked', 'confirmar', 'busy'}:
                invalid()
            plain_json(child, depth + 1)
    elif isinstance(value, list):
        if len(value) > 1000:
            invalid()
        for child in value:
            plain_json(child, depth + 1)
    elif isinstance(value, str):
        string(value, 80000)
    elif value is not None and type(value) not in (int, float, bool):
        invalid()
    return value


def form(value):
    if not isinstance(value, dict) or value.get('recurso') not in forms.TITLES:
        invalid()
    # Option lists and labels always come from native server routes on recovery.
    return {'recurso': value['recurso']}


def result(value):
    object_keys(value, ('respuesta', 'borrador', 'consultas', 'agente', 'formulario',
                        'opciones', 'continuacion', 'flujo_compra', 'tarea_pendiente', 'comunicaciones', 'actividad', 'nota_actividad'))
    cleaned = {'respuesta': string(value.get('respuesta', '')), 'borrador': None,
               'consultas': plain_json(value.get('consultas', []))}
    if not isinstance(cleaned['consultas'], list):
        invalid()
    if value.get('actividad'):
        if not isinstance(value['actividad'], dict):
            invalid()
        cleaned['actividad'] = {'id': identity(value['actividad'].get('id'))}
    for key in ('agente', 'continuacion', 'flujo_compra', 'tarea_pendiente', 'nota_actividad'):
        if key in value:
            cleaned[key] = string(value[key], 80000 if key in ('continuacion', 'flujo_compra') else 8000)
    for key in ('opciones', 'comunicaciones'):
        if key in value:
            if not isinstance(value[key], list) or len(value[key]) > 20:
                invalid()
            allowed = ('etiqueta', 'instruccion') if key == 'opciones' else ('de', 'a', 'motivo')
            for item in value[key]:
                object_keys(item, allowed)
                for child in item.values():
                    string(child, 8000)
            cleaned[key] = value[key]
    if value.get('formulario') is not None:
        cleaned['formulario'] = form(value['formulario'])
    if value.get('borrador') is not None:
        if not isinstance(value['borrador'], dict):
            invalid()
        # Never retain editable client plans, review views, or execution results.
        cleaned['borrador'] = {'id_borrador': identity(value['borrador'].get('id_borrador'))}
    return cleaned


def workflow(value):
    object_keys(value, ('frames', 'proposal', 'dirty', 'saved', 'draftId', 'draft_state'))
    frames = value.get('frames')
    if not isinstance(frames, list) or not 1 <= len(frames) <= 7:
        invalid()
    cleaned = {'frames': [], 'proposal': None, 'saved': None, 'dirty': boolean(value.get('dirty', False))}
    fields = {'nombre', 'prefijo', 'categorias', 'proveedor', 'categoria', 'unidad',
              'contenido', 'item', 'tipo', 'menaje', 'precio'}
    for frame in frames:
        object_keys(frame, ('form', 'values', 'version'))
        values = frame.get('values', {})
        object_keys(values, fields)
        for key, child in values.items():
            if key == 'categorias':
                if not isinstance(child, list) or len(child) > 1000:
                    invalid()
                for item in child:
                    number(item)
            else:
                string(child, 1000)
        cleaned['frames'].append({'form': form(frame.get('form')), 'values': values,
                                  'version': number(frame.get('version', 0))})
    if value.get('proposal') is not None:
        cleaned['proposal'] = result(value['proposal'])
    if value.get('draftId') is not None:
        cleaned['draftId'] = identity(value['draftId'])
    # saved is reconstructed from the scoped draft, never browser result IDs.
    if value.get('saved') is not None and not cleaned.get('draftId'):
        invalid()
    return cleaned


def sanitize(value):
    if value is None:
        return None
    try:
        size = len(json.dumps(value, ensure_ascii=False, allow_nan=False).encode('utf-8'))
    except (ValueError, TypeError, RecursionError):
        invalid()
    if size > MAX_BYTES:
        raise AssistantError('La tarea guardada es demasiado grande.', 413)
    object_keys(value, ('version', 'instruction', 'review', 'original', 'context', 'result',
                        'catalogForm', 'formVersion', 'formDirty', 'confirmed', 'lastPrompt',
                        'time', 'history', 'resumeDraft', 'draftId', 'workflow', 'continuation'))
    if type(value.get('version')) is not int or value['version'] != 1:
        invalid()
    cleaned = {'version': 1}
    for key in ('instruction', 'review', 'original', 'context', 'lastPrompt', 'time', 'continuation'):
        if key in value and value[key] is not None:
            cleaned[key] = string(value[key], 80000 if key == 'continuation' else
                                   8000 if key in ('instruction', 'lastPrompt') else 16000)
    for key in ('formDirty', 'confirmed'):
        if key in value:
            cleaned[key] = boolean(value[key])
    if 'formVersion' in value:
        cleaned['formVersion'] = number(value['formVersion'])
    for key in ('resumeDraft', 'draftId'):
        if value.get(key) is not None:
            cleaned[key] = identity(value[key])
    for key, parser in (('result', result), ('catalogForm', form), ('workflow', workflow)):
        if key in value:
            cleaned[key] = parser(value[key]) if value[key] is not None else None
    if 'history' in value:
        history = value['history']
        if not isinstance(history, list) or len(history) > 10:
            invalid()
        for item in history:
            object_keys(item, ('prompt', 'response', 'time', 'done', 'queries', 'actividad'))
            for key in ('prompt', 'response', 'time'):
                string(item.get(key, ''))
            boolean(item.get('done', False))
            if not isinstance(item.get('queries', []), list):
                invalid()
            plain_json(item.get('queries', []))
            if item.get('actividad'):
                if not isinstance(item['actividad'], dict):
                    invalid()
                item['actividad'] = {'id': identity(item['actividad'].get('id'))}
        cleaned['history'] = history
    return cleaned


def restore(session, snapshot):
    """Validate every signed continuation and rebuild every proposal from DB."""
    from app.agents.orchestrator import communication
    cleaned = sanitize(snapshot)
    if cleaned is None:
        return {'workspace': None}
    messages, rows, states = [], {}, {}
    from app.agents import activity
    def refresh_activity(answer):
        if answer and answer.get('actividad'):
            try:
                answer['actividad'] = activity.load(answer['actividad']['id'])
            except AssistantError:
                answer.pop('actividad', None)
    refresh_activity(cleaned.get('result'))
    for turn in cleaned.get('history', []):
        refresh_activity(turn)

    def check_token(token):
        if token:
            states[token] = communication.load(token)

    check_token(cleaned.get('continuation'))
    for answer in (cleaned.get('result'), (cleaned.get('workflow') or {}).get('proposal')):
        if answer:
            check_token(answer.get('continuacion'))
            if answer.get('flujo_compra'):
                from app.agents.orchestrator import purchase_flow
                purchase_flow.load(answer['flujo_compra'])

    def draft(draft_id):
        if draft_id not in rows:
            row = drafts.load(draft_id)
            tools.authorize(session, row['plan']['recurso'], row['plan']['accion'])
            rows[draft_id] = row
        return rows[draft_id]

    def refresh(answer):
        if not answer:
            return None
        if answer.get('formulario'):
            answer['formulario'] = forms.open_form(session, answer['formulario']['recurso'])
        if answer.get('borrador'):
            draft_id = answer['borrador']['id_borrador']
            row = draft(draft_id)
            if row['estado'] == 'PENDIENTE' and row['vigente']:
                plan = row['plan']
                answer['borrador'] = {k: v for k, v in plan.items() if not k.startswith('_')}
                answer['borrador'].update(id_borrador=draft_id, vista=tools.readable(session, plan))
            else:
                answer['borrador'] = None
            return draft_id
        return None

    # Validate every reference even when a newer visible proposal takes priority.
    # Client metadata can never smuggle a foreign completed draft into storage.
    for draft_id in (cleaned.get('draftId'), cleaned.get('resumeDraft'),
                     (cleaned.get('workflow') or {}).get('draftId')):
        if draft_id:
            draft(draft_id)
    top_id = refresh(cleaned.get('result')) or cleaned.get('draftId') or cleaned.get('resumeDraft')
    if cleaned.get('catalogForm'):
        cleaned['catalogForm'] = forms.open_form(session, cleaned['catalogForm']['recurso'])

    def status(draft_id):
        row = draft(draft_id)
        state = {'id_borrador': draft_id, 'estado': row['estado'], 'vigente': bool(row['vigente'])}
        if row['estado'] == 'REALIZADO':
            state['resultado'] = row['resultado']
        elif row['estado'] != 'PENDIENTE' or not row['vigente']:
            messages.append('El borrador venció o ya fue procesado. Revisa el módulo antes de preparar otro cambio; no se repetirá automáticamente.')
        return state

    response = {'workspace': cleaned}
    if top_id:
        state = response['draft_state'] = status(top_id)
        cleaned['draftId'] = top_id
        cleaned['confirmed'] = state['estado'] == 'REALIZADO'
        cleaned['resumeDraft'] = None
        token = cleaned.get('continuation') or (cleaned.get('result') or {}).get('continuacion')
        if state['estado'] == 'REALIZADO' and token and states[token].get('pila'):
            row, task = draft(top_id), states[token]
            plan = row['plan']
            if (plan.get('_coordinacion') == task['paso'] and plan['accion'] == 'crear'
                    and plan['recurso'] == task['actual']['recurso']):
                cleaned['resumeDraft'] = top_id
    nested = cleaned.get('workflow')
    if nested:
        for frame in nested['frames']:
            frame['form'] = forms.open_form(session, frame['form']['recurso'])
        nested_id = refresh(nested.get('proposal')) or nested.get('draftId')
        if nested_id:
            state = nested['draft_state'] = status(nested_id)
            nested['draftId'] = nested_id
            nested['saved'] = state.get('resultado') if state['estado'] == 'REALIZADO' else None
    if messages:
        response['mensaje'] = messages[-1]
    return response


def scoped():
    scope = drafts.scope()
    return and_(table.c.id_usuario == scope['usuario'], table.c.id_perfil == scope['perfil'],
                table.c.id_local == scope['local'])


def require_storage():
    if not inspect(db.session.connection()).has_table(table.name):
        raise AssistantError('Falta ejecutar 20261021_asistente_ia_workspace.sql para guardar la tarea.', 503)


def expires():
    return (func.datetime('now', '+2 hours') if db.engine.dialect.name == 'sqlite'
            else func.now() + text("interval '2 hours'"))


def save(session, snapshot, revision):
    revision = number(revision)
    snapshot = sanitize(snapshot)
    # Validate the signed/scoped references before retaining them; save only the
    # sanitized UI, never the server-enriched response or transient approvals.
    restore(session, snapshot)
    require_storage()
    scope = drafts.scope()
    insert = sqlite_insert if db.engine.dialect.name == 'sqlite' else pg_insert
    db.session.execute(insert(table).values(id_usuario=scope['usuario'], id_perfil=scope['perfil'],
                       id_local=scope['local'], snapshot=None, revision=0,
                       actualizado_en=func.now(), vence_en=expires()).on_conflict_do_nothing())
    current = db.session.execute(update(table).where(scoped(), table.c.revision == revision).values(
        snapshot=snapshot, revision=table.c.revision + 1, actualizado_en=func.now(), vence_en=expires()
    ).returning(table.c.revision)).scalar()
    if current is None:
        latest = db.session.execute(select(table.c.revision).where(scoped())).scalar()
        raise Conflict(latest)
    db.session.commit()
    return {'workspace': snapshot, 'revision': current}


def load(session):
    require_storage()
    # A concurrent clear/update wins; never expire or clear a newer revision.
    for _ in range(3):
        row = db.session.execute(select(table, (table.c.vence_en > func.now()).label('vigente')).where(scoped())).mappings().first()
        if row is None or row['snapshot'] is None:
            db.session.rollback()
            return {'workspace': None, 'revision': row['revision'] if row else 0}
        try:
            if not row['vigente']:
                raise AssistantError(EXPIRED, 409)
            response = restore(session, row['snapshot'])
        except AssistantError as error:
            if error.status >= 500:
                raise
            revision = db.session.execute(update(table).where(scoped(), table.c.revision == row['revision']).values(
                snapshot=None, revision=table.c.revision + 1, actualizado_en=func.now()
            ).returning(table.c.revision)).scalar()
            db.session.commit()
            if revision is not None:
                return {'workspace': None, 'revision': revision, 'mensaje': EXPIRED}
            continue
        db.session.rollback()  # Release scoped draft read locks; no execution.
        return {**response, 'revision': row['revision']}
    raise AssistantError('La tarea cambió en otra pestaña. Recarga antes de continuar.', 409)
