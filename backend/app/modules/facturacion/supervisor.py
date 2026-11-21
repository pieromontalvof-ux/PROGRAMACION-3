"""Single PostgreSQL leader owns a bounded set of worker child processes."""
from dataclasses import dataclass
import json
import logging
import os
from pathlib import Path
import subprocess
import sys
import time
from uuid import uuid4
from sqlalchemy import text
from app.core.extensions import db
from .scaling import ScalingPolicy

log=logging.getLogger(__name__)
LOCK=(207414,1)


def queue_stats():
    row=db.session.execute(text('''SELECT
        count(*) FILTER(WHERE (estado IN ('PENDIENTE','REINTENTO') AND disponible_en<=now())
            OR (estado='PROCESANDO' AND lease_hasta<now())) AS ready,
        count(*) FILTER(WHERE estado='PROCESANDO' AND lease_hasta>=now()) AS busy,
        COALESCE(extract(epoch FROM now()-min(disponible_en) FILTER(WHERE estado IN ('PENDIENTE','REINTENTO')
            AND disponible_en<=now())),0) AS oldest,
        EXISTS(SELECT 1 FROM fact_api_circuito WHERE abierto_hasta>now()) AS blocked
        FROM fact_api_operacion WHERE NOT obsoleto AND (intentos<max_intentos
            OR (estado='PROCESANDO' AND lease_hasta>=now()))''')).mappings().one()
    # A cap/timeout is a reason to wait, never a reason to multiply traffic.
    health=db.session.execute(text('''SELECT count(*) AS total,
        count(*) FILTER(WHERE http_status=429 OR http_status>=500) AS bad
        FROM fact_api_intento WHERE inicio>now()-interval '60 seconds' AND fin IS NOT NULL''')).mappings().one()
    db.session.commit()
    return {'ready':row['ready'],'busy':row['busy'],'oldest':float(row['oldest']),
            'blocked':bool(row['blocked']),'unhealthy':health['bad']>=2 and health['bad']/max(health['total'],1)>=.25}


def acquire_leadership():
    connection=db.engine.connect().execution_options(isolation_level='AUTOCOMMIT')
    try:
        acquired=connection.execute(text('SELECT pg_try_advisory_lock(:group,:identity)'),
            {'group':LOCK[0],'identity':LOCK[1]}).scalar()
        if not acquired:
            connection.close();return None
        return connection
    except Exception:
        connection.close();raise


def release_leadership(connection):
    try:
        connection.execute(text('SELECT pg_advisory_unlock(:group,:identity)'),
            {'group':LOCK[0],'identity':LOCK[1]})
    finally:
        # Session locks must never survive a return to SQLAlchemy's pool.
        connection.invalidate();connection.close()


def acquire_worker_slot():
    """Hard cap across manual, orphaned and replacement-supervisor workers."""
    connection=db.engine.connect().execution_options(isolation_level='AUTOCOMMIT')
    try:
        for slot in range(4):
            if connection.execute(text('SELECT pg_try_advisory_lock(:group,:slot)'),
                    {'group':LOCK[0],'slot':100+slot}).scalar():
                pid=connection.execute(text('SELECT pg_backend_pid()')).scalar_one()
                return connection,pid
        connection.close();return None
    except Exception:
        connection.invalidate();connection.close();raise


def release_worker_slot(connection):
    # Invalidate rather than pool a PostgreSQL session with a worker slot lock.
    connection.invalidate();connection.close()


def owns_epoch(identity):
    owned=db.session.execute(text('''SELECT EXISTS(SELECT 1 FROM fact_api_escalado
        WHERE id=1 AND supervisor=:id AND actualizado_en>now()-interval '20 seconds')'''),{'id':identity}).scalar()
    db.session.commit()
    return bool(owned)


@dataclass
class Child:
    process: object
    stop: Path
    output: object
    retiring: bool=False


class Supervisor:
    def __init__(self,runtime,policy=None,*,clock=time.monotonic,spawn=subprocess.Popen):
        self.runtime=Path(runtime).resolve()
        self.policy=policy or ScalingPolicy()
        self.clock=clock;self.spawn=spawn
        self.identity=str(uuid4());self.children=[];self.last_spawn=None

    def reap(self):
        for child in list(self.children):
            if child.process.poll() is not None:
                child.output.close();child.stop.unlink(missing_ok=True);self.children.remove(child)
                log.info('fact_api worker_exited pid=%s',child.process.pid)

    def start(self):
        self.runtime.mkdir(parents=True,exist_ok=True)
        identity=str(uuid4())
        stop=self.runtime/(identity+'.stop')
        output=(self.runtime/(identity+'.log')).open('ab')
        script=Path(__file__).resolve().parents[3]/'scripts/run_fact_api_worker.py'
        try:
            process=self.spawn([sys.executable,str(script),'--stop-file',str(stop),'--supervisor-id',self.identity],
                cwd=str(script.parent.parent),stdin=subprocess.DEVNULL,stdout=output,stderr=output,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        except Exception:
            output.close();raise
        self.children.append(Child(process,stop,output));self.last_spawn=self.clock()
        log.info('fact_api worker_started pid=%s',process.pid)

    def tick(self,stats):
        self.reap()
        current=len(self.children)
        desired=self.policy.decide(current,now=self.clock(),**stats)
        # Do not replace a retiring worker until it actually finishes and exits.
        # Back off if a child repeatedly crashes during startup.
        can_spawn=self.last_spawn is None or self.clock()-self.last_spawn>=self.policy.grow_seconds
        if desired>current and can_spawn:
            for _ in range(desired-current):self.start()
        elif desired<current and not any(c.retiring for c in self.children):
            child=self.children[-1];child.stop.touch();child.retiring=True
            log.info('fact_api worker_retiring pid=%s',child.process.pid)
        return min(desired,len(self.children)-sum(c.retiring for c in self.children))

    def heartbeat(self,stats,desired):
        db.session.execute(text('''INSERT INTO fact_api_escalado
            (id,supervisor,pid,minimo,maximo,activos,objetivo,listos,ocupados,espera_segundos,pausado,workers,actualizado_en)
            VALUES(1,:id,:pid,:minimum,:maximum,:active,:desired,:ready,:busy,:oldest,:paused,CAST(:workers AS jsonb),now())
            ON CONFLICT(id) DO UPDATE SET supervisor=EXCLUDED.supervisor,pid=EXCLUDED.pid,
            minimo=EXCLUDED.minimo,maximo=EXCLUDED.maximo,activos=EXCLUDED.activos,objetivo=EXCLUDED.objetivo,
            listos=EXCLUDED.listos,ocupados=EXCLUDED.ocupados,espera_segundos=EXCLUDED.espera_segundos,
            pausado=EXCLUDED.pausado,workers=EXCLUDED.workers,actualizado_en=now()'''),
            {'id':self.identity,'pid':os.getpid(),'minimum':self.policy.minimum,'maximum':self.policy.maximum,
             'active':len(self.children),'desired':desired,'ready':stats['ready'],'busy':stats['busy'],
             'oldest':stats['oldest'],'paused':stats['blocked'] or stats['unhealthy'],
             'workers':json.dumps([{'pid':c.process.pid,'retirando':c.retiring} for c in self.children])})
        db.session.commit()

    def retire_all(self):
        for child in self.children:
            child.stop.touch();child.retiring=True

    def wait_for_retirement(self):
        self.retire_all()
        while self.children:
            self.reap()
            if self.children:time.sleep(.5)
