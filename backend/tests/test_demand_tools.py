import json
import unittest
from unittest.mock import patch
from app import create_app
from app.multiagente.agents.orchestrator.router import route
from app.multiagente.api import demand
from app.multiagente.api.provider import AssistantError
from flask_jwt_extended import create_access_token


class DemandToolsTests(unittest.TestCase):
    def test_http_route_authentication_date_validation_and_local_scope(self):
        app = create_app()
        app.config['JWT_SECRET_KEY'] = 'demand-tests-only-at-least-32-characters'
        client = app.test_client()
        url = '/api/inventario-operativo/demanda?desde=2020-01-01&hasta=2020-01-02'
        self.assertEqual(client.get(url).status_code, 401)
        with app.app_context():
            token = create_access_token(identity='2', additional_claims={
                'tipo_token': 'operativo', 'id_perfil': 2, 'id_local': 7})
        headers = {'Authorization': 'Bearer ' + token}
        with patch('app.core.extensions.db.session.execute') as execute, \
             patch('app.modules.inventarios.operativo.contexto', return_value=(7, 2, 2)), \
             patch('app.modules.inventarios.demand.report', return_value={'productos': [], 'articulos': []}) as report:
            execute.return_value.scalar.return_value = True
            self.assertEqual(client.get(url, headers=headers).status_code, 200)
            self.assertEqual(report.call_args.args[0], 7)
            report.reset_mock()
            self.assertEqual(client.get('/api/inventario-operativo/demanda?desde=2020-01-02&hasta=2020-01-01', headers=headers).status_code, 400)
            self.assertEqual(client.get('/api/inventario-operativo/demanda?desde=2999-01-01&hasta=2999-01-02', headers=headers).status_code, 400)
            report.assert_not_called()

    def test_routes_preserve_purchase_and_catalog_intentions(self):
        for instruction in ('Qué cerveza tiene más salida', 'Analiza las ventas de la carta',
                            'Cuánto durará la IPA', 'Qué insumos tienen menor cobertura',
                            'Rotación del queso', 'Qué se vende más', 'Cuál tiene mayor recibimiento',
                            'Analiza qué tanto salió una cerveza'):
            self.assertEqual(route(instruction), 'demanda', instruction)
        self.assertEqual(route('Prepara un pedido según la rotación'), 'compras')
        self.assertEqual(route('Consulta el stock'), 'inventario')
        self.assertEqual(route('Crear receta'), 'recetas')
        self.assertEqual(route('Y del queso', 'Analiza la rotación'), 'demanda')

    def test_permission_needs_stock_and_sales_and_operational_profile(self):
        session = {'menu': [{'id_opcion_menu': m, 'permisos': {'consultar': True}} for m in (15, 37)]}
        with patch.object(demand, 'get_jwt', return_value={'id_perfil': 2}):
            self.assertTrue(demand.allowed(session))
            self.assertFalse(demand.allowed(session, 'crear'))
            self.assertFalse(demand.allowed({'menu': session['menu'][:1]}))
        for role in (1, 4):
            with patch.object(demand, 'get_jwt', return_value={'id_perfil': role}):
                self.assertFalse(demand.allowed(session))

    def test_invalid_filters_cannot_override_local_or_expand_query(self):
        with patch('app.multiagente.api.tools.authorize'), patch('app.multiagente.api.tools.native') as native:
            for filters in ({'id_local': 2}, {'desde': 'bad'}, {'hasta': '2999-01-01'},
                            {'desde': '2020-01-01', 'hasta': '2026-01-01'},
                            {'desde_registro': True}, {'busqueda': 'x'*201}, []):
                with self.assertRaises(AssistantError):
                    demand.read({}, filters)
            native.assert_not_called()

    def test_filter_before_pagination_and_bound_each_ranking(self):
        data = {'desde': '2026-01-01', 'hasta': '2026-01-31', 'metodologia': 'calendario',
                'productos': [dict(nombre='IPA', id_producto=i) for i in range(45)],
                'articulos': [dict(nombre='Hamburguesa'), dict(nombre='IPA 500 ml')]}
        with patch('app.multiagente.api.tools.authorize'), patch('app.multiagente.api.tools.native', return_value=data):
            r = demand.read({}, {'desde': '2026-01-01', 'hasta': '2026-01-31', 'busqueda': 'ipa', 'desde_registro': 20})
        self.assertEqual(len(r['registros']), 20)
        self.assertEqual(r['total'], 45)
        self.assertTrue(r['hay_mas'])
        self.assertEqual(r['contexto']['total_articulos'], 1)

    def test_runtime_exposes_read_only_analysis_and_purchase_can_share_it(self):
        from app.multiagente.agents.demanda.agent import run
        answer = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Informe'}]}]
        call = [{'type': 'function_call', 'call_id': 'demand', 'name': 'analizar_demanda',
                 'arguments': json.dumps({'filtros_json': '{"desde":"2026-07-18","hasta":"2026-11-17"}'})}]
        app = create_app()
        with app.test_request_context(), patch('app.multiagente.api.tools.allowed', side_effect=lambda s,r,a='consultar': a=='consultar'), \
             patch('app.multiagente.api.demand.read', return_value={'recurso': 'demanda_rotacion'}) as read, \
             patch('app.multiagente.api.provider.respond', side_effect=[call, answer]) as model:
            result = run({'menu': []}, 'Analiza la rotación')
        read.assert_called_once_with({'menu': []}, {'desde':'2026-07-18','hasta':'2026-11-17','detalle_productos':True})
        names = {tool['name'] for tool in model.call_args.args[1]}
        self.assertIn('analizar_demanda', names)
        self.assertNotIn('preparar_cambio', names)
        self.assertEqual(result['consultas'], [{'recurso': 'demanda_rotacion'}])


if __name__ == '__main__':
    unittest.main()
