"""Especialistas independientes con dependencias de solo lectura."""
from dataclasses import dataclass
from pathlib import Path

from app.agents.runtime import run_specialist
from app.agents import activity
from app.modules.asistente_ia.agent import INSTRUCTIONS


@dataclass(frozen=True)
class Specialist:
    identity: str
    name: str
    resource: str
    dependencies: tuple[str, ...]
    description: str
    read_resources: tuple[str, ...] = ()

    @property
    def resources(self):
        return tuple(dict.fromkeys((self.resource, *self.dependencies, *self.read_resources)))

    @property
    def skills(self):
        return (Path(__file__).parents[1] / 'modules' / 'asistente_ia' / 'skills' / self.identity / 'SKILL.md',)

    @property
    def instructions(self):
        return INSTRUCTIONS + f'\nEres el especialista de {self.name}. Solo preparas cambios de {self.resource}. ' + (
            'Los demás recursos son exclusivamente de consulta para comprobar requisitos. '
            'Antes de crear un requisito, revisa alternativas reales y resuelve la decisión inmediata con el usuario. '
            'Cuando esa elección esté resuelta y el usuario desee crearlo, usa solicitar_especialista para delegarlo al Coordinador. Nunca crees dependencias '
            'ni prepares cambios en otro módulo. No inventes datos ni equivalencias. '
            'Los campos faltantes se solicitan al usuario; Realizar confirma cada cambio.')

    @activity.agent(lambda self, *a, **kw: self.identity)
    def run(self, session, instruction, previous='', context=''):
        return run_specialist(session, instruction, previous, context, self.resources,
                              self.instructions, self.skills, writable_resources=(self.resource,),
                              dependencies=self.dependencies)

    @activity.agent(lambda self, *a, **kw: self.identity)
    def inspect_options(self, session, instruction):
        """Read the specialist's own catalog for a coordinated recommendation."""
        from app.modules.asistente_ia import configuration, tools
        configuration.authorize(self.identity, self.resource)
        return read_options(session, self.resource)


@activity.tool('consultar_opciones_registradas')
def read_options(session, resource):
    from app.modules.asistente_ia import configuration, tools
    configuration.authorize_owner(resource)
    records = tools.records(session, resource)
    return {'recurso': resource, 'total': len(records), 'registros': records}


SPECIALISTS = {agent.identity: agent for agent in (
    Specialist('categorias_carta', 'Categorías de carta', 'categorias_carta', (),
               'Crea y edita las categorías que agrupan los artículos de la carta.'),
    Specialist('menajes', 'Menajes', 'menajes', (),
               'Crea y edita platos, vasos, copas y otros menajes para servir.'),
    Specialist('presentaciones', 'Presentaciones de venta', 'presentaciones', ('categorias_carta', 'menajes', 'productos'),
               'Define artículo, contenido, unidad, precio, categoría y menaje; revisa posibles insumos y abastecimiento.',
               ('proveedores', 'stock', 'recetas', 'subproductos')),
    Specialist('subproductos', 'Subproductos', 'subproductos', ('productos',),
               'Define preparaciones internas con productos, cantidades, rendimiento e instrucciones.', ('proveedores', 'stock')),
    Specialist('recetas', 'Recetas', 'recetas', ('presentaciones', 'productos', 'subproductos'),
               'Consulta preparación, ingredientes y abastecimiento del local; gestiona recetas por presentación.',
               ('proveedores', 'stock')),
    Specialist('promociones', 'Promociones', 'promociones', ('presentaciones',),
               'Crea y edita promociones con precio, horario y grupos de presentaciones existentes.'),
)}
