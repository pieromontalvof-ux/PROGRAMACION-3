"""Run one durable worker. Start another process for additional concurrency."""
import argparse
from pathlib import Path
import sys
import time
from uuid import UUID
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import create_app
from app.core.extensions import db
from app.modules.facturacion.worker import process_one
from app.modules.facturacion.scaling import worker_loop
from app.modules.facturacion.supervisor import acquire_worker_slot,release_worker_slot,owns_epoch
from sqlalchemy import func, select


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--once',action='store_true')
    parser.add_argument('--stop-file',type=Path)
    parser.add_argument('--supervisor-id',type=UUID)
    args=parser.parse_args()
    app=create_app()
    slot=None
    def stopping():
        if args.stop_file and args.stop_file.exists():return True
        try:
            with app.app_context():
                if args.supervisor_id and not owns_epoch(str(args.supervisor_id)):return True
                if slot and slot[0].execute(select(func.public.facturacion_pid_conexion())).scalar_one()!=slot[1]:return True
        except Exception:
            return True  # Fail closed if ownership cannot be verified.
        return False
    def process():
        try:
            with app.app_context():
                worked=process_one()
                db.session.remove()
        except Exception:
            app.logger.error('fact_api worker: error interno; el lease permite recuperar el trabajo')
            worked=False
        return worked
    with app.app_context():
        try:
            while not stopping():
                slot=acquire_worker_slot()
                if slot:break
                if args.once:return
                time.sleep(.5)
            if slot:worker_loop(process,stop_file=args.stop_file,once=args.once,should_stop=stopping)
        finally:
            if slot:release_worker_slot(slot[0])


if __name__=='__main__':main()
