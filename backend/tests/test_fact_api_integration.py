"""Real PostgreSQL queue, enabled only by the isolated test runner."""
import os
import unittest
from uuid import uuid4
from sqlalchemy import text
from app.core.extensions import db


@unittest.skipUnless(os.getenv('LOCAL_SCOPE_TEST_DB')=='1','PostgreSQL aislado')
class QueueTests(unittest.TestCase):
    def setUp(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        self.files=TemporaryDirectory()
        self.addCleanup(self.files.cleanup)
        for target in ('app.modules.facturacion.routes.storage_root','app.modules.facturacion.attachments.storage_root'):
            override=patch(target,return_value=Path(self.files.name));override.start();self.addCleanup(override.stop)
        from app import create_app
        self.app=create_app()
        self.app.config['JWT_SECRET_KEY']='fact-api-integration-test-secret-over-32-characters'
        self.ctx=self.app.app_context();self.ctx.push()
        migration=Path(__file__).resolve().parents[2]/'database/migrations/20261121_fact_api_queue.sql'
        db.session.execute(text(migration.read_text(encoding='utf-8').replace('BEGIN;','').replace('COMMIT;','')))
        migration=migration.with_name('20261121_fact_api_autoscale.sql')
        db.session.execute(text(migration.read_text(encoding='utf-8').replace('BEGIN;','').replace('COMMIT;','')))
        db.session.commit()
        db.session.execute(text('DELETE FROM fact_api_adjunto; DELETE FROM fact_api_archivo; DELETE FROM fact_api_documento; DELETE FROM fact_api_intento; DELETE FROM fact_api_operacion; UPDATE fact_api_circuito SET fallos=0,abierto_hasta=NULL'))
        db.session.commit()

    def tearDown(self):
        db.session.rollback();db.session.remove();self.ctx.pop()

    def test_same_payload_is_one_operation_and_revisions_are_separate(self):
        from app.modules.facturacion.repository import enqueue
        first=enqueue(1,'VENTA',1,{'x':1})
        self.assertEqual(first,enqueue(1,'VENTA',1,{'x':1}))
        self.assertNotEqual(first,enqueue(1,'VENTA',1,{'x':2}))
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM fact_api_operacion')).scalar(),2)

    def test_claim_is_exclusive_and_expired_worker_cannot_finish(self):
        from app.modules.facturacion.repository import enqueue,claim,finish
        enqueue(1,'VENTA',1,{'x':1});db.session.commit()
        first=claim()
        self.assertIsNone(claim())
        db.session.execute(text("UPDATE fact_api_operacion SET lease_hasta=now()-interval '1 minute'"));db.session.commit()
        second=claim()
        self.assertNotEqual(first['lease_token'],second['lease_token'])
        self.assertFalse(finish(first,'RECHAZADO',422,1))
        self.assertTrue(finish(second,'REINTENTO',503,2,error='HTTP 503',delay=5))
        self.assertEqual(db.session.execute(text('SELECT estado FROM fact_api_operacion')).scalar(),'REINTENTO')
        self.assertEqual(db.session.execute(text("SELECT count(*) FROM fact_api_intento WHERE fin IS NOT NULL")).scalar(),2)

    def test_rollback_does_not_leave_an_orphan_job(self):
        from app.modules.facturacion.repository import enqueue
        enqueue(1,'COMPRA',1,{'x':1});db.session.rollback()
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM fact_api_operacion')).scalar(),0)

    def test_circuit_opens_after_repeated_failures(self):
        from app.modules.facturacion.repository import enqueue,claim,finish
        for i in range(3):
            enqueue(1,'VENTA',i,{'x':i})
        db.session.commit()
        for i in range(3):
            job=claim();self.assertIsNotNone(job)
            finish(job,'REINTENTO',503,1,delay=60)
        enqueue(1,'VENTA',10,{'x':10});db.session.commit()
        self.assertIsNone(claim())

    def test_parallel_workers_claim_different_jobs(self):
        from concurrent.futures import ThreadPoolExecutor
        from app.modules.facturacion.repository import enqueue,claim
        for i in range(8):enqueue(1,'VENTA',i,{'x':i})
        db.session.commit()
        def take(_):
            with self.app.app_context():
                row=claim();db.session.remove();return str(row['id_operacion'])
        with ThreadPoolExecutor(max_workers=4) as pool:ids=list(pool.map(take,range(8)))
        self.assertEqual(len(set(ids)),8)

    def test_invalidated_sale_is_not_claimed(self):
        from app.modules.facturacion.repository import enqueue,claim
        from app.modules.facturacion.service import invalidate_sale
        enqueue(1,'VENTA',1,{'x':1});invalidate_sale(1,1);db.session.commit()
        self.assertIsNone(claim())

    def test_supervisor_lock_is_exclusive_and_released(self):
        from app.modules.facturacion.supervisor import acquire_leadership,release_leadership
        first=acquire_leadership();self.assertIsNotNone(first)
        try:self.assertIsNone(acquire_leadership())
        finally:release_leadership(first)
        second=acquire_leadership();self.assertIsNotNone(second);release_leadership(second)

    def test_scaler_ignores_delayed_jobs_but_counts_a_last_attempt_in_progress(self):
        from app.modules.facturacion.repository import enqueue,claim
        from app.modules.facturacion.supervisor import queue_stats
        one=enqueue(1,'VENTA',1,{'x':1});two=enqueue(1,'VENTA',2,{'x':2});db.session.commit()
        db.session.execute(text("UPDATE fact_api_operacion SET disponible_en=now()+interval '1 hour' WHERE id_operacion=:id"),{'id':two});db.session.commit()
        self.assertEqual(queue_stats()['ready'],1)
        row=claim()
        db.session.execute(text('UPDATE fact_api_operacion SET max_intentos=intentos WHERE id_operacion=:id'),{'id':one});db.session.commit()
        self.assertEqual(queue_stats()['busy'],1)

    def test_real_supervised_processes_start_and_retire_gracefully(self):
        from tempfile import TemporaryDirectory
        from app.modules.facturacion.supervisor import Supervisor
        now=[0]
        with TemporaryDirectory() as folder:
            manager=Supervisor(folder,clock=lambda:now[0])
            stats={'ready':20,'busy':0,'oldest':1,'blocked':False,'unhealthy':False}
            try:
                manager.heartbeat(stats,1)
                self.assertEqual(manager.tick(stats),1)
                now[0]=11;self.assertEqual(manager.tick(stats),4)
                manager.heartbeat(stats,4)
                processes=[c.process for c in manager.children]
                self.assertEqual(db.session.execute(text('SELECT activos FROM fact_api_escalado')).scalar(),4)
            finally:manager.wait_for_retirement()
            self.assertEqual(manager.children,[])
            self.assertTrue(all(p.returncode==0 for p in processes))

    def test_worker_slots_remain_bounded_across_supervisor_generations(self):
        from app.modules.facturacion.supervisor import acquire_worker_slot,release_worker_slot
        slots=[]
        try:
            for _ in range(4):
                slot=acquire_worker_slot();self.assertIsNotNone(slot);slots.append(slot)
            self.assertIsNone(acquire_worker_slot())
            release_worker_slot(slots.pop()[0])
            replacement=acquire_worker_slot();self.assertIsNotNone(replacement);slots.append(replacement)
        finally:
            for slot in slots:release_worker_slot(slot[0])

    def test_old_worker_epoch_cannot_continue_after_supervisor_replacement(self):
        from app.modules.facturacion.supervisor import Supervisor,owns_epoch
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as folder:
            first=Supervisor(folder)
            stats={'ready':0,'busy':0,'oldest':0,'blocked':False,'unhealthy':False}
            first.heartbeat(stats,1)
            self.assertTrue(owns_epoch(first.identity))
            second=Supervisor(folder);second.heartbeat(stats,1)
            self.assertFalse(owns_epoch(first.identity))
            self.assertTrue(owns_epoch(second.identity))

    def test_exhausted_dead_worker_is_closed_for_review(self):
        from app.modules.facturacion.repository import enqueue,claim
        enqueue(1,'VENTA',1,{'x':1});db.session.commit();claim()
        db.session.execute(text("UPDATE fact_api_operacion SET max_intentos=1,lease_hasta=now()-interval '1 minute'"));db.session.commit()
        self.assertIsNone(claim())
        self.assertEqual(db.session.execute(text('SELECT estado FROM fact_api_operacion')).scalar(),'REVISION')
        self.assertEqual(db.session.execute(text('SELECT resultado FROM fact_api_intento')).scalar(),'LEASE_VENCIDO')

    def test_original_attachment_is_private_and_deduplicated(self):
        import io
        from flask_jwt_extended import create_access_token
        def headers(profile=1,local=1):
            token=create_access_token(identity='1',additional_claims={'tipo_token':'operativo','id_perfil':profile,'id_local':local})
            return {'Authorization':'Bearer '+token}
        client=self.app.test_client()
        def upload():return client.post('/api/v1/fact-api/COMPRA/1/originales',headers=headers(),
            data={'formato':'PDF','archivo':(io.BytesIO(b'%PDF-1.7\ntest-original'),'factura.pdf')})
        one=upload();self.assertEqual(one.status_code,201,one.json)
        two=upload();self.assertEqual(one.json,two.json)
        from flask import g
        g.pop('local_operativo',None)
        path='/api/v1/fact-api/originales/'+one.json['id_adjunto']
        response=client.get(path,headers=headers(local=2))
        self.assertEqual(response.status_code,404)
        g.pop('local_operativo',None)
        response=client.get(path,headers=headers())
        self.assertEqual(response.status_code,200);self.assertTrue(response.data.startswith(b'%PDF-'))
        response.close()
        self.assertEqual(client.get(path,headers=headers(profile=4)).status_code,403)


@unittest.skipUnless(os.getenv('LOCAL_SCOPE_TEST_DB')=='1','PostgreSQL aislado')
class AutomaticPaymentTests(unittest.TestCase):
    def test_payment_enqueues_in_same_transaction_and_repeat_does_not_duplicate(self):
        import test_salon_payments as payments
        case=payments.SalonPaymentTests(methodName='test_electronic_customer_and_local_read_access')
        case.setUp()
        try:
            db.session.execute(text('''INSERT INTO fact_api_config(id_local,activo,empresa,serie_factura,serie_boleta,tasa_igv)
                VALUES(1,true,'{"nombre":"Prueba"}','F001','B001',18)
                ON CONFLICT(id_local) DO UPDATE SET activo=true'''))
            self.assertEqual(case.guardar(enviar=True).status_code,200)
            payload=case.payload()
            response=case.pay(payload)
            self.assertEqual(response.status_code,201,response.json)
            self.assertEqual(case.pay(payload).status_code,200)
            self.assertEqual(db.session.execute(text("SELECT count(*) FROM fact_api_operacion WHERE origen='VENTA' AND id_origen=:id"),{'id':response.json['id']}).scalar(),1)
        finally:case.tearDown()
