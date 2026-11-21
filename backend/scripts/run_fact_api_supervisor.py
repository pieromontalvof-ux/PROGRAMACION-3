"""Automatically grow/shrink local workers; singleton lock is held until retirement."""
import argparse
import os
from pathlib import Path
import signal
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import create_app
from app.core.extensions import db
from app.modules.facturacion.scaling import ScalingPolicy
from app.modules.facturacion.supervisor import Supervisor,queue_stats,acquire_leadership,release_leadership
from sqlalchemy import text


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--min-workers',type=int,default=int(os.getenv('FACT_API_MIN_WORKERS','1')))
    parser.add_argument('--max-workers',type=int,default=int(os.getenv('FACT_API_MAX_WORKERS','4')))
    parser.add_argument('--stop-file',type=Path)
    parser.add_argument('--once',action='store_true')
    args=parser.parse_args()
    policy=ScalingPolicy(minimum=args.min_workers,maximum=args.max_workers)
    app=create_app();stopping=False
    def stop(*_):
        nonlocal stopping
        stopping=True
    signal.signal(signal.SIGINT,stop);signal.signal(signal.SIGTERM,stop)
    with app.app_context():
        leader=acquire_leadership()
        if leader is None:
            print('Ya existe un supervisor fact_api en esta base.',flush=True);return 2
        backend_pid=leader.execute(text('SELECT pg_backend_pid()')).scalar_one()
        manager=Supervisor(Path(app.instance_path)/'fact_api_workers',policy)
        print(f'Workers automáticos: mínimo {policy.minimum}, máximo {policy.maximum}.',flush=True)
        try:
            manager.heartbeat({'ready':0,'busy':0,'oldest':0,'blocked':False,'unhealthy':False},policy.minimum)
            while not stopping and not (args.stop_file and args.stop_file.exists()):
                # A reconnected session no longer owns the original advisory lock.
                if leader.execute(text('SELECT pg_backend_pid()')).scalar_one()!=backend_pid:
                    raise RuntimeError('Se perdió la sesión de liderazgo.')
                stats=queue_stats();desired=manager.tick(stats);manager.heartbeat(stats,desired)
                if args.once:break
                for _ in range(10):
                    if stopping or (args.stop_file and args.stop_file.exists()):break
                    time.sleep(.5)
        finally:
            manager.wait_for_retirement()
            try:
                db.session.execute(text('''UPDATE fact_api_escalado SET activos=0,objetivo=0,workers='[]',
                    actualizado_en=now() WHERE supervisor=:id'''),{'id':manager.identity});db.session.commit()
            finally:
                release_leadership(leader)
    return 0


if __name__=='__main__':sys.exit(main())
