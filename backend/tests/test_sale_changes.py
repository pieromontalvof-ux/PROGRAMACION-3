from datetime import date
import unittest
from werkzeug.exceptions import Conflict
from app.modules.salon.salon_sale_changes import verificar_dia
class SaleDayTest(unittest.TestCase):
 def test_open_today(self):
  verificar_dia(date(2026,11,19),date(2026,11,19),None,date(2026,11,19))
 def test_old_or_closed(self):
  for fecha,cierre in [(date(2026,11,18),None),(date(2026,11,19),'closed')]:
   with self.assertRaises(Conflict): verificar_dia(fecha,fecha,cierre,date(2026,11,19))

from unittest.mock import patch, MagicMock
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
from app.modules.salon.salon_payments import salon_payments_bp
class SaleChangeRoutes(unittest.TestCase):
 def setUp(self):
  capacidad = patch('app.modules.salon.salon_payments.perfil_tiene_capacidad',
                    side_effect=lambda perfil, permiso: perfil in (2, 3))
  capacidad.start()
  self.addCleanup(capacidad.stop)
  self.app=Flask(__name__);self.app.config['JWT_SECRET_KEY']='a-test-secret-of-more-than-thirty-two-characters';JWTManager(self.app)
  self.app.register_blueprint(salon_payments_bp,url_prefix='/api/salon')
  with self.app.app_context(): self.token=create_access_token(identity='1')
 def post(self,body):
  return self.app.test_client().post('/api/salon/comprobantes/1/anular',json=body,headers={'Authorization':'Bearer '+self.token})
 def test_team_denied(self):
  with patch('app.modules.salon.salon_payments.contexto',return_value={'perfil':4}):
   self.assertEqual(self.post({'motivo':'Equivocación','version':0}).status_code,403)
 def test_reason_required(self):
  with patch('app.modules.salon.salon_payments.contexto',return_value={'perfil':2}):
   self.assertEqual(self.post({'motivo':'','version':0}).status_code,400)
 def test_foreign_store_not_found(self):
  with patch('app.modules.salon.salon_payments.contexto',return_value={'perfil':2,'id_local':3}),patch('app.modules.inventarios.operativo.bloqueo'),patch('app.modules.salon.salon_payments.db') as database:
   database.session.execute.return_value.mappings.return_value.first.return_value=None
   self.assertEqual(self.post({'motivo':'Equivocación','version':0}).status_code,404)
   sql,params=database.session.execute.call_args.args
   self.assertIn('public.salon_cambio_bloqueado',str(sql));self.assertEqual(params['local'],3)
   database.session.rollback.assert_called_once()
 def test_closed_day_cannot_change(self):
  row=dict(fecha_venta=date(2026,11,19),jornada_fecha=date(2026,11,19),cerrado_en='closed',hoy=date(2026,11,19))
  with patch('app.modules.salon.salon_payments.contexto',return_value={'perfil':2,'id_local':3}),patch('app.modules.inventarios.operativo.bloqueo'),patch('app.modules.salon.salon_payments.db') as database:
   database.session.execute.return_value.mappings.return_value.first.return_value=row
   self.assertEqual(self.post({'motivo':'Equivocación','version':0}).status_code,409)
   database.session.commit.assert_not_called()
