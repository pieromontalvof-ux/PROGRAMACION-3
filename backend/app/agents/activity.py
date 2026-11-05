"""Server-recorded execution events, never model reasoning or prompts."""
from contextvars import ContextVar
from datetime import datetime, timezone
from functools import wraps
import inspect
import json
import os
from pathlib import Path
import re
from uuid import UUID, uuid4
from flask import current_app, request
from app.modules.asistente_ia.provider import AssistantError

_current=ContextVar('agent_activity',default=None)
SECRET=re.compile(r'password|contras|secret|token|authorization|api.?key|continuacion|flujo_compra',re.I)

def now():return datetime.now(timezone.utc).isoformat()
def scrub(value,limit=1500):
    return re.sub(r'\bsk-[\w-]+|Bearer\s+\S+','[oculto]',str(value))[:limit]
def safe(value,depth=0):
    if depth>3:return '[resumen]'
    if isinstance(value,dict):return {str(k):safe(v,depth+1) for k,v in list(value.items())[:20] if not SECRET.search(str(k))}
    if isinstance(value,(list,tuple)):return [safe(x,depth+1) for x in value[:5]]
    if isinstance(value,str):return scrub(value)
    if value is None or isinstance(value,(int,float,bool)):return value
    return str(value)[:200]

def scope():
    from app.modules.asistente_ia.drafts import scope as actual
    return actual()

def folder(owner):
    root=current_app.config.get('APP_DATA_DIR') or os.environ.get('APP_DATA_DIR') or current_app.instance_path
    return Path(root)/'agent_activity'/('-'.join(str(int(owner[k] or 0)) for k in ('usuario','perfil','local')))

def begin(instruction,owner):
    url=request.base_url
    forwarded=request.headers.get('X-Forwarded-Proto','').split(',')[0].strip()
    if forwarded in ('http','https'):
        url=url.replace(request.scheme+'://',forwarded+'://',1)
    state={'id':str(uuid4()),'inicio':now(),'entrada':scrub(instruction,8000),'url':url,
           'scope':owner,'agentes':['orquestador'],'eventos':[],'actual':'orquestador','truncada':False}
    token=_current.set(state)
    emit('agente_inicio',agente='orquestador',mensaje='El Coordinador recibe la solicitud y evalúa su ruta.')
    return token

def reset(token):_current.reset(token)

def emit(kind,**data):
    state=_current.get()
    if state is None:return
    if len(state['eventos'])>=100:
        state['truncada']=True;return
    state['eventos'].append({'paso':len(state['eventos'])+1,'fecha':now(),'tipo':kind,
                            'agente':state['actual'],**safe(data)})

def agent(identity):
    def decorate(fn):
        @wraps(fn)
        def wrapped(*args,**kwargs):
            state=_current.get()
            selected=identity(*args,**kwargs) if callable(identity) else identity
            if state is None or state['actual']==selected:return fn(*args,**kwargs)
            parent=state['actual']
            bound=inspect.signature(fn).bind_partial(*args,**kwargs).arguments
            task=bound.get('instruction','')
            emit('delegacion',de=parent,a=selected,mensaje=task)
            if selected not in state['agentes']:state['agentes'].append(selected)
            state['actual']=selected
            emit('agente_inicio',mensaje='Inicio de la tarea delegada.')
            try:
                result=fn(*args,**kwargs)
                emit('agente_fin',mensaje=(result or {}).get('respuesta','Tarea completada.'))
                emit('retorno',de=selected,a=parent,mensaje=(result or {}).get('respuesta',''))
                return result
            except Exception:
                emit('agente_error',mensaje='La tarea del especialista no se completó.');raise
            finally:state['actual']=parent
        return wrapped
    return decorate

def tool(name):
    def decorate(fn):
        @wraps(fn)
        def wrapped(*args,**kwargs):
            if _current.get() is None:return fn(*args,**kwargs)
            bound=inspect.signature(fn).bind_partial(*args,**kwargs).arguments
            parameters={k:v for k,v in bound.items() if k not in ('session','sesion')}
            emit('herramienta_inicio',herramienta=name,parametros=parameters)
            try:
                result=fn(*args,**kwargs)
                # Keep useful bounded outputs, not raw user lists or credentials.
                summary={k:v for k,v in result.items() if k in ('recurso','total','desde','hay_mas','mensaje','diagnostico','porcentaje_incremento')} if isinstance(result,dict) else {'tipo':type(result).__name__}
                if isinstance(result,dict):
                    for k in ('registros','productos','articulos'):
                        if isinstance(result.get(k),list):summary[k+'_devueltos']=len(result[k])
                emit('herramienta_fin',herramienta=name,resultado=summary,estado='completada')
                return result
            except Exception:
                emit('herramienta_fin',herramienta=name,estado='error',mensaje='La herramienta no completó la operación.');raise
        return wrapped
    return decorate

def finish(payload,status=200):
    state=_current.get()
    if state is None:return None
    # Invalid bodies and rate-limit rejections never started an execution.
    if status >= 400 and len(state['eventos']) <= 1:
        return None
    emit('respuesta_final',mensaje=payload.get('respuesta') or payload.get('mensaje',''))
    trace={k:v for k,v in state.items() if k not in ('scope','actual')}
    trace.update(fin=now(),estado='completada' if status<400 else 'error',respuesta_final=scrub(payload.get('respuesta') or payload.get('mensaje',''),16000),
                 nota='Actividad registrada por el servidor; mensajes, parámetros y resultados resumidos. No incluye razonamiento interno.')
    if len(str(payload.get('respuesta') or payload.get('mensaje',''))) > 16000:
        trace['truncada'] = True
    try:
        target=folder(state['scope']);target.mkdir(parents=True,exist_ok=True)
        path=target/(trace['id']+'.json');temporary=path.with_suffix('.tmp')
        temporary.write_text(json.dumps(trace,ensure_ascii=False,default=str),encoding='utf-8');temporary.replace(path)
    except OSError:
        current_app.logger.warning('agent_activity persistence_unavailable id=%s',trace['id'])
        return None
    current_app.logger.info('agent_activity id=%s agentes=%s estado=%s',trace['id'],','.join(trace['agentes']),trace['estado'])
    return trace

def load(identity):
    try:identity=str(UUID(identity))
    except (ValueError,TypeError,AttributeError):raise AssistantError('Traza inválida.',400) from None
    path=folder(scope())/(identity+'.json')
    if not path.is_file():raise AssistantError('No hay actividad disponible para este perfil y local.',404)
    return json.loads(path.read_text(encoding='utf-8'))
