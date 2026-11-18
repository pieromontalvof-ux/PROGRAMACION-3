from pathlib import Path

from app.multiagente.agents.carta_recetas import agent as catalog_agent
from app.multiagente.agents.inventario import agent as inventory_agent
from app.multiagente.agents.compras import agent as purchase_agent
from app.multiagente.agents.eventos import agent as event_agent
from app.multiagente.agents.recepcion import agent as reception_agent
from app.multiagente.agents.demanda import agent as demand_agent
from app.multiagente.agents.actualizador_skills import agent as skill_updater
from app.multiagente.agents.configuracion import agent as skill_validator
from app.multiagente.agents.orchestrator.router import (CATALOG_HINTS, INVENTORY_HINTS, PURCHASE_HINTS,
                                            EVENT_HINTS, RECEPTION_HINTS, SPECIALIST_HINTS, DEMAND_HINTS)
from app.multiagente.agents.catalog_specialists import SPECIALISTS


def _skills(paths, labels):
    return [
        {'nombre': label, 'archivo': Path(path).parent.name + '/' + Path(path).name,
         'contenido': Path(path).read_text(encoding='utf-8')}
        for path, label in zip(paths, labels)
    ]


def catalog():
    identities = ['carta_recetas', 'inventario', 'compras', 'eventos', 'recepcion', 'demanda', *SPECIALISTS]
    owners = {resource: 'carta_recetas' for resource in catalog_agent.RESOURCES}
    owners.update({resource: 'inventario' for resource in inventory_agent.RESOURCES})
    owners.update({resource: 'demanda' for resource in demand_agent.RESOURCES})
    owners.update({specialist.resource: specialist.identity for specialist in SPECIALISTS.values()})
    connections = [
        {'origen': 'orquestador', 'destino': identity, 'tipo': 'coordinacion'}
        for identity in identities
    ]
    connections.extend(
        {'origen': specialist.identity, 'destino': owner, 'tipo': 'dependencia'}
        for specialist in SPECIALISTS.values()
        for owner in dict.fromkeys(owners[resource] for resource in (*specialist.dependencies, *specialist.read_resources) if resource in owners)
        if owner != specialist.identity
    )
    connections.append({'origen': 'compras', 'destino': 'demanda', 'tipo': 'dependencia'})
    connections.append({'origen': 'compras', 'destino': 'eventos', 'tipo': 'dependencia'})
    connections.append({'origen': 'compras', 'destino': 'inventario', 'tipo': 'dependencia'})
    return {
        'conexiones': connections,
        'coordinador': {
            'id': 'orquestador',
            'nombre': 'Coordinador',
            'descripcion': 'Guía pedidos por eventos, análisis opcionales y porcentaje elegido; coordina especialistas y requisitos faltantes. Cada cambio requiere confirmación humana.',
            'relaciones': identities,
            'skills': _skills((Path(__file__).parents[1] / 'api' / 'skills' / 'pedido_guiado' / 'SKILL.md',), ['Pedido guiado']),
            'reglas_ruta': {
                'inventario': list(INVENTORY_HINTS),
                'compras': list(PURCHASE_HINTS),
                'eventos': list(EVENT_HINTS),
                'recepcion': list(RECEPTION_HINTS),
                'demanda': list(DEMAND_HINTS),
                'carta_recetas': list(CATALOG_HINTS),
                **{key: list(value) for key, value in SPECIALIST_HINTS.items()},
            },
        },
        'agentes': [
            {
                'id': 'demanda', 'nombre': 'Demanda y rotación',
                'descripcion': 'Analiza ventas de carta, consumo de todos los insumos y cobertura estimada por local.',
                'relaciones': ['orquestador', 'compras'],
                'herramientas': ['analizar_demanda', 'consultar'],
                'recursos': list(demand_agent.RESOURCES), 'recursos_modificables': [],
                'recursos_solo_consulta': list(demand_agent.RESOURCES),
                'instrucciones': demand_agent.INSTRUCTIONS,
                'skills': _skills(demand_agent.SKILLS, ['Demanda y rotación']),
            },
            {
                'id': 'compras', 'nombre': 'Compras y reposición',
                'descripcion': 'Prepara propuestas de compra, incluidos pedidos semanales, con el margen elegido y los informes de eventos, demanda e inventario recibidos del Coordinador.',
                'relaciones': ['orquestador', 'demanda', 'eventos', 'inventario'],
                'herramientas': ['consultar', 'formulario', 'preparar_cambio', 'analizar_demanda'],
                'recursos': list(purchase_agent.RESOURCES),
                'instrucciones': purchase_agent.INSTRUCTIONS,
                'skills': _skills(purchase_agent.SKILLS, ['Compras y reposición']),
                'recursos_modificables': ['ordenes_compra'],
            },
            {
                'id': 'eventos', 'nombre': 'Eventos cercanos',
                'descripcion': 'Consulta eventos de los próximos siete días con fuentes verificadas; no modifica pedidos ni stock.',
                'relaciones': ['orquestador'], 'herramientas': ['web_search'],
                'recursos': ['eventos_cercanos'], 'recursos_modificables': [],
                'instrucciones': event_agent.INSTRUCTIONS,
                'skills': _skills(event_agent.SKILLS, ['Eventos por restaurante']),
            },
            {
                'id': 'recepcion', 'nombre': 'Recepción',
                'descripcion': 'Compara pendientes con cantidades verificadas por la persona y prepara una recepción para revisión.',
                'relaciones': ['orquestador'], 'herramientas': ['consultar', 'preparar_cambio'],
                'recursos': list(reception_agent.RESOURCES),
                'recursos_modificables': ['recepciones'],
                'recursos_solo_consulta': ['historial_recepciones'],
                'instrucciones': reception_agent.INSTRUCTIONS,
                'skills': _skills(reception_agent.SKILLS, ['Recepción de productos']),
            },
            {
                'id': 'carta_recetas',
                'nombre': 'Catálogos y usuarios',
                'descripcion': 'Gestiona categorías de productos, proveedores, productos y usuarios con los permisos del perfil.',
                'relaciones': ['orquestador'],
                'herramientas': ['consultar', 'abrir_formulario', 'preparar_cambio'],
                'recursos': list(catalog_agent.RESOURCES),
                'instrucciones': catalog_agent.INSTRUCTIONS,
                'skills': _skills(catalog_agent.SKILLS, ['Operaciones de catálogo', 'Crear categoría de productos',
                                                       'Crear proveedor', 'Crear producto']),
            },
            *[{
                'id': specialist.identity, 'nombre': specialist.name,
                'descripcion': specialist.description, 'relaciones': ['orquestador'],
                'herramientas': ['consultar', 'preparar_cambio'] +
                                (['revisar_insumo', 'consultar_inventario'] if 'stock' in specialist.read_resources else []) +
                                (['solicitar_especialista'] if specialist.dependencies else []) +
                                (['abrir_formulario'] if specialist.resource in ('categorias_carta', 'menajes', 'presentaciones') else []) +
                                (['formulario'] if specialist.resource in ('presentaciones', 'subproductos', 'recetas', 'promociones') else []),
                'recursos': list(specialist.resources),
                'recursos_modificables': [specialist.resource],
                'recursos_solo_consulta': list(dict.fromkeys((*specialist.dependencies, *specialist.read_resources))),
                'instrucciones': specialist.instructions,
                'skills': _skills(specialist.skills, [specialist.name]),
            } for specialist in SPECIALISTS.values()],
            {
                'id': 'inventario',
                'nombre': 'Inventario',
                'descripcion': 'Consulta stock, conteos, asignaciones, revisiones, jornadas y ventas; prepara las operaciones habilitadas para el perfil.',
                'relaciones': ['orquestador'],
                'herramientas': ['consultar_inventario', 'preparar_cambio'],
                'recursos': list(inventory_agent.RESOURCES),
                'instrucciones': inventory_agent.INSTRUCTIONS,
                'skills': _skills(inventory_agent.SKILLS, ['Operaciones de inventario']),
            },
        ],
        'administracion': [
            {'id': identity, 'nombre': name, 'descripcion': description,
             'relaciones': [], 'herramientas': [], 'recursos': [], 'recursos_modificables': [],
             'instrucciones': module.SKILL.read_text(encoding='utf-8'),
             'skills': _skills((module.SKILL,), [name])}
            for identity, name, description, module in (
                ('actualizador_skills', 'Actualizador de skills',
                 'Lee la skill y los archivos seleccionados; propone texto editable. No guarda ni concede permisos.', skill_updater),
                ('validador_skills', 'Validador de skills',
                 'Revisa independientemente la propuesta. Indica conflictos, datos y permisos necesarios; no modifica ni concede accesos.', skill_validator),
            )
        ],
        'limite_salon': 'Los pedidos de Salón no están conectados al asistente: usan sesión y autorización PIN separadas.',
        'regla_ejecucion': 'Los agentes solo preparan borradores. El backend revalida perfil y local; una persona debe confirmar para ejecutar.',
    }
