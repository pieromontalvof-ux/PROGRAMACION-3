"""Adjustment replaces a review atomically without executing purchase writes."""
import json
import unittest
from copy import deepcopy
from unittest.mock import patch
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
from sqlalchemy import text
from app.core.extensions import db
from app.multiagente.api import routes, drafts
from app.multiagente.api.provider import AssistantError

IDENTITY = '73f497ae-c692-4e14-a89f-7db565cad044'
PLAN = {'recurso':'ordenes_compra','accion':'crear','advertencia':'Revisar',
        'horizonte':'semanal','dias_abastecimiento':14,'_privado':'oculto',
        'datos':{'accion':'GUARDAR_BORRADOR','detalles':[
            {'id_producto':7,'cantidad_solicitada':5}, {'id_producto':8,'cantidad_solicitada':3}]},
        'revision_compra':[{'producto':'Limon','unidad':'KGM','presentacion_compra':2.5,'cantidad_final':5,'porcentaje_general':10},
                           {'producto':'Agua','unidad':'LTR','presentacion_compra':3,'cantidad_final':3}]}

class PurchaseAdjustmentTests(unittest.TestCase):
    def setUp(self):
        availability = patch('app.multiagente.api.quotas.ensure_enabled')
        availability.start(); self.addCleanup(availability.stop)
        app=Flask(__name__)
        app.config.update(SQLALCHEMY_DATABASE_URI='sqlite://',JWT_SECRET_KEY='adjustment-test-secret-key-at-least-32')
        db.init_app(app)
        JWTManager(app)
        app.register_blueprint(routes.asistente_ia_bp,url_prefix='/api/asistente-ia')
        ctx=app.app_context(); ctx.push()
        self.addCleanup(ctx.pop); self.addCleanup(db.session.remove)
        db.session.execute(text("""CREATE TABLE asistente_ia_borrador (
            id TEXT PRIMARY KEY,id_usuario INTEGER,id_perfil INTEGER,id_local INTEGER,plan JSON,
            estado TEXT DEFAULT 'PENDIENTE', vence_en TEXT DEFAULT '2099-01-01')"""))
        db.session.execute(text('INSERT INTO asistente_ia_borrador(id,id_usuario,id_perfil,id_local,plan) VALUES (:id,1,1,1,:p)'),{'id':IDENTITY,'p':json.dumps(PLAN)})
        db.session.commit()
        self.client=app.test_client()
        self.menu={'menu':[{'id_opcion_menu':22,'permisos':{'consultar':True,'crear':True}}]}
        self.headers=self.token()
        self.products={'productos':[{'id_producto':7,'presentacion':2.5,'unidad':'KGM'}, {'id_producto':8,'presentacion':3,'unidad':'LTR'}]}
        for target,kwargs in [('app.multiagente.api.routes.obtener_sesion_actual',{'side_effect':lambda *_:(self.menu,200)}),
                              ('app.multiagente.api.drafts.load',{'side_effect':self.load}),
                              ('app.multiagente.api.tools.native',{'side_effect':lambda *_:deepcopy(self.products)}),
                              ('app.multiagente.api.tools.execute',{'side_effect':AssertionError('Must never create order')})]:
            p=patch(target,**kwargs); p.start(); self.addCleanup(p.stop)

    def token(self,local=1):
        return {'Authorization':'Bearer '+create_access_token(identity='1',additional_claims={'id_perfil':1,'id_local':local})}

    def load(self,identity):
        row=db.session.execute(text('SELECT *, vence_en > CURRENT_TIMESTAMP AS vigente FROM asistente_ia_borrador WHERE id=:id AND id_usuario=:usuario AND id_perfil=:perfil AND id_local=:local'),{'id':identity,**drafts.scope()}).mappings().first()
        if row is None: raise AssistantError('No existe',404)
        return {**row,'plan':json.loads(row['plan'])}

    def post(self,changes=None,headers=None):
        return self.client.post('/api/asistente-ia/compras/ajustar',headers=headers or self.headers,json={
            'id_borrador':IDENTITY,'cantidades':changes if changes is not None else [{'id_producto':7,'presentaciones':5}]})

    def states(self):
        return db.session.execute(text('SELECT estado FROM asistente_ia_borrador ORDER BY estado')).scalars().all()

    def test_replacement_commits_old_cancelled_and_new_pending_without_order(self):
        response=self.post()
        self.assertEqual(response.status_code,200,response.json)
        draft=response.json['borrador']
        self.assertNotEqual(draft['id_borrador'],IDENTITY)
        self.assertEqual(draft['datos']['detalles'],[{'id_producto':7,'cantidad_solicitada':12.5},{'id_producto':8,'cantidad_solicitada':3}])
        self.assertEqual(draft['revision_compra'][0]['cantidad_final'],12.5)
        self.assertTrue(draft['revision_compra'][0]['ajuste_manual'])
        self.assertEqual(draft['dias_abastecimiento'],14)
        self.assertEqual(draft['revision_compra'][0]['porcentaje_general'],10)
        self.assertNotIn('_privado',draft)
        self.assertEqual(self.states(),['CANCELADO','PENDIENTE'])
        self.assertEqual(self.post().status_code,409)

    def test_invalid_payloads_leave_original_unchanged(self):
        for changes in [[{'id_producto':9,'presentaciones':2}], [{'id_producto':7,'presentaciones':1.5}],
                        [{'id_producto':7,'presentaciones':True}], [{'id_producto':7,'presentaciones':0}],
                        [{'id_producto':7,'presentaciones':1000001}], [{'id_producto':7,'presentaciones':2,'cantidad':20}],
                        [{'id_producto':7,'presentaciones':2}]*2]:
            with self.subTest(changes=changes):
                self.assertEqual(self.post(changes).status_code,400)
                self.assertEqual(self.states(),['PENDIENTE'])

    def test_scope_and_current_permissions_are_enforced(self):
        self.assertEqual(self.post(headers=self.token(local=2)).status_code,404)
        self.menu['menu'][0]['permisos']['crear']=False
        self.assertEqual(self.post().status_code,403)
        self.assertEqual(self.states(),['PENDIENTE'])

    def test_expired_processed_and_changed_pack_are_rejected(self):
        self.products['productos'][0]['presentacion']=1
        self.assertEqual(self.post().status_code,409)
        self.products['productos'][0]['presentacion']=2.5
        db.session.execute(text("UPDATE asistente_ia_borrador SET vence_en='2000-01-01'")); db.session.commit()
        self.assertEqual(self.post().status_code,409)
        db.session.execute(text("UPDATE asistente_ia_borrador SET estado='REALIZADO',vence_en='2099-01-01'")); db.session.commit()
        self.assertEqual(self.post().status_code,409)

    def test_missing_current_local_product_is_rejected(self):
        self.products['productos']=self.products['productos'][1:]
        self.assertEqual(self.post().status_code,409)
        self.assertEqual(self.states(),['PENDIENTE'])

    def test_failed_replacement_commit_rolls_back_both_writes(self):
        with patch.object(db.session, 'commit', side_effect=RuntimeError('storage unavailable')):
            self.assertEqual(self.post().status_code,500)
        self.assertEqual(self.states(),['PENDIENTE'])

    def test_ambiguous_review_mapping_is_rejected_without_writes(self):
        plan=deepcopy(PLAN)
        plan['revision_compra'][0]['id_producto']=8
        db.session.execute(text('UPDATE asistente_ia_borrador SET plan=:plan'),{'plan':json.dumps(plan)})
        db.session.commit()
        self.assertEqual(self.post().status_code,409)
        self.assertEqual(self.states(),['PENDIENTE'])
