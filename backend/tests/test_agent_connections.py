import json
import unittest
from unittest.mock import patch
import test_agent_library
from app.modules.asistente_ia import configuration
from app.agents.demanda import agent as demand_agent


class AgentConnectionTests(unittest.TestCase):
    setUp = test_agent_library.AgentLibraryTests.setUp
    token = test_agent_library.AgentLibraryTests.token

    def test_add_connection_persists_without_changing_skill_or_defaults(self):
        path = '/api/asistente-ia/biblioteca/demanda'
        before = self.client.get(path, headers=self.headers).json
        self.assertEqual(before['configuracion']['accesos'], {'demanda_rotacion': ['consultar']})
        self.assertEqual(before['accesos_disponibles']['promociones'], ['consultar'])
        accesses = {**before['configuracion']['accesos'], 'promociones': ['consultar']}
        saved = self.client.put(path + '/accesos', headers=self.headers, json={'accesos': accesses, 'revision': 0})
        self.assertEqual(saved.status_code, 200, saved.json)
        self.assertEqual(saved.json['configuracion']['skills'], before['configuracion']['skills'])
        self.assertEqual(saved.json['configuracion']['accesos'], accesses)
        removed = self.client.put(path + '/accesos', headers=self.headers, json={'accesos': {'demanda_rotacion': ['consultar']}, 'revision': 1})
        self.assertEqual(removed.status_code, 200, removed.json)

    def test_connection_cannot_grant_unknown_or_write_capability(self):
        for resource, actions in [('externo', ['consultar']), ('promociones', ['consultar', 'crear'])]:
            result = self.client.put('/api/asistente-ia/biblioteca/demanda/accesos', headers=self.headers,
                                     json={'accesos': {'demanda_rotacion': ['consultar'], resource: actions}, 'revision': 0})
            self.assertEqual(result.status_code, 400, result.json)

    def test_added_connection_is_used_and_filtered_by_profile(self):
        config = configuration.effective('demanda')
        config['accesos']['promociones'] = ['consultar']
        calls = [{'type': 'function_call', 'name': 'consultar', 'call_id': '1', 'arguments': json.dumps({'recurso': 'promociones', 'busqueda': '', 'desde': 0})}]
        answer = [{'content': [{'type': 'output_text', 'text': 'Promoción consultada.'}]}]
        with patch.object(configuration, 'saved', return_value=config), patch('app.agents.runtime.tools.allowed', return_value=True), patch('app.agents.runtime.tools.query', return_value={'registros': []}) as query, patch('app.agents.runtime.provider.respond', side_effect=[calls, answer]) as respond:
            demand_agent.run({'local_activo': None}, 'Consultar promociones')
            names = next(t for t in respond.call_args_list[0].args[1] if t['name'] == 'consultar')['parameters']['properties']['recurso']['enum']
            self.assertIn('promociones', names)
            query.assert_called_once()
        with patch.object(configuration, 'saved', return_value=config), patch('app.agents.runtime.tools.allowed', side_effect=lambda session, resource, action='consultar': resource != 'promociones'), patch('app.agents.runtime.tools.query') as query, patch('app.agents.runtime.provider.respond', side_effect=[calls, answer]):
            demand_agent.run({'local_activo': None}, 'Consultar promociones')
            query.assert_not_called()

    def test_removed_connection_cannot_be_called_by_model(self):
        config = configuration.effective('demanda')
        calls = [{'type': 'function_call', 'name': 'consultar', 'call_id': '1', 'arguments': json.dumps({'recurso': 'promociones', 'busqueda': '', 'desde': 0})}]
        with patch.object(configuration, 'saved', return_value=config), patch('app.agents.runtime.tools.allowed', return_value=True), patch('app.agents.runtime.tools.query') as query, patch('app.agents.runtime.provider.respond', side_effect=[calls, [{'content': []}]]):
            demand_agent.run({'local_activo': None}, 'Consultar promociones')
            query.assert_not_called()

    def test_inventory_specialist_receives_added_generic_connection(self):
        from app.agents.inventario import agent
        config = configuration.effective('inventario')
        config['accesos']['promociones'] = ['consultar']
        calls = [{'type': 'function_call', 'name': 'consultar', 'call_id': '1', 'arguments': json.dumps({'recurso': 'promociones', 'busqueda': '', 'desde': 0})}]
        with patch.object(configuration, 'saved', return_value=config), patch('app.agents.runtime.tools.allowed', return_value=True), patch('app.agents.runtime.tools.query', return_value={'registros': []}) as query, patch('app.agents.runtime.provider.respond', side_effect=[calls, [{'content': []}]]):
            agent.run({'local_activo': None}, 'Consultar promociones')
            query.assert_called_once()

    def test_dedicated_agents_do_not_offer_unsupported_runtime_connections(self):
        self.assertNotIn('promociones', configuration.supported('eventos'))
        self.assertNotIn('promociones', configuration.supported('orquestador'))

    def test_demand_inventory_connection_supports_date_filters(self):
        config = configuration.effective('demanda')
        config['accesos']['mix_ventas'] = ['consultar']
        filters = {'desde': '2026-10-01', 'hasta': '2026-10-07'}
        calls = [{'type': 'function_call', 'name': 'consultar_inventario', 'call_id': '1', 'arguments': json.dumps({'recurso': 'mix_ventas', 'filtros_json': json.dumps(filters)})}]
        with patch.object(configuration, 'saved', return_value=config), patch('app.agents.runtime.tools.allowed', return_value=True), patch('app.agents.runtime.inventory.read', return_value={}) as read, patch('app.agents.runtime.provider.respond', side_effect=[calls, [{'content': []}]]) as model:
            demand_agent.run({'local_activo': None}, 'Comparar ventas')
            read.assert_called_once_with({'local_activo': None}, 'mix_ventas', filters)
            self.assertIn('consultar_inventario', [tool['name'] for tool in model.call_args_list[0].args[1]])

    def test_only_generic_inventory_connection_never_emits_empty_enum(self):
        from app.agents.inventario import agent
        config = configuration.effective('inventario')
        config['accesos'] = {'promociones': ['consultar']}
        with patch.object(configuration, 'saved', return_value=config), patch('app.agents.runtime.tools.allowed', return_value=True), patch('app.agents.runtime.provider.respond', return_value=[{'content': []}]) as model:
            agent.run({'local_activo': None}, 'Consultar promociones')
            self.assertNotIn('consultar_inventario', [tool['name'] for tool in model.call_args.args[1]])
