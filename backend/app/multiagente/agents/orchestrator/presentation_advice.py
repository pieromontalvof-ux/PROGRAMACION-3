"""Bounded, read-only recommendations before asking a presentation's questions."""
from decimal import Decimal, InvalidOperation, ROUND_FLOOR
import json
import re
from app.multiagente.agents import activity
from app.multiagente.agents.catalog_specialists import SPECIALISTS
from app.multiagente.api import tools, configuration, provider
from app.modules.carta.measurements import milliliters
from app.multiagente.agents.runtime import function
from app.multiagente.api.provider import AssistantError


def parse(instruction):
    if not re.search(r'\b(?:crear|crea|agregar|agrega)\b',tools.normalized(instruction)):
        return None
    def quoted_value(label):
        # Match each closing delimiter to its opener; apostrophes inside a
        # double-quoted name are content, not the end of that name.
        quoted=r'''\s*(?:"([^"]+)"|“([^”]+)”|«([^»]+)»|‘([^’]+)’|'([^']+)')'''
        match=re.search(label+quoted,instruction,re.I)
        return next((value.strip() for value in match.groups() if value is not None),None) if match else None
    title=quoted_value(r'(?:llamad[ao]|nombre)') or quoted_value(r'(?:crear|crea|agregar|agrega)')
    category=quoted_value(r'categor[ií]a') or quoted_value(r'\ben')
    size=re.search(r'\bde\s*(\d+(?:[.,]\d+)?)\s*(mL|mililitros?|litros?|L)\b',instruction,re.I)
    price=re.search(r'\ba\s+S/\s*(\d+(?:[.,]\d+)?)',instruction,re.I)
    if not all((title,category,size,price)):return None
    try:
        amount=Decimal(size[1].replace(',','.'));cost=Decimal(price[1].replace(',','.'))
        unit='mL' if size[2].lower().startswith(('ml','mili')) else 'L'
        base_amount=amount/1000 if unit=='mL' else amount
        if not (0<base_amount<=Decimal('999999999.999') and 0<=cost<=Decimal('99999999.99')):
            return None
        if cost!=cost.quantize(Decimal('.01')) or base_amount!=base_amount.quantize(Decimal('.001')):
            return None
    except InvalidOperation:
        return None
    if not (1<=len(title)<=200 and 1<=len(category)<=100):return None
    return {'nombre':title,'categoria':category,'cantidad':str(amount),
            'unidad':unit,'precio':str(cost),'mililitros':str(amount if unit=='mL' else amount*1000)}


def active(row):
    return bool(row.get('activo',True)) and row.get('estado_registro',1)==1


def suggested_prefix(name,categories):
    words=re.findall('[a-z]+',tools.normalized(name));important=[w for w in words if w not in ('de','del','la','las','el','los','y')]
    base=''.join(w[0] for w in important).upper()[:5]
    used={str(r.get('prefijo','')).upper() for r in categories}
    candidates=[base,''.join(w[0] for w in words).upper()[:5]]
    letters=''.join(important).upper()
    candidates += [letters[:n] for n in range(2,6)]
    return next((c for c in candidates if c and c not in used),None)


def volume(row):
    try:
        n=Decimal(str(row['contenido']))
        u=str(row.get('unidad','')).upper()
        return n*1000 if u in ('LTR','L') else n if u in ('MLT','ML') else None
    except (KeyError,InvalidOperation,ValueError,TypeError):return None


def semantic_parse(instruction):
    fields={k:{'type':'string'} for k in ('nombre','categoria','cantidad','unidad','precio')}
    fields['completo']={'type':'boolean'}
    try:
        output=provider.respond([{'role':'system','content':
            'Extrae una solicitud explícita de CREAR presentación de bebida. Solo datos del mensaje, sin inventar. '
            'Llama interpretar_presentacion una vez. completo=false si no pide crear o falta nombre, categoría, '
            'volumen o precio. cantidad y precio como números decimales; unidad solo mL o L. No ejecutes acciones.'},
            {'role':'user','content':instruction[:4000]}],
            [function('interpretar_presentacion','Extraer datos explícitos sin modificar catálogos.',fields)],max_output_tokens=600)
        calls=[r for r in output if r.get('type')=='function_call']
        if len(calls)!=1 or calls[0].get('name')!='interpretar_presentacion':return None
        value=json.loads(calls[0]['arguments'])
        if not isinstance(value,dict) or set(value)!=set(fields) or value['completo'] is not True:return None
        if any(not isinstance(value[k],str) for k in fields if k!='completo'):return None
        if value['unidad'] not in ('mL','L'):return None
        if not all(re.fullmatch(r'\d+(?:[.,]\d+)?',value[k]) for k in ('cantidad','precio')):return None
        # Reuse all bounds, decimal precision and title checks in the native parser.
        encoded=('Crear presentación llamada '+json.dumps(value['nombre'],ensure_ascii=False)+
                 ', de '+value['cantidad']+' '+value['unidad']+', a S/ '+value['precio']+
                 ', categoría '+json.dumps(value['categoria'],ensure_ascii=False))
        parsed=parse(encoded)
        return parsed if parsed and parsed['nombre']==value['nombre'] and parsed['categoria']==value['categoria'] else None
    except (AssistantError,ValueError,KeyError,TypeError):
        return None


def run(session,instruction,*,interpret=False):
    if not tools.allowed(session,'presentaciones','crear') or not configuration.owner_allows('presentaciones','crear'):
        return None
    requested=parse(instruction)
    if requested is None and interpret:
        requested=semantic_parse(instruction)
    if requested is None:return None
    return review(session,instruction,requested)


@activity.agent('presentaciones')
def review(session,instruction,requested):
    tools.authorize(session,'presentaciones')
    sources={};limitations=[]
    for resource,task in [('categorias_carta','Revisar la categoría solicitada, alternativas existentes y un prefijo disponible.'),
                          ('menajes','Revisar menajes activos para la presentación solicitada.'),
                          ('presentaciones','Comparar contenido y menajes de presentaciones registradas.')]:
        try:
            sources[resource]=SPECIALISTS[resource].inspect_options(session,task)['registros']
        except AssistantError as error:
            if error.status!=403:raise
            limitations.append(resource);sources[resource]=[]
    categories=sources['categorias_carta'];wares=[r for r in sources['menajes'] if active(r)]
    presentations=[r for r in sources['presentaciones'] if active(r)]
    duplicates=[r for r in sources['presentaciones'] if tools.normalized(str(r.get('item') or r.get('nombre_item') or r.get('nombre') or ''))==tools.normalized(requested['nombre'])
                and volume(r)==Decimal(requested['mililitros'])]
    if duplicates:
        message=f"Ya existe **{requested['nombre']} · {requested['cantidad']} {requested['unidad']}**. No propongo crear un duplicado."
        if any(not active(row) for row in duplicates):
            message+=' La coincidencia incluye una presentación inactiva.'
        if len(duplicates)>1:
            message+=' Hay varias coincidencias registradas; primero debemos elegir cuál revisar.'
        elif tools.allowed(session,'presentaciones','editar') and configuration.owner_allows('presentaciones','editar'):
            message+=' ¿Quieres revisar y modificar esa presentación?'
        else:
            message+=' Tu perfil no tiene habilitada su edición.'
        return {'respuesta':message,'consultas':[{'recurso':'presentaciones','total':len(duplicates),'desde':0,'hay_mas':len(duplicates)>3,'registros':duplicates[:3]}],
                'plan':None,'agente':'presentaciones','_referencias_revisadas':{'solicitud':requested,'coincidencias_existentes':duplicates[:3]}}
    matches=[r for r in categories if tools.normalized(r['nombre'])==tools.normalized(requested['categoria'])]
    exact=next((r for r in matches if active(r)),None)
    ignored={'de','del','la','las','el','los','y','especial','nuevo','nueva','clasico','clasica'}
    tokens=set(tools.normalized(requested['categoria']+' '+requested['nombre']).split())-ignored
    title_tokens=set(tools.normalized(requested['nombre']).split())-ignored
    def item_words(row):
        return set(tools.normalized(str(row.get('item') or row.get('nombre_item') or row.get('nombre') or '')).split())
    related_categories={row.get('id_categoria_carta') for row in presentations if title_tokens & item_words(row)}
    alternatives=sorted([r for r in categories if active(r) and r not in matches and
        (r.get('id_categoria_carta') in related_categories or tokens & (set(tools.normalized(r['nombre']).split())-ignored))],
        key=lambda r:(-(r.get('id_categoria_carta') in related_categories),-len(tokens & set(tools.normalized(r['nombre']).split())),r['nombre']))[:2]
    prefix=suggested_prefix(requested['categoria'],categories) if not matches and 'categorias_carta' not in limitations else None
    can_create=tools.allowed(session,'categorias_carta','crear') and configuration.owner_allows('categorias_carta','crear')
    amount=Decimal(requested['mililitros'])
    measured=[]
    for ware in wares:
        try:
            capacity=milliliters(ware.get('capacidad'),ware.get('unidad_capacidad'))
        except ValueError:
            continue
        measured.append((ware,capacity))
    fitting=[pair for pair in measured if pair[1]>=amount]
    chosen=min(fitting,key=lambda pair:pair[1]) if fitting else max(measured,key=lambda pair:pair[1],default=None)
    preferred=chosen[0] if chosen else next((w for w in wares if 'vaso' in tools.normalized(w['nombre'])),wares[0] if wares else None)
    capacity=chosen[1] if chosen else None
    suggested=(capacity/10).to_integral_value(rounding=ROUND_FLOOR)*10 if capacity is not None and capacity<amount else amount
    if suggested<=0 and capacity is not None:
        suggested=capacity.to_integral_value(rounding=ROUND_FLOOR)
    samples=[r for r in presentations if preferred and r.get('id_menaje')==preferred['id_menaje'] and volume(r) is not None]
    sample=min(samples,key=lambda r:(-len(title_tokens & item_words(r)),abs(volume(r)-amount)),default=None)
    if not exact and not alternatives:
        alternatives=[r for r in categories if active(r) and r not in matches and tools.normalized(r['nombre']) in ('sin alcohol','bebidas sin alcohol')][:1]
    lines=[f"Puedo preparar **{requested['nombre']} · {requested['cantidad']} {requested['unidad']} · S/ {Decimal(requested['precio']):.2f}**."]
    if 'categorias_carta' in limitations:
        lines.append('- **Categoría:** no pude revisarla con los accesos actuales.')
    elif exact:
        lines.append(f"- **Categoría:** ya existe **{exact['nombre']}** (prefijo {exact.get('prefijo','registrado')}).")
    elif matches:
        lines.append(f"- **Categoría:** {requested['categoria']} ya existe inactiva; no propongo un duplicado.")
    elif can_create and prefix:
        lines.append(f"- **Categoría:** no existe **{requested['categoria']}**. Propongo crearla con el prefijo **{prefix}** (disponible al consultar).")
    else:
        lines.append('- **Categoría:** no existe; falta una opción activa y autorizada antes de continuar.')
    if not exact and alternatives:
        lines[-1]+=' También puedes usar '+ ' o '.join('**'+r['nombre']+'**' for r in alternatives)+'.'
    if preferred and capacity is not None:
        measured_text=format(capacity.quantize(Decimal('.001')).normalize(),'f')
        lines.append(f"- **Menaje:** sugiero **{preferred['nombre']}**, capacidad registrada de {measured_text} mL.")
        if preferred.get('origen_medidas') == 'DEMO':
            lines[-1]+=' Medida de ejemplo para pruebas.'
    elif preferred:
        lines.append(f"- **Menaje:** existe **{preferred['nombre']}**, pero su capacidad no está registrada. Hay que medirla y registrarla antes de confirmar esta medida.")
    else:
        lines.append('- **Menaje:** no pude verificar una opción activa con los accesos y datos disponibles.')
    if capacity is not None and capacity<amount:
        decision='medida_precio'
        lines[-1]+=' Puedes ajustar la medida y revisar el precio.'
        question=(f"¿Prefieres {format(suggested.normalize(),'f')} mL y revisar el precio, "
                  f"o elegir un menaje con capacidad suficiente para {requested['cantidad']} {requested['unidad']} a S/ {Decimal(requested['precio']):.2f}?")
    elif capacity is None:
        decision='menaje'
        question=('¿Registramos la capacidad del menaje antes de continuar?' if preferred else
                  '¿Qué menaje medido quieres usar o proponer crear?')
    elif not exact:
        decision='categoria'
        if can_create and prefix:
            question=f'¿Usamos una categoría existente o proponemos crear {requested["categoria"]} con el prefijo {prefix}?'
            if not alternatives:
                question=f'¿Proponemos crear {requested["categoria"]} con el prefijo {prefix}?'
        else:
            question='¿Qué categoría activa quieres usar?'
    else:
        decision='menaje'
        question=f'¿Usamos {preferred["nombre"]} para esta presentación?'
    lines.append(question)
    from app.multiagente.agents import supply
    supply_report = supply.for_title(session, requested['nombre'], 'presentaciones')
    if supply_report:
        lines.insert(-1, '- **Insumo:** ' + supply_report['resumen'])
        if supply_report['requiere_decision']:
            if supply_report.get('alcance') == 'CATALOGO':
                decision='insumo_catalogo'
                lines[-1]='¿Revisamos ese insumo del catálogo antes de continuar con la presentación?'
            else:
                decision='abastecimiento'
                lines[-1]='¿Revisamos ese insumo y su abastecimiento antes de continuar con la presentación?'
    references={'solicitud':requested,'categoria_existente':exact,'prefijo_propuesto':prefix,
                'alternativas_categoria':alternatives,'menaje_propuesto':preferred,
                'referencia_volumen':sample,'capacidad_ml':str(capacity) if capacity is not None else None,'medida_sugerida_ml':str(suggested) if capacity is not None else None,'limitaciones':limitations,
                'decision_pendiente':decision,'revision_insumo':supply_report}
    queries=[{'recurso':r,'total':len(rows),'desde':0,'hay_mas':len(rows)>3,'registros':rows[:3]} for r,rows in sources.items()]
    if supply_report:
        queries.append(supply_report)
    return {'respuesta':'\n\n'.join(lines),'consultas':queries,'plan':None,'agente':'presentaciones',
            '_referencias_revisadas':references}
