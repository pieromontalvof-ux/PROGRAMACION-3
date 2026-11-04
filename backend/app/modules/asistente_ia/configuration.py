"""Reviewed effective agent configuration; never grants unsupported/native permissions."""
import hashlib
import json
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

from flask import current_app, has_app_context
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from . import drafts, library
from .provider import AssistantError

REVIEW_LIMIT = 120000


def native_accesses(agent_id, agent=None):
    agent = agent or library.identity(agent_id)
    resources = agent.get('recursos', [])
    writes = set(agent.get('recursos_modificables', []))
    if agent_id == 'carta_recetas':
        writes = {'productos', 'categorias_productos', 'proveedores'}
    result = {resource: ['consultar'] + (['crear', 'editar'] if resource in writes else []) for resource in resources}
    if agent_id in ('compras', 'recepcion'):
        for resource in writes:
            result[resource] = ['consultar', 'crear']
    if agent_id == 'inventario':
        result['conteos'] = ['consultar', 'crear']
        result['asignaciones_conteo'] = ['consultar', 'editar']
        result['revision_conteo'] = ['consultar', 'editar']
    return result


def supported(agent_id, agent=None):
    result = native_accesses(agent_id, agent)
    if agent_id not in ('orquestador', 'eventos'):
        from .tools import RESOURCES
        for resource in RESOURCES:
            result.setdefault(resource, ['consultar'])
    return result


def effective(agent_id, state=None):
    agent = library.identity(agent_id)
    state = library.read(agent_id) if state is None else state
    if state.get('configuracion'):
        return deepcopy(state['configuracion'])
    instruction = agent.get('instrucciones') or '\n'.join(skill['contenido'] for skill in agent.get('skills', [])) or agent['descripcion']
    if state.get('instrucciones'):
        instruction += '\n\nCriterios guardados del administrador:\n' + state['instrucciones']
    return {'instrucciones': instruction, 'skills': deepcopy(agent.get('skills', [])), 'accesos': native_accesses(agent_id, agent)}


def validate(agent_id, value):
    if not isinstance(value, dict) or set(value) != {'instrucciones', 'skills', 'accesos'}:
        raise AssistantError('La configuración requiere instrucciones, skills y accesos.')
    instruction = value['instrucciones']
    if not isinstance(instruction, str) or not instruction.strip() or len(instruction) > 30000 or '\x00' in instruction:
        raise AssistantError('Las instrucciones deben contener texto de hasta 30000 caracteres.')
    base = library.identity(agent_id)
    allowed_skills = {skill['archivo']: skill for skill in base.get('skills', [])}
    skills = value['skills']
    if not isinstance(skills, list) or len(skills) != len(allowed_skills):
        raise AssistantError('Conserva las skills registradas del agente; puedes editar su contenido.')
    clean_skills, seen = [], set()
    for skill in skills:
        if not isinstance(skill, dict) or not isinstance(skill.get('archivo'), str) or skill.get('archivo') not in allowed_skills or skill['archivo'] in seen:
            raise AssistantError('Skill desconocida o repetida.')
        content = skill.get('contenido')
        if not isinstance(content, str) or not content.strip() or len(content) > 30000 or '\x00' in content:
            raise AssistantError('Cada skill debe contener texto de hasta 30000 caracteres.')
        seen.add(skill['archivo'])
        clean_skills.append({**allowed_skills[skill['archivo']], 'contenido': content.strip()})
    accesses, ceiling = value['accesos'], supported(agent_id, base)
    if not isinstance(accesses, dict) or not set(accesses).issubset(ceiling):
        raise AssistantError('Conexión no disponible. El recurso necesita una integración antes de poder asignarse.')
    for resource, actions in accesses.items():
        if not isinstance(actions, list) or any(not isinstance(action, str) for action in actions) or len(actions) != len(set(actions)) or any(action not in ceiling[resource] for action in actions):
            raise AssistantError('Acceso no soportado para ' + resource + '.')
        if any(action != 'consultar' for action in actions) and 'consultar' not in actions:
            raise AssistantError('Para preparar cambios en ' + resource + ', habilita también su consulta.')
    return {'instrucciones': instruction.strip(), 'skills': clean_skills,
            'accesos': {resource: sorted(actions) for resource, actions in accesses.items()}}


def digest(config, state):
    content = {'configuracion': config, 'revision': state['revision'], 'documentos': state['documentos']}
    return hashlib.sha256(json.dumps(content, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def signer():
    key = current_app.config.get('SECRET_KEY') or current_app.config.get('JWT_SECRET_KEY')
    if not key:
        raise AssistantError('Falta configurar la firma de revisiones.', 503)
    return URLSafeTimedSerializer(key, salt='agent-configuration-review-v1')


def review(agent_id, proposal, revision, purpose='configuracion'):
    config = validate(agent_id, proposal)
    state = library.read(agent_id)
    library.check_revision(state, revision)
    length = len(config['instrucciones']) + sum(len(skill['contenido']) for skill in config['skills']) + sum(len(doc['contenido']) for doc in state['documentos'])
    if length > REVIEW_LIMIT:
        raise AssistantError(f'La revisión completa admite {REVIEW_LIMIT} caracteres entre instrucciones, skills y documentos; la propuesta tiene {length}. Reduce o divide las referencias antes de revisar.', 413)
    agent = library.identity(agent_id)
    from app.agents.configuracion.agent import review as inspect
    report = inspect({'agente': {'id': agent_id, 'nombre': agent['nombre'], 'descripcion': agent['descripcion'], 'relaciones': agent.get('relaciones', [])},
                      'configuracion_propuesta': config, 'accesos_soportados': supported(agent_id, agent),
                      'otros_especialistas': [{'id': item['id'], 'nombre': item['nombre'], 'recursos': item.get('recursos', [])} for item in library.agents()],
                      'documentos': state['documentos'], 'limite_lectura_operativa': library.CONTEXT_LIMIT})
    approval = signer().dumps({'agente': agent_id, 'scope': drafts.scope(), 'digest': digest(config, state), 'proposito': purpose,
                               'revision': revision, 'informe': report})
    return {'revision_ia': approval, 'informe': report, 'documentos_revisados': len(state['documentos']),
            'caracteres_revisados': length, 'revision': revision, 'puede_guardar': can_save(report)}


def apply(agent_id, proposal, revision, approval, purpose='configuracion'):
    config = validate(agent_id, proposal)
    if not isinstance(approval, str) or len(approval) > 40000:
        raise AssistantError('Primero revisa esta configuración con el Revisor de configuración.', 409)
    try:
        checked = signer().loads(approval, max_age=900)
    except (BadSignature, SignatureExpired):
        raise AssistantError('La revisión venció o cambió. Revisa nuevamente antes de aplicar.', 409) from None
    if checked['scope'] != drafts.scope() or checked['agente'] != agent_id:
        raise AssistantError('La revisión pertenece a otra sesión o agente.', 403)
    if checked.get('proposito', 'configuracion') != purpose:
        raise AssistantError('La validación no corresponde a esta operación.', 409)
    if purpose == 'skills' and not can_save(checked['informe']):
        raise AssistantError('Resuelve la información, permisos o conflictos señalados y vuelve a validar antes de guardar.', 409)
    with library.mutation(agent_id):
        state = library.read(agent_id)
        library.check_revision(state, revision)
        if checked['revision'] != revision or checked['digest'] != digest(config, state):
            raise AssistantError('La propuesta o sus documentos cambiaron después de la revisión. Revisa nuevamente.', 409)
        state['configuracion'] = config
        state['documentos_activos'] = [doc['id'] for doc in state['documentos']]
        state['revision'] += 1
        state['ultima_revision'] = {'informe': checked['informe'], 'aplicado_por': drafts.scope()['usuario'],
                                   'fecha': datetime.now(timezone.utc).isoformat()}
        library.save(agent_id, state)
        return library.view(agent_id, state)


def can_save(report):
    return not any(report[key] for key in ('conflictos', 'informacion_faltante', 'accesos_necesarios'))


def skill_proposal(agent_id, skills):
    config = effective(agent_id)
    # The coordinator used to duplicate the same source as instructions and skill.
    base = library.identity(agent_id)
    if agent_id == 'orquestador' and config['instrucciones'].strip() == '\n'.join(skill['contenido'] for skill in base.get('skills', [])).strip():
        config['instrucciones'] = base['descripcion']
    config['skills'] = skills
    return validate(agent_id, config)


def review_skills(agent_id, skills, revision):
    return review(agent_id, skill_proposal(agent_id, skills), revision, purpose='skills')


def save_skills(agent_id, skills, revision, approval):
    return apply(agent_id, skill_proposal(agent_id, skills), revision, approval, purpose='skills')


def update_skill(agent_id, skills, skill_file, documents, revision):
    config = skill_proposal(agent_id, skills)
    state = library.read(agent_id)
    library.check_revision(state, revision)
    skill = next((skill for skill in config['skills'] if skill['archivo'] == skill_file), None)
    if skill is None:
        raise AssistantError('Selecciona una skill registrada.')
    if not isinstance(documents, list) or not documents or any(not isinstance(doc, str) for doc in documents) or len(set(documents)) != len(documents):
        raise AssistantError('Selecciona al menos un archivo, sin duplicados.')
    sources = [doc for doc in state['documentos'] if doc['id'] in documents]
    if len(sources) != len(documents):
        raise AssistantError('Uno de los archivos ya no existe. Recarga la carpeta.', 409)
    if len(skill['contenido']) + sum(len(doc['contenido']) for doc in sources) > REVIEW_LIMIT:
        raise AssistantError('La skill y las referencias superan el límite de lectura. Selecciona menos archivos.', 413)
    from app.agents.actualizador_skills.agent import update
    result = update({'agente': library.identity(agent_id)['nombre'], 'skill_actual': skill, 'documentos': sources})
    # A concurrent upload/delete/config change must never silently produce a stale proposal.
    if library.read(agent_id)['revision'] != revision:
        raise AssistantError('Los archivos o la configuración cambiaron durante el análisis. Vuelve a actualizar la skill.', 409)
    return {**result, 'archivo_skill': skill_file, 'fuentes': [doc['nombre'] for doc in sources], 'revision': revision}


def save_accesses(agent_id, accesses, revision):
    with library.mutation(agent_id):
        state = library.read(agent_id)
        library.check_revision(state, revision)
        config = effective(agent_id, state)
        config['accesos'] = accesses
        checked = validate(agent_id, config)
        config['accesos'] = checked['accesos']
        state['configuracion'] = config
        state['revision'] += 1
        state['ultimo_cambio_permisos'] = {'por': drafts.scope()['usuario'], 'fecha': datetime.now(timezone.utc).isoformat()}
        library.save(agent_id, state)
        return library.view(agent_id, state)


def agent_for_skills(skills):
    if not skills:
        return None
    key = Path(skills[0]).parent.name
    return {'operaciones_catalogo': 'carta_recetas', 'compras_eventos': 'eventos'}.get(key, key)


def saved(agent_id):
    if not has_app_context() or agent_id is None:
        return None
    return library.read(agent_id).get('configuracion')


def allows(agent_id, resource, action='consultar'):
    config = saved(agent_id)
    return config is None or action in config['accesos'].get(resource, [])


def authorize(agent_id, resource, action='consultar'):
    if not allows(agent_id, resource, action):
        raise AssistantError('El acceso a ' + resource + ' está deshabilitado en la configuración de este agente.', 403)


def owner(resource):
    from app.agents.catalog_specialists import SPECIALISTS
    from . import inventory, purchases, receptions
    if resource in SPECIALISTS:
        return resource
    elif resource in ('productos', 'categorias_productos', 'proveedores'):
        return 'carta_recetas'
    elif resource in inventory.RESOURCES:
        return 'inventario'
    elif resource in purchases.RESOURCES:
        return 'compras'
    elif resource in receptions.RESOURCES:
        return 'recepcion'
    return None


def authorize_owner(resource, action='consultar'):
    agent_id = owner(resource)
    if agent_id:
        authorize(agent_id, resource, 'consultar')
        authorize(agent_id, resource, action)


def owner_allows(resource, action='consultar'):
    try:
        authorize_owner(resource, action)
        return True
    except AssistantError as error:
        if error.status != 403:
            raise
        return False


def form_dependencies(resource):
    return {'productos': ('categorias_productos', 'proveedores'), 'proveedores': ('categorias_productos',),
            'presentaciones': ('categorias_carta', 'menajes'), 'subproductos': ('productos',),
            'recetas': ('productos', 'subproductos', 'presentaciones'), 'promociones': ('presentaciones',)}.get(resource, ())


def authorize_form_dependencies(session, resource, agent_id=None):
    from . import tools
    agent_id = agent_id or owner(resource)
    for dependency in form_dependencies(resource):
        if agent_id:
            authorize(agent_id, dependency)
        tools.authorize(session, dependency)


def decorate(manifest):
    for agent in [manifest['coordinador'], *manifest['agentes']]:
        config = effective(agent['id'])
        agent['instrucciones'] = config['instrucciones']
        agent['skills'] = config['skills']
        agent['accesos'] = config['accesos']
        if agent['id'] != 'orquestador':
            agent['recursos'] = [resource for resource, actions in config['accesos'].items() if actions]
            agent['recursos_modificables'] = [resource for resource, actions in config['accesos'].items() if any(action != 'consultar' for action in actions)]
    return manifest
