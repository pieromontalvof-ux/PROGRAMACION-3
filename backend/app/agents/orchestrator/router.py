import re

from app.modules.asistente_ia import inventory, tools
from app.modules.asistente_ia.provider import AssistantError
from app.agents.catalog_specialists import SPECIALISTS
from app.agents.orchestrator import recipe_answers

INVENTORY_HINTS = (
    'inventario', 'stock', 'existencia', 'existencias', 'conteo', 'conteos',
    'asignar puesto', 'asignacion', 'asignaciones', 'puesto', 'diferencia',
    'diferencias', 'jornada', 'jornadas', 'mix de ventas', 'ventas', 'vendido',
    'faltante', 'merma', 'revision de conteo', 'bajo minimo', 'minimo de stock',
)
CATALOG_HINTS = (
    'catalogo', 'promocion', 'promociones', 'promo', 'promos', 'receta',
    'recetas', 'carta', 'presentacion', 'presentaciones', 'proveedor',
    'proveedores', 'categoria', 'categorias', 'subproducto', 'menaje',
    'crear producto', 'crear un producto', 'crea producto', 'crea un producto',
    'agregar producto', 'agregar un producto', 'agrega producto', 'agrega un producto',
    'editar producto', 'editar un producto', 'modificar producto', 'modifica el producto',
    'producto de carta', 'precio de venta',
)
PURCHASE_HINTS = ('compra', 'pedido sugerido')
EVENT_HINTS = ('evento', 'concierto', 'festividad', 'festividades', 'feriado')
RECEPTION_HINTS = ('recepcion', 'recibir', 'recibido', 'recibi', 'entrega parcial',
                   'entrega del proveedor', 'llego el pedido', 'llegaron los productos')
DEMAND_HINTS = ('rotacion', 'demanda', 'mas salida', 'mayor salida', 'mas vendido',
                'mas se vende', 'se vende mas', 'mas rapido', 'rapido se acaba', 'rapidez',
                'cuanto durara', 'cuanto dura el stock', 'cobertura', 'aceptacion', 'recibimiento',
                'analiza las ventas', 'analiza ventas', 'analisis de ventas', 'se esta quedando',
                'que tanto salio', 'se acaba', 'se agota', 'velocidad de venta')

SPECIALIST_HINTS = {
    'categorias_carta': ('categoria de carta', 'categorias de carta', 'categoria carta', 'categorias carta'),
    'menajes': ('menaje', 'menajes'),
    'presentaciones': ('presentacion', 'presentaciones', 'precio de venta', 'articulo de carta', 'producto de carta'),
    'subproductos': ('subproducto', 'subproductos'),
    'recetas': ('receta', 'recetas'),
    'promociones': ('promocion', 'promociones', 'promo', 'promos'),
}


def catalog_route(instruction):
    value = tools.normalized(instruction)
    # Natural wording with an article identifies the same menu resource.
    value = re.sub(r'\b(producto|articulo)\s+de\s+la\s+carta\b', r'\1 de carta', value)
    value = re.sub(r'\b(crear|crea|agregar|agrega|editar|edita|modificar|modifica)(un|una|el|la)\b', r'\1 \2', value)
    # El objeto de la acción prevalece sobre sus dependencias mencionadas.
    action = r'\b(?:crea|crear|agrega|agregar|edita|editar|modifica|modificar|actualiza|actualizar)\s+(?:(?:un|una|el|la|los|las|nuevo|nueva)\s+)*'
    for identity, hints in SPECIALIST_HINTS.items():
        for hint in hints:
            if re.search(action + re.escape(hint) + r'\b', value):
                return identity
    for identity in ('promociones', 'recetas', 'subproductos', 'presentaciones', 'menajes', 'categorias_carta'):
        if any(re.search(r'\b' + re.escape(hint) + r'\b', value) for hint in SPECIALIST_HINTS[identity]):
            return identity
    return None


def _score(value, hints):
    normalized = tools.normalized(value)
    return sum(normalized.count(tools.normalized(hint)) for hint in hints)


def explicit_catalog_task(instruction):
    creation = re.search(r'\b(?:crear|crea|registrar|registra|agregar|agrega|editar|edita)\s+'
                         r'(?:(?:un|una|el|la|nuevo|nueva)\s+)*'
                         r'(recetas?|presentaci(?:on|ones)|subproductos?)\b', tools.normalized(instruction))
    if creation:
        entity = creation[1]
        return 'recetas' if entity.startswith('receta') else 'subproductos' if entity.startswith('subproducto') else 'presentaciones'
    return None


def route(instruction, previous=''):
    if recipe_answers.detect(instruction) is not None:
        return 'recetas'
    explicit = (_score(instruction, CATALOG_HINTS) or _score(instruction, INVENTORY_HINTS)
                or _score(instruction, PURCHASE_HINTS) or _score(instruction, EVENT_HINTS)
                or _score(instruction, RECEPTION_HINTS) or _score(instruction, DEMAND_HINTS)
                or re.search(r'\bpedidos?\b', tools.normalized(instruction)))
    request = instruction if explicit else f'{instruction} {previous}'
    normalized = tools.normalized(request)
    # Stock and possible purchasing are checks within an explicit recipe/menu
    # creation task, rather than a reason to abandon it for another workflow.
    creation = explicit_catalog_task(instruction)
    if creation:
        return creation
    # In management, an unspecified pedido refers to purchasing supplies.
    # Explicit table/service orders belong to the separate Salon workflow.
    if re.search(r'\bpedidos?\b', normalized) and re.search(r'\b(salon|mesa|comanda|mesero)\b', normalized):
        return 'salon'
    if _score(request, RECEPTION_HINTS) and not re.search(r'\brecibimiento\b', normalized):
        return 'recepcion'
    purchase_request = _score(request, PURCHASE_HINTS) or re.search(r'\bpedidos?\b', normalized)
    event_query = re.search(
        r'\b(busca|buscar|consulta|consultar|reintenta|reintentar|muestra|ver|que|hay)\b'
        r'(?:\s+\w+){0,4}\s+(eventos?|conciertos?|festividades|feriados?)\b', normalized)
    skip_events = re.search(
        r'\b(sin|no)\s+(?:(?:quiero|deseo|necesito|consultar|buscar|revisar|consultes|busques|revises|los|las)\s+)*'
        r'(eventos?|conciertos?|festividades|feriados?)\b', normalized)
    if _score(request, EVENT_HINTS) and not skip_events and (not purchase_request or event_query):
        return 'eventos'
    if purchase_request:
        return 'compras'
    if _score(request, DEMAND_HINTS):
        return 'demanda'
    inventory_score = _score(request, INVENTORY_HINTS)
    catalog_score = _score(request, CATALOG_HINTS)
    if skip_events and not inventory_score and not catalog_score:
        return 'orquestador'
    if inventory_score and catalog_score:
        return 'orquestador'
    if inventory_score > catalog_score:
        return 'inventario'
    return catalog_route(instruction) or ('carta_recetas' if explicit else catalog_route(previous) or 'carta_recetas')


def run(session, instruction, previous='', context=''):
    recipe_answer = recipe_answers.handle(session, instruction)
    if recipe_answer is not None:
        return recipe_answer
    selected = route(instruction, previous)
    # Shortages are ambiguous during reception. Explicit stock/count requests still switch.
    if selected == 'inventario' and context and route(context) == 'recepcion':
        strong_inventory = tuple(hint for hint in INVENTORY_HINTS
                                 if hint not in ('faltante', 'merma', 'diferencia', 'diferencias'))
        if not _score(instruction, strong_inventory):
            selected = 'recepcion'
    if selected == 'carta_recetas' and not _score(instruction, CATALOG_HINTS) and context:
        contextual = route(context)
        if contextual in ('compras', 'recepcion', 'eventos', 'inventario', 'demanda'):
            selected = contextual
    if selected == 'salon':
        return {'respuesta': 'Los pedidos de mesa se registran desde Salón. Si deseas comprar insumos, indica «hacer un pedido de compra».',
                'consultas': [], 'plan': None, 'agente': 'orquestador'}
    if selected == 'carta_recetas' and not _score(instruction, CATALOG_HINTS) and context and route(context) == 'compras':
        selected = 'compras'
    if selected == 'carta_recetas' and not _score(instruction, CATALOG_HINTS) and context:
        selected = catalog_route(context) or selected
    if selected == 'demanda':
        from app.agents.demanda.agent import run as specialist
        result = specialist(session, instruction, previous, context)
        result['agente'] = selected
        return result
    if selected == 'compras':
        from app.agents.compras.agent import run as specialist
        result = specialist(session, instruction, previous, context)
        result['agente'] = selected
        return result
    if selected in ('eventos', 'recepcion'):
        if selected == 'eventos':
            from app.agents.eventos.agent import run as specialist
        else:
            from app.agents.recepcion.agent import run as specialist
        result = specialist(session, instruction, previous, context)
        result['agente'] = selected
        return result
    if selected == 'orquestador':
        if _score(instruction, EVENT_HINTS):
            return {'respuesta': 'No se consultarán eventos. Puedes pedir la base de compras o consultar inventario y recepción.',
                    'consultas': [], 'plan': None, 'agente': selected}
        return {'respuesta': 'El pedido combina inventario y catálogo. Indica cuál de esas tareas quieres preparar primero.',
                'consultas': [], 'plan': None, 'agente': selected}

    if selected in SPECIALISTS:
        specialist = SPECIALISTS[selected]
        if not tools.allowed(session, specialist.resource):
            raise AssistantError('Tu perfil no tiene acceso a ' + specialist.name + '.', 403)
        result = specialist.run(session, instruction, previous, context)
        result['agente'] = selected
        return result

    available_catalog = any(tools.allowed(session, resource) for resource in tools.RESOURCES
                            if resource not in inventory.RESOURCES)
    available_inventory = any(tools.allowed(session, resource) for resource in inventory.RESOURCES)
    if selected == 'inventario' and not available_inventory:
        raise AssistantError('Tu perfil no tiene acceso a las acciones de inventario del asistente.', 403)
    if selected == 'carta_recetas' and not available_catalog:
        if available_inventory:
            selected = 'inventario'
        else:
            raise AssistantError('Tu perfil no tiene acceso a los agentes del asistente.', 403)

    if selected == 'inventario':
        from app.agents.inventario.agent import run as specialist
    else:
        from app.agents.carta_recetas.agent import run as specialist
    result = specialist(session, instruction, previous, context)
    result['agente'] = selected
    return result
