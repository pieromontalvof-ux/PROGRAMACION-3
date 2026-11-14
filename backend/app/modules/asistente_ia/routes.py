"""Authenticated assistant: read, review, confirm; model never executes writes."""
import time
import json
from functools import wraps
from threading import Lock
from uuid import UUID
from flask import Blueprint, jsonify, request, send_file, current_app
from io import BytesIO
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from app.core.extensions import db
from app.modules.auth.service import obtener_sesion_actual
from . import agent, drafts, provider, tools, forms
from .provider import AssistantError
from app.agents.orchestrator import communication
from app.agents import activity

asistente_ia_bp = Blueprint('asistente_ia', __name__)
MODULOS = {r[0] for r in tools.RESOURCES.values()}
_attempts = {}
_workspace_attempts = {}
_lock = Lock()


def limit():
    key, now = get_jwt_identity(), time.monotonic()
    with _lock:
        for k in list(_attempts):
            _attempts[k] = [t for t in _attempts[k] if now - t < 60]
            if not _attempts[k]: del _attempts[k]
        if len(_attempts.get(key, [])) >= 8:
            raise AssistantError('Espera un minuto antes de enviar más solicitudes al asistente.', 429)
        _attempts.setdefault(key, []).append(now)


def secured(function):
    @wraps(function)
    @jwt_required()
    def wrapped(*args, **kwargs):
        try:
            session, code = obtener_sesion_actual(int(get_jwt_identity()), get_jwt())
            if code != 200: return jsonify(session), code
            if function.__name__ not in ('preparar', 'continuar', 'preparar_formulario'):
                return function(session, *args, **kwargs)
            data = request.get_json(silent=True) or {}
            if not isinstance(data, dict):
                data = {}
            token = activity.begin(data.get('instruccion', 'Continuar tarea' if function.__name__ == 'continuar' else 'Revisar formulario'), drafts.scope())
            try:
                response = current_app.make_response(function(session, *args, **kwargs))
                payload = response.get_json() or {}
                # Direct form shortcuts are programmed routing, not a model handoff.
                if payload.get('agente'):
                    activity.emit('ruta_respuesta', a=payload['agente'], mensaje='Área de la respuesta. Los participantes ejecutados se identifican en los eventos de delegación.')
                payload['actividad'] = activity.finish(payload, response.status_code)
                if payload['actividad'] is None:
                    payload.pop('actividad')
                    payload['nota_actividad'] = 'La respuesta está disponible, pero no se pudo guardar su actividad.'
                response.set_data(current_app.json.dumps(payload))
                return response
            except AssistantError as error:
                activity.finish({'mensaje': str(error)}, error.status)
                raise
            except Exception:
                activity.finish({'mensaje': 'No se pudo completar la solicitud.'}, 500)
                raise
            finally:
                activity.reset(token)
        except AssistantError as error:
            db.session.rollback()
            return jsonify(mensaje=str(error)), error.status
        except Exception:
            db.session.rollback()
            return jsonify(mensaje='No se pudo completar la operación. Si estabas confirmando un cambio, revisa el módulo antes de intentarlo otra vez.'), 500
    return wrapped


@asistente_ia_bp.get('/actividad/<identity>')
@secured
def actividad(session, identity):
    response = jsonify(activity.load(identity))
    response.headers['Cache-Control'] = 'private, no-store'
    return response


def body(max_bytes=100000):
    if request.content_length and request.content_length > max_bytes:
        raise AssistantError('La instrucción es demasiado larga.', 413)
    result = request.get_json(silent=True)
    if not isinstance(result, dict): raise AssistantError('Envía un objeto JSON válido.')
    return result


def identity(value):
    try: return str(UUID(value))
    except (ValueError, TypeError, AttributeError): raise AssistantError('Borrador inválido.') from None


def workspace_limit():
    scope, now = drafts.scope(), time.monotonic()
    key = (scope['usuario'], scope['perfil'], scope['local'])
    with _lock:
        for saved_key in list(_workspace_attempts):
            recent = [stamp for stamp in _workspace_attempts[saved_key] if now - stamp < 60]
            if recent:
                _workspace_attempts[saved_key] = recent
            else:
                del _workspace_attempts[saved_key]
        if len(_workspace_attempts.get(key, [])) >= 120:
            raise AssistantError('Espera un minuto antes de guardar más cambios en la tarea.', 429)
        _workspace_attempts.setdefault(key, []).append(now)


@asistente_ia_bp.get('/workspace')
@secured
def workspace_get(session):
    from . import workspace
    workspace_limit()
    return jsonify(workspace.load(session))


@asistente_ia_bp.put('/workspace')
@secured
def workspace_put(session):
    from . import workspace
    workspace_limit()
    # Autosaves have their own bounded payload; they consume no model quota.
    if request.content_length and request.content_length > workspace.MAX_BYTES:
        raise AssistantError('La tarea guardada es demasiado grande.', 413)
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or set(data) != {'workspace', 'revision'}:
        raise AssistantError('Envía la tarea y su revisión actual.', 400)
    try:
        return jsonify(workspace.save(session, data['workspace'], data['revision']))
    except workspace.Conflict as error:
        db.session.rollback()
        return jsonify(mensaje=str(error), revision=error.revision), 409

@asistente_ia_bp.get('/estado')
@secured
def estado(sesion):
    configured = provider.configured()
    storage = drafts.ready()
    modulos = [dict(nombre=m['nombre'], ruta=m['url_menu'])
               for m in sesion['menu'] if m['id_opcion_menu'] in MODULOS
               and m['permisos']['consultar'] and m['url_menu']]
    return jsonify(estado='disponible' if configured else 'sin_configurar', ia_disponible=configured,
                   dictado_disponible=configured, ejecucion_disponible=storage,
                   capacidades={r:[a for a in ('consultar','crear','editar') if tools.allowed(sesion,r,a)]
                                for r in tools.RESOURCES if tools.allowed(sesion,r)},
                   modulos_consultables=modulos)


@asistente_ia_bp.get('/agentes')
@secured
def agentes(sesion):
    if int(get_jwt().get('id_perfil', 0)) != 1:
        raise AssistantError('Solo el Administrador del sistema puede ver los agentes.', 403)
    from app.agents.manifest import catalog
    from . import configuration
    return jsonify(configuration.decorate(catalog()))


def require_agent_admin():
    if int(get_jwt().get('id_perfil', 0)) != 1:
        raise AssistantError('Solo el Administrador del sistema puede administrar agentes.', 403)


@asistente_ia_bp.get('/biblioteca')
@secured
def biblioteca(session):
    require_agent_admin()
    from . import library
    return jsonify(library.listing())


@asistente_ia_bp.route('/biblioteca/<agent_id>', methods=['GET', 'PUT'])
@secured
def carpeta_agente(session, agent_id):
    require_agent_admin()
    from . import library
    if request.method == 'GET':
        return jsonify(library.view(agent_id))
    raise AssistantError('La edición integral fue retirada. Guarda la skill validada o usa el menú Permisos de agentes.', 410)


@asistente_ia_bp.post('/biblioteca/<agent_id>/revisar')
@secured
def revisar_configuracion_agente(session, agent_id):
    require_agent_admin()
    raise AssistantError('Usa Validar skill en el flujo de skills. Los permisos se administran por separado.', 410)


@asistente_ia_bp.post('/biblioteca/<agent_id>/skills/<operation>')
@secured
def flujo_skill(session, agent_id, operation):
    require_agent_admin()
    from . import configuration
    data = body(1000000)
    if operation == 'validar':
        limit()
        return jsonify(configuration.review_skills(agent_id, data.get('skills'), data.get('revision')))
    if operation == 'guardar':
        return jsonify(configuration.save_skills(agent_id, data.get('skills'), data.get('revision'), data.get('revision_ia')))
    if operation == 'actualizar':
        limit()
        return jsonify(configuration.update_skill(agent_id, data.get('skills'), data.get('archivo_skill'), data.get('documentos'), data.get('revision')))
    raise AssistantError('Operación no disponible.', 404)


@asistente_ia_bp.put('/biblioteca/<agent_id>/accesos')
@secured
def permisos_agente(session, agent_id):
    require_agent_admin()
    from . import configuration
    data = body()
    return jsonify(configuration.save_accesses(agent_id, data.get('accesos'), data.get('revision')))


@asistente_ia_bp.get('/biblioteca/<agent_id>/documentos/<document_id>/original')
@secured
def original_documento_agente(session, agent_id, document_id):
    require_agent_admin()
    from . import library
    content, mime, filename = library.original(agent_id, document_id)
    response = send_file(BytesIO(content), mimetype=mime, download_name=filename, as_attachment=False)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Cache-Control'] = 'no-store'
    return response


@asistente_ia_bp.post('/biblioteca/<agent_id>/documentos')
@secured
def subir_documento_agente(session, agent_id):
    require_agent_admin()
    if request.content_length and request.content_length > 2 * 1024 * 1024 + 65536:
        raise AssistantError('El documento debe pesar como máximo 2 MB.', 413)
    from . import library
    try:
        revision = int(request.form.get('revision', ''))
    except ValueError:
        raise AssistantError('Indica la revisión actual de la carpeta.') from None
    return jsonify(library.upload(agent_id, request.files.get('archivo'), revision)), 201


@asistente_ia_bp.route('/biblioteca/<agent_id>/documentos/<document_id>', methods=['GET', 'DELETE'])
@secured
def documento_agente(session, agent_id, document_id):
    require_agent_admin()
    from . import library
    if request.method == 'GET':
        return jsonify(library.document(agent_id, document_id))
    return jsonify(library.delete(agent_id, document_id, body().get('revision')))


@asistente_ia_bp.post('/preparar')
@secured
def preparar(session):
    data = body()
    if data.get('modo', 'conversacion') not in ('conversacion', 'formulario'):
        raise AssistantError('Selecciona conversación o formulario.')
    instruction, previous = data.get('instruccion'), data.get('borrador_previo', '')
    context = data.get('contexto_previo', '')
    if not isinstance(context, str) or len(context) > 16000:
        raise AssistantError('El contexto de la conversación es demasiado largo. Inicia una nueva consulta.')
    if not isinstance(instruction, str) or not 1 <= len(instruction.strip()) <= 8000 or not isinstance(previous, str) or len(previous) > 16000:
        raise AssistantError('Escribe una instrucción de hasta 8000 caracteres.')
    limit()
    state = communication.load(data['continuacion']) if data.get('continuacion') else None
    if state is None:
        target = forms.detect(instruction)
        if target in forms.TITLES:
            from . import configuration
            configuration.authorize_owner(target, 'crear')
            tools.authorize(session, target, 'crear')
    if data.get('reemplaza'):
        drafts.cancel(identity(data['reemplaza']))
    db.session.rollback()
    if forms.prefers_chat() and (state is None or not state.get('conversacion')):
        from app.agents.orchestrator import presentation_advice
        advice = presentation_advice.run(session, instruction)
        if advice is not None:
            references = advice.pop('_referencias_revisadas')
            reviewed = json.dumps({'contexto_previo': context[-6000:], 'opciones_revisadas': references}, ensure_ascii=False)
            # A full new specification replaces a previous form-oriented task.
            result = communication.coordinate(session, advice, instruction, previous, reviewed, objective='presentaciones')
            return finish_result(session, result)
    if state is not None:
        result = communication.invoke(session, state['actual'], instruction, previous, context)
        result = communication.coordinate(session, result, instruction, previous, context, state)
        return finish_result(session, result)
    resource = forms.detect(instruction) or forms.category_choice(instruction, previous)
    # Missing prerequisites require specialist reasoning, rather than bypassing
    # the coordinator through the shortcut for simple form requests.
    normalized = tools.normalized(instruction)
    if resource != 'categoria_ambigua' and any(term in normalized for term in
            ('no existe', 'no tengo', 'no hay', 'falta', 'crear primero')):
        resource = None
    if resource == 'categoria_ambigua':
        from . import configuration
        options = [{'etiqueta': 'Categoría de productos', 'instruccion': 'Crear categoría de productos', 'recurso': 'categorias_productos'},
                   {'etiqueta': 'Categoría de carta', 'instruccion': 'Crear categoría de carta', 'recurso': 'categorias_carta'}]
        options = [{k: v for k, v in option.items() if k != 'recurso'} for option in options
                   if tools.allowed(session, option['recurso'], 'crear') and tools.allowed(session, option['recurso']) and configuration.owner_allows(option['recurso'], 'crear')]
        if not options:
            raise AssistantError('Tu perfil no tiene permiso para crear categorías.', 403)
        return jsonify(respuesta=forms.CATEGORY_QUESTION, opciones=options, consultas=[], borrador=None, agente='orquestador')
    if resource and not forms.prefers_chat():
        return jsonify(respuesta='Completa el formulario y revisa la propuesta antes de realizar el cambio.',
                       formulario=forms.open_form(session, resource), consultas=[], borrador=None,
                       agente=resource if resource in ('categorias_carta', 'menajes', 'presentaciones') else 'carta_recetas')
    from app.agents.orchestrator import purchase_flow
    result = purchase_flow.handle(session, instruction, previous, context, data.get('flujo_compra'))
    if result is None:
        routed_instruction = instruction
        if resource and forms.detect(instruction) is None:
            routed_instruction = forms.TITLES[resource] + '. Aclaración del usuario: ' + instruction
        result = agent.run(session, routed_instruction, previous, context)
    from app.agents.catalog_specialists import SPECIALISTS
    if result.get('traspaso') or (forms.prefers_chat() and result.get('agente') in ('carta_recetas', *SPECIALISTS)):
        result = communication.coordinate(session, result, instruction, previous, context)
    return finish_result(session, result)


def finish_result(session, result):
    plan = result.pop('plan')
    if plan:
        fresh, code = obtener_sesion_actual(int(get_jwt_identity()), get_jwt())
        if code != 200: return jsonify(fresh), code
        tools.authorize(fresh, plan['recurso'], plan['accion'])
        view = tools.readable(fresh, plan)
        result['borrador'] = {'id_borrador': drafts.save(plan), 'vista': view, **plan}
    else:
        result['borrador'] = None
    return jsonify(result)


@asistente_ia_bp.post('/formulario')
@secured
def formulario(session):
    return jsonify(formulario=forms.open_form(session, body().get('recurso')))


@asistente_ia_bp.post('/formulario/preparar')
@secured
def preparar_formulario(session):
    data = body()
    limit()
    plan = forms.prepare(session, data.get('recurso'), data.get('datos'))
    if data.get('continuacion'):
        communication.bind_plan(communication.load(data['continuacion']), plan)
    view = tools.readable(session, plan)
    if data.get('reemplaza'):
        drafts.cancel(identity(data['reemplaza']))
    return jsonify(respuesta='Revisa los datos y confirma con Realizar.', consultas=[],
                   agente=plan['recurso'] if plan['recurso'] in ('categorias_carta', 'menajes', 'presentaciones') else 'carta_recetas',
                   borrador={'id_borrador': drafts.save(plan), 'vista': view, **plan})


@asistente_ia_bp.post('/continuar')
@secured
def continuar(session):
    data = body()
    limit()
    result = communication.resume(session, data.get('continuacion'), identity(data.get('id_borrador')))
    return finish_result(session, result)


@asistente_ia_bp.post('/realizar')
@secured
def realizar(session):
    data = body()
    if data.get('confirmar') is not True:
        raise AssistantError('Revisa el borrador y confirma con Realizar.')
    return jsonify(drafts.perform(session, identity(data.get('id'))))


@asistente_ia_bp.post('/cancelar')
@secured
def cancelar(session):
    drafts.cancel(identity(body().get('id')))
    return jsonify(mensaje='Borrador cancelado.')


@asistente_ia_bp.post('/transcribir')
@secured
def transcribir(session):
    if not any(tools.allowed(session, r) for r in tools.RESOURCES):
        raise AssistantError('Tu perfil no tiene acceso al asistente.', 403)
    if request.content_length and request.content_length > 16 * 1024 * 1024:
        raise AssistantError('El audio supera 15 MB.', 413)
    limit()
    upload = request.files.get('audio')
    if upload is None: raise AssistantError('Adjunta una grabación.')
    content = upload.stream.read(15 * 1024 * 1024 + 1)
    db.session.rollback()
    return jsonify(texto=provider.transcribe(content, upload.mimetype))
