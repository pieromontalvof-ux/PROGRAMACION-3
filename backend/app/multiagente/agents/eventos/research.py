"""Structured event evidence, stable decisions and short-lived public research cache."""
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import time
from datetime import date
from flask import current_app, has_app_context
from app.multiagente.api.tools import normalized

FORMAT = '''Devuelve SOLO un objeto JSON sin Markdown: {"candidatos": [{"nombre":"...",
"fecha_desde":"AAAA-MM-DD","fecha_hasta":"AAAA-MM-DD","hora":"hora publicada o no publicada",
"recinto":"...","direccion":"...","tipo":"...","publico":"perfil publicado o probable, sin inventar edades",
"url":"URL del evento","fuente_fecha":"URL que acredita fecha y año",
"fuente_ubicacion":"URL que acredita dirección del recinto",
"cercania":"ACREDITADA o PENDIENTE","sustento_cercania":"evidencia concreta o vacío",
"acceso":"PUBLICO, INSCRIPCION, RESTRINGIDO o NO_VERIFICADO",
"estado":"ACTIVO, CANCELADO o NO_VERIFICADO","relevancia":"POTENCIAL o BAJA",
"motivo":"motivo de inclusión, duda o descarte"}],"limitaciones":"..."}.
Hasta 10 candidatos. Usa solo URLs consultadas, nunca inventadas. Conserva candidatos
fuera de rango, cancelados o no pertinentes con su motivo para explicar descartes.
Las sesiones legislativas y reuniones privadas con invitados cerrados son acceso RESTRINGIDO.
No son alternativas para completar una lista de eventos del bar.
Que una URL exista no acredita los datos: lee fecha/año, recinto y dirección.
Si no corroboras una hora, escribe No publicada, no repitas horas de agregadores como confirmadas.
Si falta cercanía, marca PENDIENTE; no uses relevancia BAJA solo por desconocer proximidad.
No inventes distancias ni públicos. Si la evidencia no alcanza, marca PENDIENTE.
Una búsqueda fallida no prueba ausencia de eventos. Si no hay candidatos, devuelve [].'''


def identity(row):
    name = re.sub(r'[^\w]+',' ',normalized(str(row.get('nombre') or ''))).strip()
    return (name, str(row.get('fecha_desde') or ''))


def refresh_candidates(discovered,prior):
    rows={identity(r):r for r in discovered if isinstance(r,dict)}
    for row in prior:
        if isinstance(row,dict):
            rows.setdefault(identity(row),row)
    return list(rows.values())[:30],max(0,len(rows)-30)


def merge(discovered, verified):
    result = {identity(r): {**r,'verificacion_pendiente':False} for r in verified if isinstance(r,dict)}
    for row in discovered:
        if isinstance(row,dict) and identity(row) not in result:
            result[identity(row)] = {**row,'cercania':'PENDIENTE','verificacion_pendiente':True,'motivo':'Pendiente de verificación; no fue resuelto en la revisión.'}
    return list(result.values())[:30]


def classify(candidates, period, sources, proximity=None):
    start,end = map(date.fromisoformat, period)
    rows = {}
    for source in candidates[:30]:
        if not isinstance(source,dict) or not isinstance(source.get('nombre'),str) or not source['nombre'].strip():
            continue
        row = {k:str(v or '')[:800] for k,v in source.items() if isinstance(v,(str,int,float))}
        row['verificacion_pendiente']=source.get('verificacion_pendiente') is True
        row['url_verificada']=row.get('url') in sources
        for key in ('distancia_m','radio_m','fuente_mapa','lat','lon','geografia'):
            row.pop(key,None)
        geo=(proximity or {}).get('venues',{}).get(identity(row),{})
        row['cercania']='ACREDITADA' if geo.get('estado')=='DENTRO' else 'PENDIENTE'
        row['sustento_cercania']=''
        if geo.get('estado') in ('DENTRO','FUERA'):
            row.update(distancia_m=geo['distancia_m'],radio_m=proximity['radius_m'],fuente_mapa=geo.get('url',''))
            row['sustento_cercania']=f"Aprox. {geo['distancia_m']} m en línea recta; radio {proximity['radius_m']} m."
            if geo.get('incertidumbre_m'):
                row['sustento_cercania']+=f" Margen cartográfico {geo['incertidumbre_m']} m."
        decision,reason = 'PENDIENTE','Faltan evidencias de fecha, ubicación, acceso o vigencia.'
        try:
            first = date.fromisoformat(row.get('fecha_desde',''))
            last = date.fromisoformat(row.get('fecha_hasta') or row['fecha_desde'])
            valid_dates = first <= last
        except ValueError:
            valid_dates = False
        missing = []
        if row['verificacion_pendiente']:
            missing.append('revisión del candidato')
        if not valid_dates:
            missing.append('fechas válidas')
        if row.get('url') not in sources or row.get('fuente_fecha') not in sources:
            missing.append('fuente consultada de fecha/año')
        if row.get('fuente_ubicacion') not in sources:
            missing.append('fuente consultada de ubicación')
        if row.get('cercania')!='ACREDITADA' or not row.get('sustento_cercania','').strip() or not row.get('direccion','').strip():
            missing.append('cercanía sustentada')
        if row.get('acceso') not in ('PUBLICO','INSCRIPCION'):
            missing.append('acceso público o con inscripción')
        if row.get('estado')!='ACTIVO':
            missing.append('vigencia')
        if row.get('relevancia')!='POTENCIAL':
            missing.append('relevancia para el bar')
        reason = 'Por confirmar: '+', '.join(missing)+'.' if missing else reason
        if row.get('estado')=='CANCELADO':
            decision,reason = 'DESCARTADO','Cancelación publicada.'
        elif valid_dates and (last < start or first > end):
            decision,reason = 'DESCARTADO','Fuera del período solicitado.'
        elif row.get('acceso')=='RESTRINGIDO':
            decision,reason = 'DESCARTADO','Acceso restringido; no se considera una oportunidad de público para el bar.'
        elif geo.get('estado')=='FUERA':
            decision,reason='DESCARTADO',row['sustento_cercania']+' Fuera del radio; solo contexto de ciudad.'
        elif row.get('relevancia')=='BAJA':
            decision,reason = 'DESCARTADO','Relevancia insuficiente para el bar.'
        elif (valid_dates and row.get('url') in sources and row.get('fuente_fecha') in sources
              and not row['verificacion_pendiente']
              and row.get('fuente_ubicacion') in sources and row.get('cercania')=='ACREDITADA'
              and row.get('sustento_cercania','').strip() and row.get('direccion','').strip()
              and row.get('estado')=='ACTIVO' and row.get('relevancia')=='POTENCIAL'
              and row.get('acceso') in ('PUBLICO','INSCRIPCION')):
            decision,reason = 'INCLUIDO',row['sustento_cercania']
        row.update(decision=decision,motivo=reason + (' '+row['motivo'] if row.get('motivo') else ''))
        key = identity(row)
        if key not in rows or {'INCLUIDO':0,'PENDIENTE':1,'DESCARTADO':2}[decision] < {'INCLUIDO':0,'PENDIENTE':1,'DESCARTADO':2}[rows[key]['decision']]:
            rows[key] = row
    return sorted(rows.values(), key=lambda r:(r.get('fecha_desde','9999'),normalized(r['nombre'])))


def cell(value):
    value = re.sub(r'[\r\n|]+',' ',str(value or 'No publicado')).replace('[','(').replace(']',')')
    return value if len(value)<=220 else value[:217].rstrip()+'…'


def link(row):
    url = row.get('url','')
    if row.get('url_verificada') is not False and re.fullmatch(r'https?://[^\s()<>]+',url):
        return f'[{cell(row["nombre"])}]({url})'
    return cell(row['nombre'])


def event_cells(row):
    def day(value):
        try:
            value=date.fromisoformat(value)
            return ('Lun.','Mar.','Mié.','Jue.','Vie.','Sáb.','Dom.')[value.weekday()]+f' {value.day} '+('ene.','feb.','mar.','abr.','may.','jun.','jul.','ago.','sep.','oct.','nov.','dic.')[value.month-1]
        except (ValueError,TypeError):
            return 'Fecha por confirmar'
    when=day(row.get('fecha_desde'))
    if row.get('fecha_hasta') and row['fecha_hasta']!=row.get('fecha_desde'):
        when+=' al '+day(row['fecha_hasta'])
    hour=row.get('hora') or 'Hora por confirmar'
    if re.search(r'no corrobor|no verific|no confirm|no publicad',normalized(hour)):
        hour='Hora por confirmar'
    distance_note=f" · aprox. {float(row['distancia_m'])/1000:.1f} km" if row.get('distancia_m') is not None else ''
    name=link(row)+(' · Por confirmar' if row.get('decision')=='PENDIENTE' else '')
    if row.get('decision')=='PENDIENTE' and row.get('motivo'):
        name+=' · '+re.sub(r'^Por confirmar:\s*','Falta verificar: ',cell(row['motivo']),flags=re.I)
    proximity_note=' · Cercanía sin confirmar' if row.get('cercania')!='ACREDITADA' and row.get('decision')!='DESCARTADO' else ''
    return [cell(when+' · '+hour),name,cell(row.get('tipo')),cell(row.get('recinto'))+distance_note+proximity_note]


def nearby_visible(row):
    return row['decision']!='DESCARTADO' and row.get('relevancia')!='BAJA'


def render(rows):
    visible=[r for r in rows if nearby_visible(r)]
    lines=['| Día | Evento publicado | Tipo | Lugar |','| --- | --- | --- | --- |']
    lines+=['| '+' | '.join(event_cells(r))+' |' for r in visible]
    if not visible:
        lines+=['','Sin eventos pertinentes encontrados para este período. Consulta la revisión de eventos.']
    return '\n'.join(lines)


def render_details(rows):
    reviewed = [r for r in rows if not nearby_visible(r)]
    lines=[]
    if reviewed:
        lines += ['| Día | Evento publicado | Tipo | Lugar | Motivo |','| --- | --- | --- | --- | --- |']
        for row in reviewed:
            lines.append('| '+' | '.join(event_cells(row)+[cell(row.get('motivo'))])+' |')
    return '\n'.join(lines)


def pending_report(prior, reason):
    rows = classify(merge(prior.get('candidatos',[]),[]),prior['periodo'],set())
    return {**prior,'estado':'parcial','candidatos':rows,
            'informe':reason+' Se conservan los candidatos anteriores sin considerarlos revalidados.\n\n'+render(rows),'detalle':render_details(rows)}


def unpack(response):
    texts,urls = [],set()
    for item in response.get('output',[]):
        if item.get('type')=='web_search_call':
            urls.update(s['url'] for s in (item.get('action') or {}).get('sources',[]) if isinstance(s.get('url'),str))
        for content in item.get('content',[]):
            if content.get('type')=='output_text':
                texts.append(content.get('text',''))
                urls.update(a['url'] for a in content.get('annotations',[]) if a.get('type')=='url_citation' and isinstance(a.get('url'),str))
    raw = '\n'.join(texts).strip()
    raw = re.sub(r'^```(?:json)?\s*|\s*```$','',raw).strip()
    try:
        data=json.loads(raw)
        if isinstance(data,dict) and isinstance(data.get('candidatos'),list):
            return data,urls
    except (ValueError,TypeError):
        pass
    # Recover only complete JSON objects from a truncated candidate array.
    # Never repair an unfinished object or infer any missing evidence.
    start=re.search(r'"candidatos"\s*:\s*\[',raw)
    if start:
        decoder=json.JSONDecoder()
        index=start.end()
        recovered=[]
        while len(recovered)<30:
            while index<len(raw) and raw[index].isspace():
                index+=1
            try:
                row,index=decoder.raw_decode(raw,index)
            except ValueError:
                break
            if not isinstance(row,dict):
                break
            recovered.append(row)
            while index<len(raw) and raw[index].isspace():
                index+=1
            if index>=len(raw) or raw[index]!=',':
                break
            index+=1
        if recovered:
            return {'candidatos':recovered,'limitaciones':'Respuesta cortada; se recuperaron únicamente los candidatos completos.','_partial':True},urls
    return None,urls


def cache_key(location,period,intent):
    intent = normalized(intent)
    intent = re.sub(r'\breintentar eventos\b[.\s]*','',intent)
    intent = re.sub(r'periodo de eventos confirmado:\s*del \d{4}-\d{2}-\d{2} al \d{4}-\d{2}-\d{2}[.\s]*','',intent)
    intent = re.sub(r'^eventos del \d{4}-\d{2}-\d{2} al \d{4}-\d{2}-\d{2}\.\s*','',intent)
    intent = re.sub(r'\s+',' ',intent).strip()
    from .geography import radius
    return hashlib.sha256(json.dumps(['v10-venue-batches-sources',radius(),location,period,intent],sort_keys=True,ensure_ascii=False).encode()).hexdigest()


def path(key):
    if not has_app_context() or current_app.testing:
        return None
    return Path(current_app.instance_path)/'event_research'/(key+'.json')


def cached(key, stale=False):
    target = path(key)
    if target is None:
        return None
    try:
        value=json.loads(target.read_text(encoding='utf-8'))
        if 0 <= time.time()-value['created'] < (86400 if stale else 1800):
            return value['report']
    except (OSError,ValueError,KeyError,TypeError):
        pass
    return None


def save(key,report):
    target = path(key)
    if target is None or report.get('estado')!='consultado' or not report.get('candidatos'):
        return
    temporary=None
    try:
        target.parent.mkdir(parents=True,exist_ok=True)
        with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=target.parent,delete=False) as file:
            temporary=file.name
            json.dump({'created':time.time(),'report':report},file,ensure_ascii=False)
        os.replace(temporary,target)
    except OSError:
        pass
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
