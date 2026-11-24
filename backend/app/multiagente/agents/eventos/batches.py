"""Bounded independent searches: one failed family never erases another."""
import json
from concurrent.futures import ThreadPoolExecutor
from contextlib import nullcontext
from flask import current_app, has_app_context
from app.multiagente.api.provider import AssistantError
from . import research
from app.multiagente.api import quotas

MAX_CANDIDATES=30


def run(payloads,search):
    app=current_app._get_current_object() if has_app_context() else None
    owner=quotas.principal()
    def task(payload):
        with app.app_context() if app else nullcontext(), quotas.accounting_scope(owner):
            try:
                return search(payload),None
            except AssistantError as error:
                return None,error
    with ThreadPoolExecutor(max_workers=3) as pool:
        results=list(pool.map(task,payloads))
    candidates,outputs,limitations=[],[],[]
    partial=False
    structured=False
    first_response=None
    sources=set()
    for index,(response,error) in enumerate(results,1):
        if error:
            partial=True
            limitations.append(f'Consulta {index} incompleta: {error}')
            continue
        first_response=first_response or response
        data,urls=research.unpack(response)
        sources.update(urls)
        partial |= response.get('status')!='completed' or data is None or bool(data.get('_partial'))
        outputs.extend(item for item in response.get('output',[]) if item.get('type')=='web_search_call')
        if data is not None:
            structured=True
            candidates.extend(r for r in data['candidatos'] if isinstance(r,dict))
            if data.get('limitaciones'):
                limitations.append(str(data['limitaciones'])[:300])
        else:
            limitations.append(f'Consulta {index}: no devolvió una lista verificable.')
    if not structured:
        if first_response is not None:
            return first_response
        budget_error=next((error for _,error in results if isinstance(error,AssistantError) and error.status==429),None)
        if budget_error is not None:
            raise budget_error
        raise AssistantError('No se pudieron completar las búsquedas de eventos. Conserva los resultados anteriores e intenta nuevamente.',502)
    unique={}
    for row in candidates:
        key=research.identity(row)
        previous=unique.get(key)
        if previous is None or sum(bool(v) for v in row.values())>sum(bool(v) for v in previous.values()):
            unique[key]=row
    ordered=sorted(unique.values(),key=lambda r:(str(r.get('fecha_desde','')),str(r.get('nombre',''))))
    if len(ordered)>MAX_CANDIDATES:
        partial=True
        limitations.append('Se alcanzó el límite de 30 candidatos; hay resultados adicionales pendientes.')
    data={'candidatos':ordered[:MAX_CANDIDATES],'limitaciones':' '.join(limitations)}
    outputs.append({'type':'message','content':[{'type':'output_text','text':json.dumps(data,ensure_ascii=False),
        'annotations':[{'type':'url_citation','url':url,'title':'Fuente consultada'} for url in sorted(sources)]}]})
    return {'status':'incomplete' if partial else 'completed','output':outputs}


def discover(payload,search,venues):
    groups=[('HOTELES',('hotel','conference_centre'),'congresos, convenciones y ferias en hoteles y centros de convenciones'),
            ('CULTURA',('theatre','arts_centre','museum','gallery'),'teatros, auditorios, museos y centros culturales; conciertos, ópera y obras'),
            ('OCIO',('park','stadium','events_venue'),'parques, anfiteatros y recintos de música en vivo; festivales y conciertos')]
    requests=[]
    for label,kinds,focus in groups:
        named=[r for r in venues if r.get('tipo') in kinds]
        prompt=payload['input']+f'\nGRUPO {label}: concentra esta búsqueda independiente en {focus}. '
        prompt+=('Revisa TODAS las fechas del período, incluyendo el último día. Busca por nombre del recinto y fecha; '
                 'consulta agenda del recinto, organizador y boletera. No rellenes con eventos lejanos. '
                 'No omitas otros recintos cercanos de esta familia aunque no figuren en el mapa. '
                 'Devuelve hasta 10 candidatos en el JSON solicitado; textos breves y fuentes reales. ')
        if named:
            prompt+='Recintos prioritarios de esta familia: '+json.dumps(named,ensure_ascii=False)
        requests.append({**payload,'input':prompt})
    return run(requests,search)


def verify(payload,search,candidates):
    base=payload['input'].split('\nCandidatos:',1)[0]
    chunks=[candidates[i:i+6] for i in range(0,min(len(candidates),MAX_CANDIDATES),6)] or [[]]
    requests=[{**payload,'max_tool_calls':4,'input':base+'\nRevisa únicamente este lote; no reinicies una búsqueda general. '
               'Resuelve cada candidato y conserva su nombre y fechas al corroborarlos. '
               'Si no consigues comprobar alguno, devuélvelo con su motivo pendiente.\nCandidatos: '+json.dumps(chunk,ensure_ascii=False)} for chunk in chunks]
    return run(requests,search)
