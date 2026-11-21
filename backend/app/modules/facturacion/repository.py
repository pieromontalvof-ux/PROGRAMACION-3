"""PostgreSQL outbox and fenced leases; never holds a DB transaction during HTTP."""
import hashlib
import json
from uuid import uuid4
from sqlalchemy import text
from app.core.extensions import db


def installed():
    return db.session.execute(text("SELECT to_regclass('public.fact_api_operacion') IS NOT NULL")).scalar() is True


def enqueue(local, origin, source, payload):
    encoded = json.dumps(payload, sort_keys=True, separators=(',',':'), ensure_ascii=False)
    digest = hashlib.sha256(encoded.encode()).hexdigest()
    # Serializes duplicate submissions and revisions of the same source.
    db.session.execute(text('SELECT pg_advisory_xact_lock(hashtext(:key))'), {'key': f'fact:{origin}:{source}'})
    previous = db.session.execute(text('''SELECT * FROM fact_api_operacion
        WHERE origen=:origin AND id_origen=:source ORDER BY version DESC LIMIT 1'''),
        {'origin':origin,'source':source}).mappings().first()
    if previous and previous['payload_hash']==digest:
        return str(previous['id_operacion'])
    db.session.execute(text('''UPDATE fact_api_operacion SET obsoleto=true,
        estado=CASE WHEN estado='COMPLETADO' THEN estado ELSE 'BLOQUEADO' END,
        lease_token=NULL,lease_hasta=NULL,actualizado_en=now(),
        ultimo_error='Existe una versión más reciente de la fuente'
        WHERE origen=:origin AND id_origen=:source'''),{'origin':origin,'source':source})
    db.session.execute(text('''UPDATE fact_api_intento i SET fin=now(),resultado='FUENTE_MODIFICADA'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.origen=:origin AND o.id_origen=:source AND o.obsoleto'''),{'origin':origin,'source':source})
    identity = str(uuid4())
    db.session.execute(text('''INSERT INTO fact_api_operacion
        (id_operacion,id_local,origen,id_origen,version,payload,payload_hash)
        VALUES(:id,:local,:origin,:source,:version,CAST(:payload AS jsonb),:hash)'''),
        {'id':identity,'local':local,'origin':origin,'source':source,'version':previous['version']+1 if previous else 1,
         'payload':encoded,'hash':digest})
    return identity


def claim():
    token = str(uuid4())
    row = db.session.execute(text('''WITH job AS (
        SELECT id_operacion FROM fact_api_operacion
        WHERE NOT obsoleto AND intentos<max_intentos AND ((estado IN ('PENDIENTE','REINTENTO') AND disponible_en<=now())
          OR (estado='PROCESANDO' AND lease_hasta<now()))
          AND NOT EXISTS(SELECT 1 FROM fact_api_circuito WHERE abierto_hasta>now())
        ORDER BY creado_en FOR UPDATE SKIP LOCKED LIMIT 1
    ) UPDATE fact_api_operacion o SET estado='PROCESANDO',intentos=intentos+1,
        lease_hasta=now()+interval '3 minutes',lease_token=CAST(:token AS uuid),actualizado_en=now()
        FROM job WHERE o.id_operacion=job.id_operacion RETURNING o.*'''), {'token':token}).mappings().first()
    # Exhausted workers that died are visible, never left permanently processing.
    db.session.execute(text("""UPDATE fact_api_operacion SET estado='REVISION',lease_token=NULL,
        ultimo_error='Intentos agotados; conciliar con el mismo identificador',actualizado_en=now()
        WHERE estado='PROCESANDO' AND lease_hasta<now() AND intentos>=max_intentos"""))
    db.session.execute(text('''UPDATE fact_api_intento i SET fin=now(),resultado='LEASE_VENCIDO'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.estado='REVISION' AND o.intentos>=o.max_intentos'''))
    if row:
        db.session.execute(text('''UPDATE fact_api_intento SET fin=now(),resultado='LEASE_VENCIDO'
            WHERE id_operacion=:id AND fin IS NULL'''), {'id':row['id_operacion']})
        db.session.execute(text('''INSERT INTO fact_api_intento(id_operacion,numero)
            VALUES(:id,:number)'''), {'id':row['id_operacion'],'number':row['intentos']})
    db.session.commit()
    return dict(row) if row else None


def finish(job, state, status, duration, error=None, delay=0, document=None, files=()):
    params = {'id':str(job['id_operacion']),'lease':str(job['lease_token']), 'state':state,
              'status':status,'duration':duration,'error':error,'delay':delay,'number':job['intentos']}
    owned = db.session.execute(text('''SELECT id_operacion FROM fact_api_operacion
        WHERE id_operacion=:id AND lease_token=:lease AND estado='PROCESANDO' FOR UPDATE'''),params).scalar()
    if not owned:
        db.session.rollback()
        return False
    if document:
        doc_id = str(job['id_operacion'])
        db.session.execute(text('''INSERT INTO fact_api_documento
            (id_documento,id_operacion,id_local,id_externo,numero,estado,subtotal,igv,total)
            VALUES(:id,:id,:local,:external,:numero,'DEMO_GENERADO',:subtotal,:igv,:total)
            ON CONFLICT(id_operacion) DO NOTHING'''),
            {**params,'local':job['id_local'],'external':document['id'], 'numero':document['numero'],
             'subtotal':job['payload']['subtotal'],'igv':job['payload']['igv'],'total':job['payload']['total']})
        for file in files:
            db.session.execute(text('''INSERT INTO fact_api_archivo
                (id_archivo,id_documento,formato,ruta,sha256,bytes)
                VALUES(:file,:id,:format,:path,:hash,:size) ON CONFLICT(id_documento,formato) DO NOTHING'''),
                {'file':str(uuid4()),'id':doc_id,**file})
    db.session.execute(text('''UPDATE fact_api_operacion SET estado=:state,ultimo_http=:status,
        ultimo_error=:error,disponible_en=now()+make_interval(secs=>CAST(:delay AS double precision)),
        lease_hasta=NULL,lease_token=NULL,actualizado_en=now() WHERE id_operacion=:id'''),params)
    db.session.execute(text('''UPDATE fact_api_intento SET fin=now(),duracion_ms=:duration,
        http_status=:status,resultado=:state WHERE id_operacion=:id AND numero=:number'''),params)
    if status>=500 or status==429:
        db.session.execute(text('''UPDATE fact_api_circuito SET fallos=fallos+1,
            abierto_hasta=CASE WHEN fallos>=2 THEN now()+interval '30 seconds' ELSE abierto_hasta END WHERE id=1'''))
    elif state=='COMPLETADO':
        db.session.execute(text('UPDATE fact_api_circuito SET fallos=0,abierto_hasta=NULL WHERE id=1'))
    db.session.commit()
    return True
