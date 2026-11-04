"""Exercise the real SQL only in a new disposable PostgreSQL cluster.

Opt in: STOCK_LIMITS_MIGRATION_TEST_DB=1 python -m unittest discover
    -s tests -p test_stock_limits_migration.py -v
Does not import the application, read .env, or contact an existing database.
"""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest

import psycopg2
from psycopg2.errors import CheckViolation


ROOT = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get('POSTGRES_BIN', 'C:/Program Files/PostgreSQL/18/bin'))
SUFFIX = '.exe' if os.name == 'nt' else ''


@unittest.skipUnless(os.environ.get('STOCK_LIMITS_MIGRATION_TEST_DB') == '1',
                     'Requiere PostgreSQL temporal: STOCK_LIMITS_MIGRATION_TEST_DB=1')
class StrictStockLimitsMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (BIN / ('initdb' + SUFFIX)).is_file():
            raise unittest.SkipTest('Define POSTGRES_BIN con los binarios PostgreSQL')
        cls.temporary = tempfile.TemporaryDirectory(prefix='barbarito_stock_limits_')
        cls.directory = Path(cls.temporary.name)
        cls.addClassCleanup(cls.temporary.cleanup)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            cls.port = sock.getsockname()[1]
        cls.command('initdb', '-D', str(cls.directory / 'data'), '-U', 'postgres',
                    '-A', 'trust', '--encoding=UTF8', '--no-locale')
        cls.command('pg_ctl', '-D', str(cls.directory / 'data'), '-l', str(cls.directory / 'server.log'),
                    '-o', f'-h 127.0.0.1 -p {cls.port}', '-w', 'start')
        cls.addClassCleanup(cls.command, 'pg_ctl', '-D', str(cls.directory / 'data'), '-m', 'fast', '-w', 'stop')
        # Every connection is explicit and limited to this freshly initialized port.
        cls.connection = psycopg2.connect(host='127.0.0.1', port=cls.port, user='postgres', dbname='postgres')
        cls.connection.autocommit = True
        cls.addClassCleanup(cls.connection.close)

    @classmethod
    def command(cls, name, *args):
        clean_env = {key: value for key, value in os.environ.items()
                     if not key.startswith('PG') and key != 'DATABASE_URL'}
        with (cls.directory / (name + '.log')).open('w', encoding='utf-8') as output:
            result = subprocess.run([str(BIN / (name + SUFFIX)), *args], env=clean_env,
                                    stdout=output, stderr=output,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        if result.returncode:
            raise RuntimeError((cls.directory / (name + '.log')).read_text(encoding='utf-8', errors='replace'))

    def execute(self, sql, parameters=None):
        with self.connection.cursor() as cursor:
            cursor.execute(sql, parameters)
            return cursor.fetchall() if cursor.description else None

    def setUp(self):
        self.execute('''
            DROP TABLE IF EXISTS public.producto_stock_local;
            CREATE TABLE public.producto_stock_local (
                id_producto integer PRIMARY KEY,
                stock_minimo numeric(12,3) NOT NULL DEFAULT 0,
                stock_maximo numeric(12,3),
                CONSTRAINT ck_stock_local_minimo CHECK (stock_minimo >= 0),
                CONSTRAINT ck_stock_local_maximo CHECK (stock_maximo IS NULL OR stock_maximo >= stock_minimo)
            );
            INSERT INTO public.producto_stock_local VALUES (1, 5, 5), (2, 0, 0.001), (3, 1, NULL);
            SET search_path = pg_catalog;
        ''')

    def migrate(self):
        self.execute((ROOT / 'database/migrations/20261021_limites_stock_estrictos.sql').read_text(encoding='utf-8'))

    def test_preserves_legacy_bounds_and_rejects_future_equal_writes_after_repeated_migration(self):
        before = self.execute('SELECT * FROM public.producto_stock_local ORDER BY id_producto')
        for _ in range(2):
            self.migrate()
            self.assertEqual(self.execute('SELECT * FROM public.producto_stock_local ORDER BY id_producto'), before)
            self.assertEqual(self.execute("SELECT convalidated FROM pg_constraint WHERE conrelid='public.producto_stock_local'::regclass AND conname='ck_stock_local_maximo'"), [(False,)])
            for sql in [
                'INSERT INTO public.producto_stock_local VALUES (4, 1, 1)',
                'UPDATE public.producto_stock_local SET stock_maximo=stock_minimo WHERE id_producto=2',
                'UPDATE public.producto_stock_local SET stock_minimo=stock_minimo WHERE id_producto=1',
            ]:
                with self.subTest(sql=sql), self.assertRaises(CheckViolation):
                    self.execute(sql)
        self.execute('INSERT INTO public.producto_stock_local VALUES (5, 0, 0.001), (6, 999999999.998, 999999999.999), (7, 0, NULL)')

    def test_validates_when_all_existing_bounds_are_strict(self):
        self.execute('UPDATE public.producto_stock_local SET stock_maximo=6 WHERE id_producto=1')
        for _ in range(2):
            self.migrate()
            self.assertEqual(self.execute("SELECT convalidated FROM pg_constraint WHERE conrelid='public.producto_stock_local'::regclass AND conname='ck_stock_local_maximo'"), [(True,)])

    def test_cannot_validate_legacy_equal_bounds_until_deliberately_corrected(self):
        self.migrate()
        with self.assertRaises(CheckViolation):
            self.execute('ALTER TABLE public.producto_stock_local VALIDATE CONSTRAINT ck_stock_local_maximo')
        self.execute('UPDATE public.producto_stock_local SET stock_maximo=6 WHERE id_producto=1')
        self.execute('ALTER TABLE public.producto_stock_local VALIDATE CONSTRAINT ck_stock_local_maximo')
        with self.assertRaises(CheckViolation):
            self.execute('INSERT INTO public.producto_stock_local VALUES (4, 9, 8)')

    def test_workspace_migration_preserves_saved_rows_on_repeat_and_enforces_bounds(self):
        # Share this disposable server; its new barbarito database contains only
        # this minimal fake user table, never a copy of the application's DB.
        self.execute('CREATE DATABASE barbarito')
        connection = psycopg2.connect(host='127.0.0.1', port=self.port, user='postgres', dbname='barbarito')
        self.addCleanup(connection.close)
        connection.autocommit = True
        migration = (ROOT / 'database/migrations/20261021_asistente_ia_workspace.sql').read_text(encoding='utf-8')
        with connection.cursor() as cursor:
            cursor.execute('CREATE TABLE public.usuario(id_usuario integer PRIMARY KEY); INSERT INTO public.usuario VALUES (1); CREATE ROLE multi;')
            cursor.execute(migration)
            cursor.execute("INSERT INTO public.asistente_ia_workspace(id_usuario,id_perfil,id_local,snapshot,revision) VALUES (1,2,1,'{\"form\": {\"nombre\": \"Prueba\"}}',3)")
            cursor.execute('SELECT * FROM public.asistente_ia_workspace')
            before = cursor.fetchall()
            cursor.execute(migration)
            cursor.execute('SELECT * FROM public.asistente_ia_workspace')
            self.assertEqual(cursor.fetchall(), before)
            cursor.execute("SELECT has_table_privilege('multi','public.asistente_ia_workspace','SELECT,INSERT,UPDATE')")
            self.assertEqual(cursor.fetchone(), (True,))
            for value in ["'[]'::jsonb", "jsonb_build_object('value',repeat('x',200001))"]:
                with self.subTest(snapshot=value), self.assertRaises(CheckViolation):
                    cursor.execute(f'INSERT INTO public.asistente_ia_workspace(id_usuario,id_perfil,id_local,snapshot) VALUES (1,2,2,{value})')
            with self.assertRaises(CheckViolation):
                cursor.execute('INSERT INTO public.asistente_ia_workspace(id_usuario,id_perfil,id_local,revision) VALUES (1,2,2,-1)')
            cursor.execute('INSERT INTO public.asistente_ia_workspace(id_usuario,id_perfil,id_local,snapshot) VALUES (1,3,1,NULL)')


if __name__ == '__main__':
    unittest.main()
