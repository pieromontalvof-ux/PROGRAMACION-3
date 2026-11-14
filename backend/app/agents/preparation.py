"""Conversation facts for a drink's preparation and explicit sale measure."""
import json
import re
from copy import deepcopy
from decimal import Decimal, InvalidOperation

from app.modules.asistente_ia.tools import normalized
from app.modules.asistente_ia.provider import AssistantError

MEASURE = r'(\d+(?:[.,]\d+)?)\s*(ml|mililitros?|l|litros?|porciones?|porcion)\b'


def history(context, depth=0):
    if depth > 8:
        return [], {}
    try:
        data = json.loads(context) if isinstance(context, str) else context
    except (ValueError, TypeError):
        return [], {}
    if not isinstance(data, dict):
        return [], {}
    turns, saved = history(data.get('contexto_original', ''), depth + 1)
    # A delegated instruction is model-authored; keep the human root request
    # rather than replacing its measure with the child's proposed equivalent.
    if not turns and isinstance(data.get('tarea_original'), str):
        turns.append(data['tarea_original'])
    clarifications = data.get('aclaraciones')
    if isinstance(clarifications, list):
        turns.extend(t for t in clarifications if isinstance(t, str))
    if isinstance(data.get('preparacion'), dict):
        saved = data['preparacion']
    return turns, saved


def measure(text, initial=False):
    text = normalized(text)
    found = re.search(r'\b(?:vasos?|presentacion|medida|tamano|bebida)\s+(?:(?:de|a|en|sera|es)\s+)*' + MEASURE, text)
    batch = re.search(r'\b(?:lotes?|rendimiento|rinda|rinde)\b', text)
    batch_context = bool(batch)
    if not found and initial:
        candidate = re.search(MEASURE, text)
        if candidate and (not batch or candidate.start() < batch.start()):
            found = candidate
    elif not initial and not batch_context:
        if not found and re.search(r'\b(?:crear|crea|registrar|registra|agregar|agrega)\b', text) and re.search(r'\b(?:receta|presentacion)\b', text):
            found = re.search(MEASURE, text)
        if not found:
            found = re.search(r'\b(?:cambia|cambiala|cambialo|ajusta|ajustala|manten|conserva|prefiero|mejor|dejalo|dejala)\b[^.;!?]{0,45}?' + MEASURE, text)
        if not found:
            found = re.fullmatch(r'(?:si[, ]+)?(?:de\s+|a\s+)?' + MEASURE + r'(?:\s*(?:a|por|y)?\s*s/\s*\d+(?:[.,]\d+)?)?[ .]*', text)
    if not found:
        return None
    amount = Decimal(found[1].replace(',', '.'))
    if amount <= 0 or amount > Decimal('999999999.999'):
        return None
    unit = 'MLT' if found[2].startswith(('ml', 'mili')) else 'LTR' if found[2].startswith('l') else 'PORCION'
    return {'cantidad': str(amount), 'unidad': unit}


def method(text):
    value = normalized(text).strip()
    if value.startswith(('¿', 'como ', 'explica', 'dime ', 'que significa')):
        return None
    value = re.sub(r'\bno\s+(?:(?:lo|la|quiero|sera|es|preparo)\s+)*(?:por|en)\s+lotes?\b', '', value)
    batch = bool(re.search(r'\b(?:por|en)\s+(?:un\s+)?lotes?\b', value))
    glass = bool(re.search(r'\b(?:por|cada)\s+(?:un\s+|una\s+)?(?:vaso|porcion|unidad)\b|\bal momento\b', value))
    return ('LOTE' if batch else 'POR_VASO') if batch != glass else None


def resolve(instruction, context=''):
    turns, saved = history(context)
    sale = saved.get('medida_venta')
    try:
        valid = (isinstance(sale, dict) and sale.get('unidad') in ('MLT', 'LTR', 'PORCION')
                 and Decimal(str(sale['cantidad'])).is_finite()
                 and 0 < Decimal(str(sale['cantidad'])) <= Decimal('999999999.999'))
    except (KeyError, InvalidOperation, ValueError, TypeError):
        valid = False
    state = {'requerido': bool(saved.get('requerido')), 'metodo': saved.get('metodo'),
             'medida_venta': deepcopy(sale) if valid else None}
    if state['metodo'] not in ('LOTE', 'POR_VASO'):
        state['metodo'] = None
    if not turns:
        turns = [instruction]
    recipe = any(re.search(r'\b(?:crear|crea|registrar|registra|agregar|agrega)\s+(?:(?:un|una|la|el|nueva|nuevo)\s+)*receta\b', normalized(t)) for t in turns + [instruction])
    for index, turn in enumerate(turns):
        selected = method(turn)
        if selected and (index > 0 or state['metodo'] is None):
            state['metodo'] = selected
        requested = None if index == 0 and state['medida_venta'] is not None else measure(turn, initial=index == 0)
        if requested:
            state['medida_venta'] = requested
    if instruction != turns[0]:
        state['metodo'] = method(instruction) or state['metodo']
        state['medida_venta'] = measure(instruction) or state['medida_venta']
    sale = state['medida_venta']
    state['requerido'] = state['requerido'] or bool(recipe and sale and sale['unidad'] in ('MLT', 'LTR'))
    return state


def is_reference_question(instruction):
    return bool(re.search(r'\b(?:como la|como el|explica\w*|dime|intermedio|final|que ingredientes|cuales ingredientes|como se prepara)\b', normalized(instruction)))


def question(state):
    sale = state.get('medida_venta')
    unit = {'MLT': 'mL', 'LTR': 'L', 'PORCION': 'porción'}
    size = f" y la medida de **{sale['cantidad']} {unit[sale['unidad']]}**" if sale else ''
    return f'Conservo los datos que ya elegiste{size}. ¿La prepararás **por lote** (un intermedio) o **por cada vaso**?'


def validate(state, resource, changes):
    if resource not in ('presentaciones', 'recetas'):
        return
    if not isinstance(changes, dict):
        raise AssistantError('La propuesta debe contener campos válidos de la receta o presentación.')
    if state.get('requerido') and state.get('metodo') is None:
        raise AssistantError('Primero pregunta si se prepara por lote o por cada vaso. Conserva los datos ya elegidos.')
    if resource == 'recetas':
        if state.get('requerido') and state['metodo'] == 'LOTE' and not any(c.get('tipo_componente') == 'SUBPRODUCTO' for c in changes.get('componentes', []) if isinstance(c, dict)):
            raise AssistantError('Por lote: define o elige primero el intermedio; la receta final debe consumir su cantidad por vaso, no los ingredientes de todo el lote.')
        return
    sale = state.get('medida_venta')
    if not sale:
        return
    units = {'MLT': ('VOLUMEN', Decimal('.001')), 'ML': ('VOLUMEN', Decimal('.001')),
             'LTR': ('VOLUMEN', Decimal(1)), 'L': ('VOLUMEN', Decimal(1)), 'PORCION': ('CONTEO', Decimal(1))}
    try:
        expected_unit = units[sale['unidad']]
        proposed_unit = units[str(changes['unidad']).upper()]
        equivalent = expected_unit[0] == proposed_unit[0] and Decimal(sale['cantidad']) * expected_unit[1] == Decimal(str(changes['contenido'])) * proposed_unit[1]
    except (KeyError, TypeError, ValueError, InvalidOperation):
        equivalent = False
    if not equivalent:
        raise AssistantError('Conserva el contenido y la unidad de venta indicados por el usuario. Una referencia o un lote no autorizan cambiarlos; pregunta antes de modificar la medida o convertirla a porción.')
