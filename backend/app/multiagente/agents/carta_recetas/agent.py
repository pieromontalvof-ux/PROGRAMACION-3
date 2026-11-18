from app.multiagente.agents import activity
from pathlib import Path

from app.multiagente.agents.runtime import run_specialist
from app.multiagente.api.agent import INSTRUCTIONS

RESOURCES = ('productos', 'categorias_productos', 'proveedores', 'usuarios')
SKILLS = tuple(Path(__file__).parents[2] / 'api' / 'skills' / name / 'SKILL.md'
               for name in ('operaciones_catalogo', 'crear_categoria_producto', 'crear_proveedor', 'crear_producto'))


@activity.agent('carta_recetas')
def run(session, instruction, previous='', context=''):
    from app.multiagente.api import forms
    instructions = INSTRUCTIONS + ('\nGestiona categorías, proveedores y productos por conversación: revisa coincidencias '
        'y requisitos reales, conserva los datos recibidos y prepara una ficha de revisión. No impongas formularios.'
        if forms.prefers_chat() else '\nSi el usuario eligió el formulario, usa abrir_formulario para recoger los datos.')
    return run_specialist(session, instruction, previous, context, RESOURCES, instructions, SKILLS)
