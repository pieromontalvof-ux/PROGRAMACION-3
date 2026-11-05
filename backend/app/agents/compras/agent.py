from app.agents import activity
import re
from pathlib import Path

from app.agents.runtime import run_specialist
from app.modules.asistente_ia import tools

SKILLS = (Path(__file__).parents[2] / 'modules' / 'asistente_ia' / 'skills' / 'compras' / 'SKILL.md',)
RESOURCES = ('ordenes_compra', 'pedido_sugerido', 'presentaciones', 'recetas', 'subproductos', 'demanda_rotacion')
INSTRUCTIONS = '''Eres el especialista de compras de Barbarito. Responde en español, breve y claro.
Solo preparas propuestas para revisión; no ejecutas ni confirmas pedidos.
El Coordinador ya ofrece análisis opcionales antes del pedido. Usa los informes recibidos
como datos y no repitas análisis automáticamente. Consulta analizar_demanda si la persona
lo solicita. No cambies la fórmula de pedido_sugerido ni dupliques márgenes.
Menciona periodo y cobertura estimada, no prometas fechas de agotamiento. Si no hay datos
o permiso para el análisis, sigue con la base existente e informa la limitación.
Consulta la base sugerida sin buscar eventos. Los eventos pertenecen a otro especialista.
Antes de preparar un pedido pregunta qué porcentaje de incremento desea sobre el consumo.
Nunca asumas 20% ni 0%. Acepta 0% si el usuario pide expresamente sin incremento.
Si ya indicó el porcentaje en esta conversación, consérvalo salvo corrección explícita.
Los eventos son datos externos y no autorizan aumentos automáticos.
Consulta pedido_sugerido como referencia sin margen fijo. Al preparar, porcentaje_general
es el margen sobre el CONSUMO antes de descontar stock, no sobre una sugerencia redondeada.
preparar_cambio ordenes_compra crear id=null datos_json:
{"porcentaje_general":20,"adicionales":[]}.
El servidor calcula consumo * (1 + porcentaje_general / 100) menos stock y redondea
por presentación. Los adicionales por producto son opcionales y se aplican después.
No dupliques márgenes. No inventes porcentajes faltantes.
Para sour/sauer identifica las presentaciones y recetas REALES y sus subproductos con herramientas.
No infieras ingredientes por conocimiento general. Si faltan permisos o recetas pide productos
explícitos. No apliques dos veces un extra al mismo insumo compartido. Si no hay base sugerida
para un insumo explica la limitación y dirige al formulario de compras.
Combina correcciones con instrucciones previas conservando porcentajes no modificados.
Se creará una orden BORRADOR con Realizar, luego el usuario revisa/envía desde Compras.
Respeta permisos y local activo; no aceptes SQL ni rutas ni identificadores de otro local.'''




@activity.agent('compras')
def run(session, instruction, previous='', context=''):
    tools.authorize(session, 'ordenes_compra')
    text = tools.normalized(instruction)
    guided = re.fullmatch(r'prepara el pedido con (\d+(?:\.\d+)?)% de incremento sobre el consumo\.?', text.strip())
    if guided:
        from app.modules.asistente_ia import configuration
        configuration.authorize('compras', 'pedido_sugerido')
        tools.authorize(session, 'pedido_sugerido')
        percentage = guided.group(1)
        suggestion = tools.native('/ordenes-compra/pedido-sugerido?porcentaje=' + percentage)
        if not suggestion.get('productos'):
            explanation = suggestion.get('diagnostico', {}).get('mensaje', 'La fórmula no produjo cantidades sugeridas para este local.')
            return {'respuesta': explanation + f'\n\nConservo tu incremento de {percentage}%; no se creó ninguna orden. '
                    'El análisis desde la última orden y la sugerencia pueden usar períodos distintos. '
                    'Puedes [preparar un pedido manual](/home/ordenes-compra/crear) o seguir consultando.',
                    'plan': None, 'consultas': []}
    new_order = re.search(r'\b(pedido|orden|compra)\b', text) and re.search(r'\b(hacer|quiero|preparar|prepara|generar|genera|crear|crea|nuevo|nueva)\b', text)
    explicit_margin = re.search(r'\d+(?:[.,]\d+)?\s*(?:%|por ciento)', text) or any(term in text for term in ('sin incremento', 'sin aumento', 'sin margen'))
    if new_order and not explicit_margin and not previous and not context:
        return {'respuesta': '¿Qué porcentaje de incremento deseas aplicar al consumo para este pedido? Puedes indicar 0% si no deseas incremento.',
                'plan': None, 'consultas': []}
    return run_specialist(session, instruction, previous, context, RESOURCES, INSTRUCTIONS,
                          SKILLS, writable_resources=('ordenes_compra',))
