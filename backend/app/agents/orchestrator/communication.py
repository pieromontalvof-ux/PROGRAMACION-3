"""Scoped, signed continuations for specialist handoffs; never executes writes."""
import json
from contextvars import ContextVar
from uuid import uuid4

from flask import current_app
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired

from app.core.extensions import db
from app.agents import activity
from app.agents.catalog_specialists import SPECIALISTS
from app.modules.asistente_ia import drafts, forms, tools
from app.modules.asistente_ia.provider import AssistantError

_requirement = ContextVar('pending_agent_requirement', default=None)


def current_requirement():
    return _requirement.get()


def serializer():
    secret = current_app.config.get('SECRET_KEY') or current_app.config.get('JWT_SECRET_KEY')
    if not secret:
        raise AssistantError('Falta configurar la firma de tareas del asistente.', 503)
    return URLSafeTimedSerializer(secret, salt='assistant-handoffs-v1')


def load(token):
    if not isinstance(token, str) or len(token) > 80000:
        raise AssistantError('Continuación inválida.', 400)
    try:
        state = serializer().loads(token, max_age=7200)
    except (BadSignature, SignatureExpired):
        raise AssistantError('La tarea pendiente venció o cambió. Inicia una nueva consulta.', 409) from None
    if state['scope'] != drafts.scope():
        raise AssistantError('La tarea pendiente pertenece a otro perfil o local.', 403)
    return state


def owner(resource):
    return resource if resource in SPECIALISTS else 'carta_recetas'


def conversation(frame, client_history=None):
    """Keep task facts, user corrections and verified writes distinguishable."""
    return {
        'tarea_original': frame['instruccion'],
        'contexto_original': frame['contexto'],
        'aclaraciones': frame.get('aclaraciones', []),
        'aclaraciones_requisitos': frame.get('aclaraciones_requisitos', []),
        'borrador_actual': frame.get('borrador_actual', frame.get('previo', '')),
        'historial_cliente': client_history if client_history is not None else frame.get('historial_cliente', ''),
        'resultados_confirmados': frame.get('resultados_confirmados', []),
        'revisiones_insumos': frame.get('revisiones_insumos', []),
        'preparacion': frame.get('preparacion'),
    }


def remember_reviews(frame, result):
    if result.get('_preparacion'):
        frame['preparacion'] = result.pop('_preparacion')
    for report in result.get('consultas', []):
        if report.get('estado_catalogo'):
            name = tools.normalized(report['busqueda'])
            reviews = [r for r in frame.get('revisiones_insumos', []) if tools.normalized(r['busqueda']) != name]
            frame['revisiones_insumos'] = [*reviews, report][-8:]


def return_clarifications(parent, child):
    """User decisions made during a prerequisite also belong to its parent."""
    clarifications = child.get('aclaraciones', [])
    if clarifications:
        turns = parent.setdefault('aclaraciones', [])
        for turn in clarifications:
            if not turns or turns[-1] != turn:
                turns.append(turn)
        parent['aclaraciones'] = turns[-8:]
    requirements = [*parent.get('aclaraciones_requisitos', []), *child.get('aclaraciones_requisitos', [])]
    if clarifications:
        requirements.append({'recurso': child.get('recurso'), 'aclaraciones': clarifications})
    if requirements:
        parent['aclaraciones_requisitos'] = requirements[-8:]
    remember_reviews(parent, {'consultas': child.get('revisiones_insumos', [])})
    if child.get('preparacion'):
        parent['preparacion'] = child['preparacion']


def invoke(session, frame, instruction=None, previous=None, context=None):
    task = instruction if instruction is not None else frame['instruccion']
    prior = previous if previous is not None else frame.get('borrador_actual', frame['previo'])
    # Browser history is editable and may contain only a success message. It
    # must never replace the original task or server-verified creation results.
    history = json.dumps(conversation(frame, context), ensure_ascii=False, default=str)
    selected = frame['agente']
    token = _requirement.set(frame.get('recurso'))
    try:
        if selected in SPECIALISTS:
            tools.authorize(session, SPECIALISTS[selected].resource)
            result = SPECIALISTS[selected].run(session, task, prior, history)
        elif selected == 'carta_recetas':
            from app.agents.carta_recetas.agent import run
            result = run(session, task, prior, history)
        else:
            raise AssistantError('Especialista no disponible para retomar esta tarea.', 400)
    finally:
        _requirement.reset(token)
    result['agente'] = selected
    return result


def coordinate(session, result, instruction, previous='', context='', state=None, *, record_turn=True, objective=None):
    if state is None:
        state = {'scope': drafts.scope(), 'paso': str(uuid4()), 'pila': [], 'mensajes': [],
                 'conversacion': forms.prefers_chat(),
                 'actual': {'agente': result.get('agente'), 'instruccion': instruction,
                            'previo': previous, 'contexto': context}}
        if state['conversacion']:
            target = objective or forms.detect(instruction)
            if target in ('productos', 'proveedores', 'categorias_productos', 'categorias_carta', 'menajes', 'presentaciones') and owner(target) == result.get('agente'):
                # Seal the original task before the first clarification turn.
                state['actual']['recurso_objetivo'] = target
    elif record_turn:
        frame = state['actual']
        if instruction != frame['instruccion']:
            clarifications = frame.setdefault('aclaraciones', [])
            if not clarifications or clarifications[-1] != instruction:
                clarifications.append(instruction)
            # Retain recent conversation separately from authoritative results.
            frame['aclaraciones'] = clarifications[-8:]
        frame['borrador_actual'] = previous
        frame['historial_cliente'] = context[-16000:]
    transitions = 0
    while result.get('traspaso') or result.get('seleccion_existente'):
        remember_reviews(state['actual'], result)
        transitions += 1
        if transitions > 12:
            raise AssistantError('Se detuvo una secuencia repetida de requisitos. No se han creado registros en este paso.', 422)
        if result.get('seleccion_existente'):
            selection = result.pop('seleccion_existente')
            resource, identity = selection.get('recurso'), selection.get('id')
            if not state['pila'] or resource != state['actual'].get('recurso') or type(identity) is not int or identity <= 0:
                raise AssistantError('La referencia no corresponde al requisito pendiente.', 409)
            from app.modules.asistente_ia import configuration
            configuration.authorize_owner(resource)
            tools.authorize(session, resource)
            record = tools.current_record(session, resource, identity)
            if not record or record.get('activo') is False or record.get('estado_registro', 1) != 1:
                raise AssistantError('La referencia elegida no existe o está inactiva.', 409)
            parent = state['pila'].pop()
            return_clarifications(parent, state['actual'])
            message = {'de': state['actual']['agente'], 'a': parent['agente'],
                       'motivo': 'Referencia existente verificada; se retoma la tarea sin crear un duplicado.'}
            state['mensajes'].append(message)
            activity.emit('mensaje_entre_agentes', de=message['de'], a=message['a'], mensaje=message['motivo'])
            parent.setdefault('resultados_confirmados', []).append({'recurso': resource,
                'resultado': {'seleccion': 'EXISTENTE', 'id': identity, 'registro': record}})
            state['actual'] = parent
            state['paso'] = str(uuid4())
            result = invoke(session, parent)
            continue
        handoff = result.pop('traspaso')
        current = state['actual']
        specialist = SPECIALISTS.get(current['agente'])
        resource = handoff['recurso']
        if specialist is None or resource not in specialist.dependencies:
            raise AssistantError('El Coordinador rechazó una dependencia ajena a la tarea.', 403)
        if len(state['pila']) >= 6 or owner(resource) in [f['agente'] for f in [*state['pila'], current]]:
            raise AssistantError('Se detuvo un traspaso circular. Revisa los requisitos de la tarea.', 422)
        tools.authorize(session, resource)
        tools.authorize(session, resource, 'crear')
        state['pila'].append(current)
        state['mensajes'].append({'de': current['agente'], 'a': owner(resource),
                                  'motivo': handoff['motivo']})
        activity.emit('mensaje_entre_agentes', de=current['agente'], a=owner(resource),
                      mensaje=handoff['motivo'], instruccion=handoff['instruccion'])
        state['paso'] = str(uuid4())
        state['actual'] = {'agente': owner(resource), 'recurso': resource,
                           'instruccion': handoff['instruccion'], 'previo': '',
                           'contexto': json.dumps({**conversation(current),
                                                  'requisito': handoff}, ensure_ascii=False, default=str)}
        if resource in forms.TITLES and not state.get('conversacion', False):
            result = {'respuesta': 'Completa este requisito; después retomaremos la tarea pendiente.',
                      'formulario': forms.open_form(session, resource), 'plan': None,
                      'consultas': [], 'agente': owner(resource)}
        else:
            result = invoke(session, state['actual'])
    # A catalog specialist owns products, suppliers and product categories. It
    # may prepare a prerequisite itself, but must retain the parent task too.
    plan = result.get('plan')
    current = state['actual']
    remember_reviews(current, result)
    if state.get('conversacion') and current['agente'] == 'carta_recetas' and plan and plan['accion'] == 'crear':
        target = current.get('recurso') or current.get('recurso_objetivo') or forms.detect(current['instruccion'])
        dependencies = {'productos': ('proveedores', 'categorias_productos'), 'proveedores': ('categorias_productos',)}
        if plan['recurso'] in dependencies.get(target, ()):
            if len(state['pila']) >= 6:
                raise AssistantError('Hay demasiados requisitos pendientes. Revisa la tarea antes de continuar.', 422)
            state['pila'].append(current)
            state['paso'] = str(uuid4())
            message = 'Se revisa primero el requisito del catálogo; después se retomará la solicitud original.'
            state['mensajes'].append({'de': 'carta_recetas', 'a': 'carta_recetas', 'motivo': message})
            activity.emit('paso_requisito', mensaje=message, recurso=plan['recurso'])
            state['actual'] = {'agente': 'carta_recetas', 'recurso': plan['recurso'],
                'instruccion': forms.TITLES[plan['recurso']] + '. Requisito de: ' + current['instruccion'],
                'previo': '', 'contexto': json.dumps({'tarea_original': current['instruccion'],
                    'datos_propuestos': plan['datos']}, ensure_ascii=False)}
    if state['pila'] or state['actual'].get('resultados_confirmados') or state['actual'].get('aclaraciones') or state['actual'].get('recurso_objetivo') or state['actual'].get('revisiones_insumos') or state['actual'].get('preparacion'):
        result['continuacion'] = serializer().dumps(state)
        result['comunicaciones'] = state['mensajes'][-12:]
        if state['pila']:
            result['tarea_pendiente'] = state['pila'][-1]['instruccion']
        if state['pila'] and result.get('plan'):
            bind_plan(state, result['plan'])
    elif state['mensajes']:
        result['comunicaciones'] = state['mensajes'][-12:]
    return result


def bind_plan(state, plan):
    if not state['pila']:
        return  # Final parent: its own draft needs no return to another agent.
    if plan['recurso'] != state['actual']['recurso'] or plan['accion'] != 'crear':
        raise AssistantError('La propuesta no corresponde al requisito pendiente.', 409)
    plan['_coordinacion'] = state['paso']


def resume(session, token, draft_id):
    state = load(token)
    if not state['pila']:
        raise AssistantError('No hay una tarea pendiente.', 409)
    row = drafts.load(draft_id)
    if row['estado'] != 'REALIZADO':
        raise AssistantError('Primero confirma y realiza el requisito pendiente.', 409)
    plan = row['plan']
    if (plan.get('_coordinacion') != state['paso'] or
            plan['recurso'] != state['actual']['recurso'] or plan['accion'] != 'crear'):
        raise AssistantError('Este resultado no pertenece al requisito pendiente.', 409)
    result_data = row['resultado']
    db.session.rollback()
    parent = state['pila'].pop()
    return_clarifications(parent, state['actual'])
    activity.emit('mensaje_entre_agentes', de=state['actual']['agente'], a=parent['agente'],
                  mensaje='Requisito confirmado. Se retoma la tarea pendiente.')
    state['mensajes'].append({'de': state['actual']['agente'], 'a': parent['agente'],
                              'motivo': 'Requisito confirmado. Se retoma la tarea pendiente.'})
    parent.setdefault('resultados_confirmados', []).append({
        'recurso': plan['recurso'], 'datos': plan['datos'], 'resultado': result_data,
    })
    state['actual'] = parent
    state['paso'] = str(uuid4())
    result = invoke(session, parent)
    return coordinate(session, result, parent['instruccion'], parent['previo'], parent['contexto'],
                      state, record_turn=False)
