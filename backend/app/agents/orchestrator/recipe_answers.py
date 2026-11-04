"""Read preparation answers directly from authorized recipe records, without generation."""
import re

from app.modules.asistente_ia import tools


SELECT = r'consultar preparacion registrada de receta #(\d+)'
STOP = {'un', 'una', 'el', 'la', 'los', 'las', 'de', 'del', 'para', 'por', 'favor',
        'en', 'nuestro', 'nuestra', 'local', 'barbarian', 'barbarito', 'aqui', 'uan'}
UNITS = {'C62': 'unidad', 'KGM': 'kg', 'LTR': 'L', 'GRM': 'g', 'MLT': 'mL'}


def detect(instruction):
    value = tools.normalized(instruction).strip()
    if re.fullmatch(SELECT, value):
        return value
    if re.search(r'\b(crear|crea|editar|edita|modificar|modifica|actualizar|actualiza|cambiar|cambia|agregar|agrega)\b', value):
        return None
    value = re.sub(r'\b(?:preapra|preprar|preaparar)\b', 'prepara', value)
    match = re.search(r'\b(?:como\s+(?:se\s+)?(?:prepara[rs]?|prepra|preparo|hace[rs]?|hago|cocina[rs]?|cocino|elabora[rs]?)|quiero\s+(?:hacer|preparar|cocinar|elaborar)|preparacion\s+de|ingredientes\s+(?:de|para)|receta\s+de)\s+(.+)', value)
    if not match:
        return None
    target = match.group(1)
    if re.search(r'\b(pedido|orden|compra|conteo|inventario|jornada|factura|recepcion|traslado|reporte)\b', target):
        return None
    return re.split(r'\b(?:paso a paso|y su preparacion|por favor|de nuestro local|en nuestro local)\b', target, maxsplit=1)[0].strip()


def close_word(term, word):
    """Small edit distance including adjacent transposition; never approximate numbers/IDs."""
    if term == word:
        return True
    if min(len(term), len(word)) < 3 or not term.isalpha() or not word.isalpha():
        return False
    limit = 2 if min(len(term), len(word)) >= 8 else 1
    if abs(len(term) - len(word)) > limit:
        return False
    grid = [list(range(len(word) + 1))]
    for i, left in enumerate(term, 1):
        grid.append([i] + [0] * len(word))
        for j, right in enumerate(word, 1):
            grid[i][j] = min(grid[i - 1][j] + 1, grid[i][j - 1] + 1,
                             grid[i - 1][j - 1] + (left != right))
            if i > 1 and j > 1 and left == word[j - 2] and term[i - 2] == right:
                grid[i][j] = min(grid[i][j], grid[i - 2][j - 2] + 1)
    return grid[-1][-1] <= limit


def unit(value):
    return UNITS.get(value, value or '')


def label(row):
    return f'{row["codigo_item"]} · {row["item_carta"]} · {row["contenido"]} {unit(row["unidad_presentacion"])}'


def handle(session, instruction):
    target = detect(instruction)
    if target is None:
        return None
    from app.modules.asistente_ia import configuration
    configuration.authorize('recetas', 'recetas')
    tools.authorize(session, 'recetas')
    rows = tools.records(session, 'recetas')
    approximate = False
    selected = re.fullmatch(SELECT, target)
    if selected:
        matches = [row for row in rows if row['id_receta'] == int(selected.group(1)) and row.get('activo', True)]
    else:
        terms = [term.rstrip('s') for term in re.findall(r'[a-z0-9]+', target) if term not in STOP]
        matches, candidates = [], []
        for row in rows:
            content = format(float(row.get('contenido', 0)), 'g')
            names = tools.normalized(' '.join(str(row.get(key, '')) for key in ('item_carta', 'categoria_carta')))
            name_words = {word.rstrip('s') for word in re.findall(r'[a-z0-9]+', names)}
            text = names + ' ' + tools.normalized(str(row.get('codigo_item', ''))) + ' ' + content + ' ' + unit(row.get('unidad_presentacion'))
            words = {word.rstrip('s') for word in re.findall(r'[a-z0-9]+', text)}
            if row.get('activo', True):
                candidates.append((row, words, name_words))
            if row.get('activo', True) and all(term in words for term in terms):
                matches.append(row)
        if not matches and terms:
            matches = [row for row, words, names in candidates if all(term in words or any(close_word(term, word) for word in names) for term in terms)]
            approximate = bool(matches)
    result = {'agente': 'recetas', 'plan': None, 'consultas': []}
    if not matches:
        result['respuesta'] = ('No encontré una receta activa registrada que coincida con tu consulta en Barbarian. '
                               'Indica el nombre o código del artículo de la carta. No completaré la preparación con una receta genérica.')
        return result
    if len(matches) > 1:
        result['respuesta'] = ((f'Encontré {len(matches)} coincidencias aproximadas en nuestras recetas. ¿Cuál quisiste decir? ' if approximate else
                                f'Encontré {len(matches)} recetas registradas que coinciden. ¿Cuál quieres consultar? ') +
                               'Cada opción corresponde a un artículo y presentación de nuestra carta.' +
                               (' Muestro las primeras 20; indica un nombre más específico para acotar.' if len(matches) > 20 else ''))
        result['opciones'] = [{'etiqueta': label(row), 'instruccion': f'Consultar preparación registrada de receta #{row["id_receta"]}'} for row in matches[:20]]
        return result
    row = matches[0]
    parts = [f'Receta registrada de Barbarian: {label(row)}', '\nIngredientes registrados:']
    if approximate:
        parts.insert(0, f'Interpreté tu consulta como «{row["item_carta"]}», según las recetas registradas.\n')
    if not row.get('componentes'):
        parts.append('No hay ingredientes registrados.')
    for component in row.get('componentes', []):
        parts.append(f'- {component["nombre_componente"]}: {component["cantidad"]} {unit(component["unidad"])}')
    instructions = (row.get('instrucciones') or '').strip()
    parts.append('\nPreparación registrada:\n' + instructions if instructions else
                 '\nNo hay instrucciones de preparación registradas para esta receta. Puedo mostrar sus ingredientes, pero no inventar pasos, tiempos ni temperaturas. El responsable debe completar la receta en el sistema.')
    sauces = row.get('grupo_salsa')
    if sauces and sauces.get('activo', True):
        parts.append(f'\nSalsas registradas (máximo {sauces["cantidad_maxima"]}):')
        parts.extend(f'- {option["nombre"]}: {option["cantidad"]} {unit(option["unidad"])}' for option in sauces.get('opciones', []) if option.get('activo', True))
    result['respuesta'] = '\n'.join(parts)
    result['consultas'] = [{'recurso': 'recetas', 'total': 1, 'desde': 0, 'hay_mas': False, 'registros': [row]}]
    return result
