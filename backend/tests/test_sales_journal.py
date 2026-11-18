import unittest
from datetime import date
from unittest.mock import patch
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
from werkzeug.exceptions import BadRequest
from app.modules.auth.salon_payments import salon_payments_bp, filtros_diario

class SalesJournalTests(unittest.TestCase):
    def setUp(self):
        self.app=Flask(__name__)
        self.app.config['JWT_SECRET_KEY']='test-secret-key-at-least-thirty-two-characters'
        JWTManager(self.app)
        self.app.register_blueprint(salon_payments_bp,url_prefix='/api/salon')
        with self.app.app_context(): self.token=create_access_token(identity='7')
    def test_dates_use_lima_and_include_end_date(self):
        data=filtros_diario({'desde':'2026-11-18','hasta':'2026-11-18'},date(2026,11,18))
        self.assertEqual(data['inicio'].isoformat(),'2026-11-18T00:00:00-05:00')
        self.assertEqual(data['fin'].isoformat(),'2026-11-19T00:00:00-05:00')
    def test_invalid_filters_rejected(self):
        for args in ({'tipo':'SQL'},{'metodo':'OTRO'},{'desde':'2026-11-20','hasta':'2026-11-18'},{'pagina':'0'},{'desde':'ayer'}):
            with self.subTest(args=args),self.assertRaises(BadRequest): filtros_diario(args,date(2026,11,18))
    def test_team_cannot_read_diary(self):
        with patch('app.modules.auth.salon_payments.contexto',return_value={'perfil':4,'id_local':3}):
            r=self.app.test_client().get('/api/salon/ventas',headers={'Authorization':'Bearer '+self.token})
        self.assertEqual(r.status_code,403)
    def test_query_scopes_local_filters_and_aggregate(self):
        result={'cantidad':21,'total':125,'efectivo':125,'tarjeta':0,'ventas':[{'id_cobro':81,'total':25}]}
        with patch('app.modules.auth.salon_payments.contexto',return_value={'perfil':3,'id_local':3,'local':'Barranco'}), patch('app.modules.auth.salon_payments.preparado'), patch('app.modules.auth.salon_payments.db') as database:
            database.session.execute.return_value.mappings.return_value.one.return_value=result
            r=self.app.test_client().get('/api/salon/ventas?desde=2026-11-18&hasta=2026-11-18&metodo=EFECTIVO&pagina=2',headers={'Authorization':'Bearer '+self.token})
            self.assertEqual(r.status_code,200)
            sql,params=database.session.execute.call_args.args
            self.assertIn('id_local=:local',str(sql))
            self.assertIn('metodo=:metodo',str(sql))
            self.assertEqual(params['local'],3)
            self.assertEqual(params['offset'],20)
            self.assertEqual(r.json['ventas'][0]['numero'],'INT-00000081')
            self.assertEqual(r.json['cantidad'],21)
    def test_journal_requires_authentication(self):
        self.assertEqual(self.app.test_client().get('/api/salon/ventas').status_code,401)
if __name__=='__main__': unittest.main()
