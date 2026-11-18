import unittest
from unittest.mock import patch
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
from werkzeug.exceptions import BadRequest


class ClienteValidationTests(unittest.TestCase):
    def test_ruc10_is_natural_and_document_remains_a_string(self):
        from app.modules.clientes.service import validar
        row = validar({'tipo_persona':'NATURAL','tipo_documento':'RUC','numero_documento':'10123456789','nombre':' Ana '})
        self.assertEqual(row['tipo_persona'], 'NATURAL')
        self.assertEqual(row['numero_documento'], '10123456789')
        self.assertEqual(row['nombre'], 'Ana')
        self.assertEqual(validar({'nombre':'Ana','numero_documento':'00123456','tipo_documento':'DNI'})['numero_documento'],'00123456')

    def test_invalid_documents_person_type_and_nonstring_values_are_rejected(self):
        from app.modules.clientes.service import validar
        for change in ({'nombre':''},{'tipo_persona':'EMPRESA'},{'tipo_documento':'OTRO'},
                       {'tipo_documento':'DNI','numero_documento':'123'},
                       {'numero_documento':12345678},{'tipo_documento':'RUC','numero_documento':'12345678'},
                       {'tipo_persona':'JURIDICA','tipo_documento':'DNI','numero_documento':'12345678'}):
            with self.subTest(change=change), self.assertRaises(BadRequest):
                validar({'nombre':'Ana',**change})
        self.assertIsNone(validar({'nombre':'Sin documento'})['numero_documento'])


class ClienteRouteTests(unittest.TestCase):
    def setUp(self):
        from app.modules.clientes.routes import clientes_bp
        self.app=Flask(__name__)
        self.app.config.update(TESTING=True,JWT_SECRET_KEY='customer-tests-secret-at-least-32-characters')
        JWTManager(self.app)
        self.app.register_blueprint(clientes_bp,url_prefix='/api/v1/clientes')
        self.client=self.app.test_client()

    def headers(self,perfil=2,local=7):
        with self.app.app_context():
            token=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':perfil,'id_local':local})
        return {'Authorization':'Bearer '+token}

    def test_supervisor_search_uses_selected_local_and_bounded_pagination(self):
        with patch('app.core.local_scope.db.session.execute') as execute, patch('app.modules.clientes.routes.buscar',return_value=[]) as search:
            execute.return_value.scalar.return_value=True
            response=self.client.get('/api/v1/clientes?q=00123456&limit=15&offset=2',headers=self.headers(3))
            self.assertEqual(response.status_code,200)
            search.assert_called_once_with(7,'00123456',15,2)
            for query in ('limit=0','limit=101','offset=-1','limit=abc'):
                self.assertEqual(self.client.get('/api/v1/clientes?'+query,headers=self.headers()).status_code,400)

    def test_member_and_revoked_membership_are_denied(self):
        self.assertEqual(self.client.get('/api/v1/clientes',headers=self.headers(4)).status_code,403)
        with patch('app.core.local_scope.db.session.execute') as execute:
            execute.return_value.scalar.return_value=False
            self.assertEqual(self.client.get('/api/v1/clientes',headers=self.headers()).status_code,403)

    def test_create_and_missing_customer(self):
        with patch('app.core.local_scope.db.session.execute') as execute, patch('app.modules.clientes.routes.crear',return_value={'id_cliente':'f56f07c8-7348-4cc5-8a70-b58a8319967c'}) as create, patch('app.modules.clientes.routes.obtener',return_value=None):
            execute.return_value.scalar.return_value=True
            response=self.client.post('/api/v1/clientes',json={'nombre':'Ana'},headers=self.headers())
            self.assertEqual(response.status_code,201)
            create.assert_called_once_with(7,{'nombre':'Ana'})
            self.assertEqual(self.client.get('/api/v1/clientes/f56f07c8-7348-4cc5-8a70-b58a8319967c',headers=self.headers()).status_code,404)

    def test_salon_supervisor_allowed_and_team_denied(self):
        from app.modules.clientes.routes import salon_clientes_bp
        app=Flask(__name__)
        app.config.update(TESTING=True,JWT_SECRET_KEY='customer-tests-secret-at-least-32-characters')
        JWTManager(app)
        app.register_blueprint(salon_clientes_bp,url_prefix='/api/salon')
        with app.app_context():
            token=create_access_token(identity='2',additional_claims={'tipo_token':'salon','id_local':9})
        headers={'Authorization':'Bearer '+token}
        with patch('app.modules.clientes.routes.validar_sesion_salon',return_value={'id_local':9,'perfil':3}), patch('app.modules.clientes.routes.buscar',return_value=[]) as search:
            self.assertEqual(app.test_client().get('/api/salon/clientes',headers=headers).status_code,200)
            search.assert_called_once_with(9,'',25,0)
        with patch('app.modules.clientes.routes.validar_sesion_salon',return_value={'id_local':9,'perfil':4}):
            self.assertEqual(app.test_client().get('/api/salon/clientes',headers=headers).status_code,403)

class ClientePersistenceTests(unittest.TestCase):
    def setUp(self):
        from sqlalchemy import create_engine, text
        from sqlalchemy.orm import Session
        from types import SimpleNamespace
        self.engine=create_engine('sqlite://')
        self.session=Session(self.engine)
        self.session.execute(text("ATTACH DATABASE ':memory:' AS public"))
        self.session.execute(text('''CREATE TABLE public.cliente_comercial (
            id_cliente TEXT PRIMARY KEY,id_local INTEGER,tipo_persona TEXT,tipo_documento TEXT,
            numero_documento TEXT,nombre TEXT,direccion TEXT,email TEXT,telefono TEXT)'''))
        self.mock=patch('app.modules.clientes.service.db',SimpleNamespace(session=self.session))
        self.mock.start()

    def tearDown(self):
        self.mock.stop()
        self.session.close()
        self.engine.dispose()

    def test_creation_uses_uuid_and_lookup_cannot_cross_local(self):
        from uuid import UUID
        from app.modules.clientes.service import crear, obtener
        customer=crear(7,{'nombre':'Ana','tipo_documento':'DNI','numero_documento':'00123456'})
        self.assertEqual(str(UUID(customer['id_cliente'])),customer['id_cliente'])
        self.assertNotEqual(customer['id_cliente'],'00123456')
        self.assertEqual(obtener(7,customer['id_cliente'])['numero_documento'],'00123456')
        self.assertIsNone(obtener(8,customer['id_cliente']))

    def test_invalid_input_never_creates_customer(self):
        from sqlalchemy import text
        from app.modules.clientes.service import crear
        with self.assertRaises(BadRequest):
            crear(7,{'nombre':'Ana','tipo_documento':'DNI','numero_documento':12345678})
        self.assertEqual(self.session.execute(text('SELECT count(*) FROM public.cliente_comercial')).scalar(),0)
