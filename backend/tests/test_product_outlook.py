import unittest
from datetime import date
from unittest.mock import patch


class ProductOutlookTests(unittest.TestCase):
    def test_incomplete_period_keeps_available_analysis_without_partial_labels(self):
        from app.modules.inventarios.product_outlook import calculate
        from app.multiagente.agents.demanda.product_summary import render
        historical={'dias_calendario':10,'desde':'2026-11-01','hasta':'2026-11-10','fechas_sin_registro':['2026-11-09'],
                    'articulos':[{'id_presentacion':1,'nombre':'Sour','cantidad':20}],
                    'productos':[{'id_producto':5,'nombre':'Limon','unidad':'KGM','stock_actual':10,'consumo_diario':2,'cobertura_dias':5}]}
        recipe={'id_presentacion_venta':1,'componentes':[{'tipo_componente':'PRODUCTO','id_producto':5,'cantidad':.05,'unidad':'KGM'}]}
        result=calculate(historical,{'periodos':{}},[recipe],[],{5},date(2026,11,1))
        self.assertEqual(result['articulos'][0]['ventas_diarias'],2)
        self.assertEqual(result['articulos'][0]['cobertura_dias'],5)
        self.assertEqual(result['insumos'][0]['consumo_diario'],2)
        answer=render({'contexto':{**historical,'analisis_productos':result}})
        self.assertIn('| Limon |',answer)
        self.assertIn('| Sour |',answer)
        self.assertNotIn('Provisional',answer)
        self.assertNotIn('provisional',answer.lower())
        self.assertNotIn('parcial',answer.lower())
        self.assertIn('registros disponibles',answer)

    def test_requested_period_controls_daily_average_and_shared_stock_duration(self):
        from app.modules.inventarios.product_outlook import calculate
        recipe={'id_presentacion_venta':1,'componentes':[{'tipo_componente':'PRODUCTO','id_producto':5,'cantidad':.05,'unidad':'KGM'}]}
        weekly={'productos':[{'id_producto':5,'nombre':'Limon','unidad':'KGM','stock_actual':10,'consumo_diario':9,'cobertura_dias':1}],
                'metadata':{'cobertura_completa':True},'periodos':{'base_cobertura':{'desde':'2026-10-29'}}}
        for days,sold,consumed,expected in [(100,200,50,20),(10,40,10,10)]:
            historical={'dias_calendario':days,'articulos':[{'id_presentacion':1,'nombre':'Sour','cantidad':sold}],
                        'productos':[{'id_producto':5,'nombre':'Limon','unidad':'KGM','stock_actual':10,'consumo_diario':consumed/days,'cobertura_dias':expected}],
                        'desde':'2026-07-18','hasta':'2026-11-18','fechas_sin_registro':[]}
            result=calculate(historical,weekly,[recipe],[],{5},date(2026,7,18))
            self.assertEqual(result['articulos'][0]['ventas_diarias'],sold/days)
            self.assertEqual(result['articulos'][0]['cobertura_dias'],expected)
            self.assertEqual(result['insumos'][0]['consumo_diario'],consumed/days)
            self.assertEqual(result['periodos']['base_cobertura']['desde'],historical['desde'])

    def test_partial_sales_still_show_observed_change(self):
        from app.modules.inventarios.product_outlook import calculate
        weekly={'articulos':[{'id_presentacion':1,'cantidad':7,'cantidad_anterior':30,'estado_ultimos7':'INSUFICIENTE','estado_anteriores7':'COMPLETO'}],
                'periodos':{'ultimos7':{'desde':'2026-11-11'},'anteriores7':{'desde':'2026-11-04'}},
                'metadata':{'fechas_sin_registro':['2026-11-17']}}
        result=calculate({'articulos':[{'id_presentacion':1,'nombre':'IPA','cantidad':80}]},weekly,[],[],set(),date(2026,7,18))
        row=result['articulos'][0]
        self.assertAlmostEqual(row['cambio_porcentaje'],-76.6666667)
        self.assertTrue(row['comparacion_provisional'])
        self.assertIn('provisional',row['tendencia'])
        self.assertIn('2026-11-17',result['fechas_sin_registro'])

    def test_provisional_coverage_uses_confirmed_days_and_never_generates_order(self):
        from app.modules.inventarios.weekly import calculate as weekly_calculate
        from app.modules.inventarios.product_outlook import calculate
        weekly=weekly_calculate(date(2026,11,18),[],
            [{'fecha':date(2026,11,16),'id_producto':5,'cantidad':4},
             {'fecha':date(2026,11,17),'id_producto':5,'cantidad':100}],
            [{'id_producto':5,'nombre':'Limon','unidad':'KGM','stock_actual':8}],
            [{'fecha':date(2026,11,16),'cobros':1,'cobros_con_inventario':1}])
        self.assertEqual(weekly['reposicion'],[])
        self.assertIsNone(weekly['productos'][0]['cantidad_sugerida'])
        recipe={'id_presentacion_venta':1,'componentes':[{'tipo_componente':'PRODUCTO','id_producto':5,'cantidad':.05,'unidad':'KGM'}]}
        result=calculate({'articulos':[{'id_presentacion':1,'nombre':'Sour','cantidad':3}]},weekly,[recipe],[],{5},date(2026,7,18))
        self.assertEqual(result['articulos'][0]['cobertura_dias'],2)
        self.assertEqual(result['articulos'][0]['estado_cobertura'],'Provisional')
        self.assertEqual(result['insumos'][0]['dias_observados_cobertura'],1)
        self.assertEqual(result['insumos'][0]['consumo_diario'],4)

    def test_intermediate_links_to_shared_ingredient_without_exclusive_allocation(self):
        from app.modules.inventarios.product_outlook import calculate
        historic={'articulos':[{'id_presentacion':1,'nombre':'Chicha','cantidad':10}]}
        recipe={'activo':True,'id_presentacion_venta':1,'componentes':[{'tipo_componente':'SUBPRODUCTO','id_subproducto':2,'cantidad':.4,'unidad':'LTR'}]}
        sub={'id_subproducto':2,'activo':True,'rendimiento':12,'unidad':'LTR','ingredientes':[{'id_producto':5,'cantidad':2,'unidad':'LTR'}]}
        weekly={'articulos':[],'productos':[{'id_producto':5,'nombre':'Esencia','unidad':'LTR','stock_actual':6,'consumo_diario':2,'cobertura_dias':3}],
                'metadata':{'cobertura_completa':True},'periodos':{'base_cobertura':{'desde':'2026-10-29'}}}
        result=calculate(historic,weekly,[recipe],[sub],{5},date(2026,7,18))
        self.assertEqual(result['articulos'][0]['cobertura_dias'],3)
        self.assertEqual(result['insumos'][0]['consumo_diario'],2)

    def test_native_detail_keeps_session_local(self):
        from app import create_app
        from flask_jwt_extended import create_access_token
        app=create_app()
        with app.app_context():
            token=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':7})
        with patch('app.core.extensions.db.session.execute') as execute, \
             patch('app.modules.inventarios.operativo.contexto',return_value=(7,2,2)), \
             patch('app.modules.inventarios.product_outlook.report',return_value={'analisis_productos':{}}) as report:
            execute.return_value.scalar.return_value=True
            response=app.test_client().get('/api/inventario-operativo/demanda?detalle=productos&desde=2026-07-18&hasta=2026-11-17&id_local=999',headers={'Authorization':'Bearer '+token})
        self.assertEqual(response.status_code,200)
        self.assertEqual(report.call_args.args,(7,date(2026,7,18),date(2026,11,17)))

    def test_summary_renders_native_risk_as_two_tables_not_generic_prose(self):
        from app.multiagente.agents.demanda.product_summary import render
        query={'contexto':{'desde':'2026-07-18','hasta':'2026-11-17','analisis_productos':{
            'articulos':[{'nombre':'Alitas','cantidad':5,'tendencia':'Sin comparación completa','estado_cobertura':'Revisar stock negativo'}],
            'insumos':[{'nombre':'Alitas','stock_actual':-40,'unidad':'C62','estado_cobertura':'Revisar stock negativo'}],
            'periodos':{},'nota':'No es caducidad.'}}}
        answer=render(query)
        self.assertIn('| Producto | Ventas del período |',answer)
        self.assertIn('| Insumo | Stock actual |',answer)
        self.assertIn('Revisar stock negativo',answer)
        self.assertNotIn('no vincula',answer)

    def test_shared_consumption_limits_product_without_recalculating_all_sales(self):
        from app.modules.inventarios.product_outlook import calculate
        historical={'articulos':[{'id_presentacion':1,'id_promocion':None,'nombre':'Mojito','cantidad':80}], 'productos':[]}
        weekly={'articulos':[{'id_presentacion':1,'cantidad':14,'cantidad_anterior':7,'estado_ultimos7':'COMPLETO','estado_anteriores7':'COMPLETO','variacion_porcentaje':100,'semanas':[]}],
                'productos':[{'id_producto':5,'nombre':'Limón','unidad':'KGM','stock_actual':2,'consumo_diario':1,'cobertura_dias':2}],
                'metadata':{'cobertura_completa':True},'periodos':{'base_cobertura':{'desde':'2026-10-29','hasta':'2026-11-17'},'ultimos7':{'desde':'2026-11-11'},'anteriores7':{'desde':'2026-11-04'}}}
        recipes=[{'activo':True,'id_presentacion_venta':1,'componentes':[{'tipo_componente':'PRODUCTO','id_producto':5,'cantidad':.05,'unidad':'KGM'}]}]
        report=calculate(historical,weekly,recipes,[],{5},date(2026,7,18))
        item=report['articulos'][0]
        self.assertEqual(item['tendencia'],'Sube')
        self.assertEqual(item['cobertura_dias'],2)
        self.assertEqual(item['insumo_limitante'],'Limón')
        self.assertEqual(report['insumos'][0]['consumo_diario'],1)

    def test_negative_stock_or_partial_history_is_not_a_physical_stockout_prediction(self):
        from app.modules.inventarios.product_outlook import calculate
        historical={'articulos':[{'id_presentacion':1,'nombre':'Alitas','cantidad':5}]}
        recipes=[{'activo':True,'id_presentacion_venta':1,'componentes':[{'tipo_componente':'PRODUCTO','id_producto':5,'cantidad':8,'unidad':'C62'}]}]
        weekly={'articulos':[],'productos':[{'id_producto':5,'nombre':'Alitas','unidad':'C62','stock_actual':-40,'consumo_diario':None,'cobertura_dias':None}],
                'metadata':{'cobertura_completa':False},'periodos':{}}
        report=calculate(historical,weekly,recipes,[],{5},date(2026,7,18))
        self.assertIsNone(report['articulos'][0]['cobertura_dias'])
        self.assertIn('negativo',report['articulos'][0]['estado_cobertura'])
        self.assertEqual(report['articulos'][0]['tendencia'],'Sin comparación completa')

    def test_missing_recipe_ingredient_and_optional_choices_do_not_overstate_coverage(self):
        from app.modules.inventarios.product_outlook import calculate
        recipe={'activo':True,'id_presentacion_venta':1,'id_grupo_salsa':9,'componentes':[{'tipo_componente':'PRODUCTO','id_producto':5,'cantidad':1,'unidad':'C62'}]}
        report=calculate({'articulos':[{'id_presentacion':1,'cantidad':2,'nombre':'Entrada'}]},
                         {'articulos':[],'productos':[],'metadata':{},'periodos':{}},[recipe],[],set(),date(2026,7,18))
        self.assertIsNone(report['articulos'][0]['cobertura_dias'])
        self.assertIn('opcionales',report['articulos'][0]['estado_cobertura'])
