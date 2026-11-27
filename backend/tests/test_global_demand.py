import unittest
from datetime import date
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from app import create_app


class GlobalDemandTests(unittest.TestCase):
    def test_combines_sales_but_keeps_stock_risk_separate_per_store(self):
        from app.modules.inventarios.demand_global import combine
        def source(identity,name,quantity,stock,known=True):
            return {'id_local':identity,'nombre':name,'cobros':1,'dias_con_ventas':1,
                    'productos_con_stock':[9] if known else [],'reporte':{
                        'articulos':[{'id_presentacion':5,'id_promocion':None,'nombre':'Mojito','cantidad':quantity,'total':quantity*15,'cantidad_en_promociones':0}],
                        'productos':[{'id_producto':9,'nombre':'Limon','unidad':'KGM','stock_actual':stock,'consumo_ventas':7,'consumo_diario':1,'cobertura_dias':stock}]}}
        result=combine(date(2026,1,1),date(2026,1,7),[
            source(1,'A',10,1),source(2,'B',20,100),source(3,'C',0,0,False)])
        self.assertEqual(result['articulos'][0]['cantidad'],30)
        row=result['productos'][0]
        self.assertEqual(row['stock_total_registrado'],101)
        self.assertEqual(row['cobertura_minima_dias'],1)
        self.assertIsNone(row['locales'][2]['stock_actual'])
        self.assertEqual(row['locales'][0]['id_local'],1)
        self.assertEqual(result['alcance'],'GLOBAL')
        partial=source(1,'A',10,1)
        partial['cobros_con_inventario']=0
        limited=combine(date(2026,1,1),date(2026,1,7),[partial])
        self.assertIsNone(limited['productos'][0]['cobertura_minima_dias'])
        self.assertFalse(limited['productos'][0]['locales'][0]['consumo_verificado'])

    def test_global_route_admin_only_and_preserves_local_endpoints(self):
        app=create_app();app.config['JWT_SECRET_KEY']='global-demand-tests-only-secret-at-least-32'
        client=app.test_client();url='/api/inventario-operativo/demanda-global?desde=2020-01-01&hasta=2020-01-07'
        self.assertEqual(client.get(url).status_code,401)
        for role,status in [(1,200),(2,403),(3,403),(4,403)]:
            with app.app_context():
                token=create_access_token(identity='1',additional_claims={'tipo_token':'operativo','id_perfil':role,'id_local':4})
            with patch('app.core.extensions.db.session.execute') as execute, \
                 patch('app.modules.inventarios.operativo.perfil_tiene_capacidad', return_value=role == 1), \
                 patch('app.modules.inventarios.demand_global.report',return_value={'alcance':'GLOBAL'}) as report:
                execute.return_value.scalar.return_value=True
                response=client.get(url,headers={'Authorization':'Bearer '+token})
                self.assertEqual(response.status_code,status)
                if role!=1:report.assert_not_called()
        with app.app_context():
            token=create_access_token(identity='1',additional_claims={'tipo_token':'operativo','id_perfil':1})
        with patch('app.core.extensions.db.session.execute') as execute,patch('app.modules.inventarios.demand_global.report') as report:
            execute.return_value.scalar.return_value=True
            self.assertEqual(client.get(url+'&id_local=4',headers={'Authorization':'Bearer '+token}).status_code,400)
            report.assert_not_called()

    def test_agent_global_capability_is_read_only_and_separate_from_local(self):
        from app.multiagente.api import global_demand,demand
        session={'menu':[{'id_opcion_menu':14,'permisos':{'consultar':True}}]}
        with patch.object(global_demand, 'get_jwt', return_value={'id_perfil':1}), \
             patch.object(global_demand, 'perfil_tiene_capacidad', return_value=True):
            self.assertTrue(global_demand.allowed(session))
            self.assertFalse(global_demand.allowed(session,'crear'))
        with patch.object(global_demand, 'get_jwt', return_value={'id_perfil':2}), \
             patch.object(global_demand, 'perfil_tiene_capacidad', return_value=False):
            self.assertFalse(global_demand.allowed(session))
        with patch.object(demand,'get_jwt',return_value={'id_perfil':1}), \
             patch.object(demand, 'perfil_tiene_capacidad', return_value=False):
            self.assertFalse(demand.allowed(session))
