"""One worker may be replicated. PostgreSQL leases fence late responses."""
from datetime import date, datetime, timedelta, timezone
import hashlib
import logging
import os
from pathlib import Path, PureWindowsPath
import random
import re
from time import perf_counter
from uuid import UUID, uuid4
from flask import current_app
from app.core.extensions import db
from . import repository as repo
from .policy import outcome, next_retry
from .transport import call, ApiError

log = logging.getLogger(__name__)


def storage_root():
    return Path(os.getenv('FACT_API_DOCUMENTS_DIR') or Path(current_app.instance_path)/'fact_api_documents').resolve()


def carpeta_documentos(fecha, local, categoria, nombre_local=None):
    sede = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '-', nombre_local or '').strip(' .')
    if not sede or PureWindowsPath(sede).is_reserved():
        sede = f'local-{local}'
    return Path(f'{fecha.year:04d}', f'{fecha.month:02d}', f'{fecha.day:02d}', sede, categoria)


def fecha_local(moment=None):
    lima = timezone(timedelta(hours=-5))
    if moment is None:
        moment = datetime.now(lima)
    return moment.astimezone(lima).date() if moment.tzinfo else moment.date()


def persist_pdf(job, format, data, numero=None):
    payload = job.get('payload') or {}
    fecha = date.fromisoformat(payload['fecha']) if payload.get('fecha') else fecha_local(job.get('creado_en'))
    if job['origen'] == 'COMPRA':
        categoria = 'facturas-de-compra'
    elif payload.get('tipo') == '01':
        categoria = 'facturas'
    elif (payload.get('tercero') or {}).get('documento'):
        categoria = 'boletas-electronicas'
    else:
        categoria = 'boletas'

    nombre = f'{numero}_{format}' if isinstance(numero, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,80}', numero) else format
    relative = (carpeta_documentos(fecha, job['id_local'], categoria, job.get('nombre_local'))
                / str(job['id_operacion']) / str(job['lease_token']) / f'{nombre}.pdf')
    path = storage_root()/relative
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.'+str(uuid4())+'.tmp')
    temporary.write_bytes(data)
    temporary.replace(path)
    return {'format':format,'path':relative.as_posix(),'hash':hashlib.sha256(data).hexdigest(),'size':len(data)}


def process_one():
    job = repo.claim()
    if not job:
        return False
    started = perf_counter()
    identity = str(job['id_operacion'])
    try:
        job['nombre_local'] = repo.nombre_local(job['id_local'])
        db.session.rollback()  # Release the read transaction before remote I/O.
        # POST is safe even if a previous worker died after the remote commit.
        result = call('documents', job['payload'], identity)
        if (str(UUID(result['id']))!=identity or result.get('estado')!='DEMO_GENERADO'
                or result.get('payload_hash')!=job['payload_hash'] or not isinstance(result.get('numero'),str)):
            raise ApiError(502)
        files = [persist_pdf(job, format, call('documents/'+identity+'/pdf?format='+format,
                                             operation=identity, binary=True), numero=result['numero']) for format in ('A4','80mm')]
        saved=repo.finish(job,'COMPLETADO',200,(perf_counter()-started)*1000,document=result,files=files)
        log.info('fact_api operation=%s state=%s attempts=%s',identity,'COMPLETADO' if saved else 'TURNO_VENCIDO',job['intentos'])
    except ApiError as error:
        state = outcome(error.status)
        if state=='REINTENTO' and job['intentos']>=job['max_intentos']:
            state='REVISION'
        delay=max(error.retry_after,next_retry(job['intentos'],random.random()))
        repo.finish(job,state,error.status,(perf_counter()-started)*1000,
                    error=f'HTTP {error.status}; revisar operación {identity}',delay=delay)
        log.warning('fact_api operation=%s state=%s http=%s',identity,state,error.status)
    except (ValueError, KeyError, TypeError, OSError):
        repo.finish(job,'REVISION',502,(perf_counter()-started)*1000,
                    error='Respuesta o almacenamiento no válido; conciliar con el mismo identificador')
    return True
