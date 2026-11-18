from app.multiagente.agents import activity
import re
from pathlib import Path

from app.multiagente.agents.runtime import run_specialist
from app.multiagente.api import tools

SKILLS = (Path(__file__).parents[2] / 'api' / 'skills' / 'compras' / 'SKILL.md',)
RESOURCES = ('ordenes_compra', 'pedido_sugerido', 'presentaciones', 'recetas', 'subproductos', 'demanda_rotacion')
INSTRUCTIONS = '''Eres el especialista de compras de Barbarito. Responde en español, breve y claro.
Solo preparas propuestas para revisión; no ejecutas ni confirmas pedidos.
El Coordinador ofrece análisis opcionales o ejecuta los que el usuario ya solicitó antes del pedido. Usa los informes recibidos
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
La propuesta no es una orden enviada. Solo al confirmar Enviar pedido se registra como ENVIADA.
Respeta permisos y local activo; no aceptes SQL ni rutas ni identificadores de otro local.'''




@activity.agent('compras')
def run(session, instruction, previous='', context='', *, horizonte=None,dias_abastecimiento=7):
    tools.authorize(session, 'ordenes_compra')
    text = tools.normalized(instruction)
    weekly=re.fullmatch(r'prepara el pedido semanal con (\d+(?:\.\d+)?)% de incremento sobre el consumo\.?',text.strip())
    if not weekly and horizonte=='semanal':
        weekly=re.fullmatch(r'prepara el pedido con (\d+(?:\.\d+)?)% de incremento sobre el consumo\.?',text.strip())
    if weekly:
        from app.multiagente.api import configuration, purchases
        configuration.authorize('compras','pedido_sugerido')
        tools.authorize(session,'pedido_sugerido')
        percentage=weekly.group(1)
        suggestion=tools.native('/ordenes-compra/pedido-sugerido?porcentaje='+percentage+'&horizonte=semanal'+(f'&dias={dias_abastecimiento}' if dias_abastecimiento!=7 else ''))
        if not suggestion.get('productos'):
            return {'respuesta':suggestion.get('diagnostico',{}).get('mensaje','Sin cantidades semanales calculadas.')+
                    f' Conservo tu incremento de {percentage}%. No se creó ninguna orden.', 'plan':None,'consultas':[]}
        plan=purchases.prepare(session,'crear',None,{'porcentaje_general':percentage,'adicionales':[], 'horizonte':'semanal','dias_abastecimiento':dias_abastecimiento})
        return {'respuesta':f'Revisa la propuesta para {dias_abastecimiento} días. Todavía no se ha guardado ni enviado ninguna orden.',
                'plan':plan,'consultas':[]}
    guided = re.fullmatch(r'prepara el pedido con (\d+(?:\.\d+)?)% de incremento sobre el consumo\.?', text.strip())
    if guided:
        from app.multiagente.api import configuration
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
    instructions=INSTRUCTIONS
    if horizonte=='semanal':
        instructions+=f'\nEl pedido vigente tiene un plazo confirmado de {dias_abastecimiento} días. Toda propuesta debe incluir horizonte:"semanal" y dias_abastecimiento:{dias_abastecimiento} en datos_json de preparar_cambio. Conserva los porcentajes y adicionales indicados; nunca uses la base mensual ni otro plazo.'
    result=run_specialist(session, instruction, previous, context, RESOURCES, instructions,
                         SKILLS, writable_resources=('ordenes_compra',))
    if horizonte=='semanal' and result.get('plan') and (result['plan'].get('horizonte')!='semanal' or result['plan'].get('dias_abastecimiento',7)!=dias_abastecimiento):
        result['plan']=None
        result['respuesta']=f'La corrección no conservó el plazo confirmado de {dias_abastecimiento} días. No se guardó ningún pedido; vuelve a indicar el cambio.'
    return result
