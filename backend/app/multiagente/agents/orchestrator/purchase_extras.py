"""Resolve a general margin plus a recipe extra using authorized catalog records."""
import re
from app.multiagente.api import tools, configuration, purchases
from app.multiagente.api.provider import AssistantError
from .recipe_answers import close_word, STOP


def targets(reference):
    """Keep explicitly joined beverage references separate for catalog lookup."""
    stop=STOP|{'producto','productos','insumo','insumos','que','son','se','usan','usa','lleva','lleven','ara','pero','y','a','componen','compone','contiene','contienen'}
    return [terms for part in re.split(r'\s+(?:y|e)\s+|\s*[,;]\s*',tools.normalized(reference))
            if (terms:=[w for w in re.findall(r'[a-z0-9]+',part) if w not in stop])]


def selection(general, extra, reference):
    groups=targets(reference)
    result={'general':general,'extra':extra,'terms':[t for group in groups for t in group]}
    if len(groups)>1:
        result['targets']=groups
    return result


def intent(instruction):
    value=tools.normalized(instruction).strip()
    value=re.sub(r'\bno\s+(?:guardes|envies|confirmes|ejecutes)\b[^.;!?]*','',value)
    if '?' in value or re.search(r'\b(?:no|supongamos|ejemplo|pasaria)\b',value):
        return None
    value=re.sub(r'\bporciento\b','por ciento',value)
    if re.search(r'\d\s*(?:%|por ciento)',value):
        value=re.sub(r'(?<![\w.,])(\d+(?:[.,]\d+)?)\s+(?=(?:mas|extra|adicional(?:es)?)\b)',r'\1% ',value)
    matches=list(re.finditer(r'(\d+(?:[.,]\d+)?)\s*(?:%|por ciento)',value))
    extra_marker=r'\b(?:adicional(?:es)?|extra|mas)\b'
    # A trailing "auméntale 10 más" inherits the percentage unit already
    # established in this sentence, never an arbitrary ingredient quantity.
    trailing=re.search(r'\b(?:aumentale|aumenta|subele|agregale|anadele|incrementa)\s+'
                       r'(\d+(?:[.,]\d+)?)\s*(?:%|por ciento)?\s*(?:mas|extra|adicional)\s*[.!]?$',value)
    if trailing and len(matches) in (1,2) and matches[0].end()<trailing.start():
        target=value[matches[0].end():trailing.start()]
        target=re.sub(extra_marker,' ',target)
        extra=trailing[1].replace(',','.')
    elif len(matches)==2 and re.search(extra_marker,value[matches[1].end():]):
        target=re.split(extra_marker,value[matches[1].end():],maxsplit=1)[1]
        extra=matches[1][1].replace(',','.')
    else:
        return None
    stop=STOP|{'producto','productos','insumo','insumos','que','son','se','usan','usa','lleva','lleven','ara','pero','y','a','componen','compone','contiene','contienen'}
    terms=[w for w in re.findall(r'[a-z0-9]+',target) if w not in stop]
    if not terms:
        return None
    general=matches[0][1].replace(',','.')
    purchases.percentage(general);purchases.percentage(extra)
    return selection(general,extra,target)


def prepare(session, selected, days):
    configuration.authorize('compras','recetas')
    recipes=tools.records(session,'recetas')
    groups=selected.get('targets') or targets(' '.join(selected['terms']))
    matches=[]
    for terms in groups:
        found=[]
        for row in recipes:
            words=tools.normalized(row.get('item_carta','')).split()
            if row.get('activo',True) and all(any(close_word(t,w) for w in words) for t in terms):
                found.append(row)
        # The catalog names flavored drinks "Maracuyá Sour", while users
        # naturally say "Pisco Sour de Maracuyá". Retain every flavor term;
        # never fall back to the plain Sour or invent ingredients.
        if not found and 'pisco' in terms and 'sour' in terms and len(terms)>2:
            terms=[t for t in terms if t!='pisco']
            for row in recipes:
                words=tools.normalized(row.get('item_carta','')).split()
                if row.get('activo',True) and all(any(close_word(t,w) for w in words) for t in terms):
                    found.append(row)
        precise=[r for r in found if len(tools.normalized(r.get('item_carta','')).split())==len(terms)]
        if precise:
            found=precise
        names={tools.normalized(r.get('item_carta','')) for r in found}
        if len(names)!=1:
            raise AssistantError('No pude identificar una única receta para «'+' '.join(terms)+'». Conservé las demás bebidas y los porcentajes; indica el nombre registrado de esa bebida.')
        matches.extend(found)
    if not matches:
        raise AssistantError('Indica las bebidas a cuyos insumos se aplicará el adicional.')
    ids=set()
    subproducts=None
    for recipe in matches:
        if not recipe.get('componentes'):
            raise AssistantError('La receta no tiene ingredientes registrados. Indica qué insumos llevarán el adicional.')
        if recipe.get('grupo_salsa'):
            raise AssistantError('La receta tiene ingredientes opcionales. Indica qué insumos llevarán el adicional.')
        for component in recipe['componentes']:
            if component.get('tipo_componente')=='PRODUCTO' and component.get('id_producto'):
                ids.add(component['id_producto'])
            elif component.get('id_subproducto'):
                if subproducts is None:
                    configuration.authorize('compras','subproductos')
                    subproducts=tools.records(session,'subproductos')
                sub=next((r for r in subproducts if r['id_subproducto']==component['id_subproducto'] and r.get('activo',True)),None)
                if not sub or not sub.get('ingredientes') or any(not r.get('activo',True) for r in sub['ingredientes']):
                    raise AssistantError('Faltan ingredientes activos de un intermedio. Indica qué insumos llevarán el adicional.')
                ids.update(r['id_producto'] for r in sub['ingredientes'])
            else:
                raise AssistantError('Hay un componente sin identificar en la receta. Revisa sus insumos.')
    configuration.authorize('compras','pedido_sugerido')
    tools.authorize(session,'pedido_sugerido')
    suggestion=tools.native(f'/ordenes-compra/pedido-sugerido?porcentaje={selected["general"]}&horizonte=semanal&dias={days}')
    available={r['id_producto'] for r in suggestion.get('productos',[])}
    changes={'porcentaje_general':selected['general'],'adicionales':[
        {'id_producto':pid,'porcentaje':selected['extra']} for pid in sorted(ids & available)],
        'horizonte':'semanal','dias_abastecimiento':days}
    plan=purchases.prepare(session,'crear',None,changes)
    names=' y '.join(dict.fromkeys(r['item_carta'] for r in matches))
    return {'respuesta':f'Revisa las cantidades para {days} días: {selected["general"]}% general y {selected["extra"]}% adicional en los insumos de {names} que requieren reposición. El adicional se aplica una sola vez a cada insumo compartido. Puedes editar el total a pedir. No se ha guardado ni enviado ninguna orden.',
            'plan':plan,'consultas':[],'agente':'compras'}
