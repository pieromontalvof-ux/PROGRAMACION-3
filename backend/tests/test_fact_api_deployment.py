import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import os
from unittest.mock import MagicMock,patch


class DeploymentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path=Path(__file__).resolve().parents[1]/'scripts/cloud_runtime.py'
        spec=importlib.util.spec_from_file_location('cloud_runtime',path)
        cls.runtime=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.runtime)

    def test_cloud_environment_is_private_isolated_and_demo_only(self):
        with TemporaryDirectory() as directory:
            env={'DATABASE_URL':'postgresql://user:secret@postgres.internal:5432/railway','APP_DATA_DIR':directory}
            result=self.runtime.prepare_settings(env,Path(directory))
            self.assertEqual(result['laravel']['DB_SEARCH_PATH'],'fact_api')
            self.assertEqual(result['laravel']['BARBARITO_DEMO_ONLY'],'true')
            self.assertEqual(result['laravel']['DB_DATABASE'],'railway')
            self.assertEqual(env['FACT_API_URL'],'http://127.0.0.1:8091')
            self.assertEqual(env['FACT_API_TOKEN'],result['laravel']['BARBARITO_TOKEN'])
            self.assertGreaterEqual(len(env['FACT_API_TOKEN']),32)
            self.assertTrue(Path(env['FACT_API_DOCUMENTS_DIR']).is_relative_to(Path(directory)))

    def test_restart_preserves_keys_and_does_not_write_password_in_manifest(self):
        with TemporaryDirectory() as directory:
            config=lambda:{'DATABASE_URL':'postgresql://user:database-password@host/railway','APP_DATA_DIR':directory}
            first=self.runtime.prepare_settings(config(),Path(directory))
            second=self.runtime.prepare_settings(config(),Path(directory))
            self.assertEqual(first['laravel']['APP_KEY'],second['laravel']['APP_KEY'])
            self.assertEqual(first['laravel']['BARBARITO_TOKEN'],second['laravel']['BARBARITO_TOKEN'])
            manifest=(Path(directory)/'fact_api/runtime-secrets.json').read_text()
            self.assertNotIn('database-password',manifest)

    def test_invalid_database_or_mode_fails_before_migrations(self):
        with TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                self.runtime.prepare_settings({'DATABASE_URL':'sqlite:///:memory:'},Path(directory))
            with self.assertRaises(ValueError):
                self.runtime.prepare_settings({'DATABASE_URL':'postgresql://u:p@host/db','FACT_API_MODE':'PRODUCTION'},Path(directory))

    def test_bad_secret_file_is_not_silently_replaced(self):
        with TemporaryDirectory() as directory:
            path=Path(directory)/'fact_api/runtime-secrets.json'
            path.parent.mkdir();path.write_text('broken')
            with self.assertRaises(ValueError):
                self.runtime.prepare_settings({'DATABASE_URL':'postgresql://u:p@host/db'},Path(directory))
            self.assertEqual(path.read_text(),'broken')

    def test_shutdown_drains_web_before_workers_and_allows_gunicorn_35_seconds(self):
        module=self.runtime
        processes=[MagicMock() for _ in range(4)]
        for process in processes:process.poll.return_value=None
        events=[]
        for index,process in enumerate(processes):
            process.terminate.side_effect=lambda i=index:events.append(i)
        handlers={}
        def register(signum,handler):handlers[signum]=handler
        def interrupt(_):handlers[module.signal.SIGTERM](None,None)
        with patch.dict(os.environ,{'FACT_API_BUNDLED':'1','FACT_API_TOKEN':'t'*40}), \
             patch.object(module,'prepare_settings',return_value={'database':object()}), \
             patch.object(module,'migrate_application'),patch.object(module,'configure_laravel'), \
             patch.object(module,'wait_bridge'),patch.object(module.subprocess,'Popen',side_effect=processes), \
             patch.object(module.signal,'signal',side_effect=register),patch.object(module.time,'sleep',side_effect=interrupt):
            module.main()
        self.assertEqual(events[:2],[3,2])
        processes[3].wait.assert_called_with(timeout=35)
        processes[2].wait.assert_any_call(timeout=65)

    def test_supervisor_waits_for_previous_leader_during_rollout(self):
        path=Path(__file__).resolve().parents[1]/'scripts/run_fact_api_supervisor.py'
        spec=importlib.util.spec_from_file_location('cloud_supervisor_test',path)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        leader=MagicMock();leader.execute.return_value.scalar_one.return_value=123
        with patch('sys.argv',['supervisor','--once','--wait-for-leader']), \
             patch.object(module,'create_app'),patch.object(module,'acquire_leadership',side_effect=[None,leader]), \
             patch.object(module,'release_leadership'),patch.object(module,'queue_stats',return_value={}), \
             patch.object(module,'Supervisor'),patch.object(module,'db'), \
             patch.object(module.signal,'signal'),patch.object(module.time,'sleep') as sleep:
            self.assertEqual(module.main(),0)
        sleep.assert_called_once_with(2)

    @unittest.skipUnless(os.getenv('LOCAL_SCOPE_TEST_DB')=='1','PostgreSQL aislado')
    def test_migrations_are_repeatable_and_preserve_business_tables(self):
        from sqlalchemy import create_engine,text
        from sqlalchemy.engine import make_url
        url=make_url(os.environ['DATABASE_URL'])
        engine=create_engine(url)
        try:
            with engine.begin() as conn:
                self.assertEqual(conn.execute(text('SELECT current_database()')).scalar(),'barbarito_test')
                conn.exec_driver_sql('CREATE TABLE cloud_preservation_probe (id integer PRIMARY KEY, value text)')
                conn.exec_driver_sql("INSERT INTO cloud_preservation_probe VALUES(1,'preserve')")
                sales=conn.execute(text('SELECT count(*) FROM salon_cobro')).scalar()
            self.runtime.migrate_application(url)
            self.runtime.migrate_application(url)
            with engine.connect() as conn:
                self.assertEqual(conn.execute(text('SELECT value FROM cloud_preservation_probe WHERE id=1')).scalar(),'preserve')
                self.assertEqual(conn.execute(text('SELECT count(*) FROM salon_cobro')).scalar(),sales)
                self.assertTrue(conn.execute(text("SELECT to_regclass('public.fact_api_operacion') IS NOT NULL")).scalar())
                self.assertTrue(conn.execute(text("SELECT 1 FROM pg_namespace WHERE nspname='fact_api'")).scalar())
        finally:
            engine.dispose()
