import unittest
from decimal import Decimal
from unittest.mock import patch
from app.modules.compras.service import _calcular_sugerencia, obtener_pedido_sugerido
from app.agents.compras.agent import run

class PurchaseMarginTests(unittest.TestCase):
    def test_margin_is_selected_before_subtracting_stock(self):
        product = {'consumo_total': 100, 'stock_actual': 20, 'presentacion': 1}
        self.assertEqual(_calcular_sugerencia(product, Decimal('0')), 80)
        self.assertEqual(_calcular_sugerencia(product, Decimal('35')), 115)

    def test_invalid_margin_is_rejected_before_querying(self):
        for value in ('', '-1', 'NaN', 'Infinity', '1001', 'abc'):
            with self.subTest(value=value), patch('app.modules.compras.service.listar_productos_para_compra') as rows:
                data, status = obtener_pedido_sugerido(value)
                self.assertEqual(status, 400)
                rows.assert_not_called()

    def test_new_order_asks_for_margin_without_calling_model(self):
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.agents.compras.agent.run_specialist') as model:
            result = run({}, 'Quiero hacer un pedido')
            self.assertIsNone(result['plan'])
            self.assertIn('porcentaje', result['respuesta'])
            model.assert_not_called()

    def test_explicit_margin_reaches_specialist(self):
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.agents.compras.agent.run_specialist', return_value={'plan': None}) as model:
            run({}, 'Quiero un pedido con 35%')
            model.assert_called_once()

    def test_assistant_uses_selected_margin_once_in_native_calculation(self):
        from app.modules.asistente_ia import purchases
        product = {'id_producto': 1, 'codigo': 'A1', 'nombre': 'Insumo', 'unidad': 'unidad',
                   'presentacion': 1, 'stock_minimo': 0, 'stock_actual': 20, 'consumo_total': 100,
                   'id_categoria': 1, 'categoria': 'A', 'id_proveedor': 1, 'proveedor': 'B'}
        with patch('app.modules.compras.service.listar_productos_para_compra', return_value=[product]):
            response, status = obtener_pedido_sugerido('35')
        self.assertEqual(status, 200)
        self.assertEqual(response['productos'][0]['cantidad_sugerida'], 115)
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.native', return_value=response) as native:
            plan = purchases.prepare({}, 'crear', None, {'porcentaje_general': 35, 'adicionales': []})
        native.assert_called_once_with('/ordenes-compra/pedido-sugerido?porcentaje=35')
        self.assertEqual(plan['datos']['detalles'][0]['cantidad_solicitada'], 115)

    def test_pack_rounding_exposes_different_raw_needs(self):
        product = {'id_producto': 1, 'codigo': 'C-009', 'nombre': 'Alitas', 'unidad': 'unidad',
                   'presentacion': 24, 'stock_minimo': 0, 'stock_actual': -40, 'consumo_total': 40,
                   'id_categoria': 1, 'categoria': 'A', 'id_proveedor': 1, 'proveedor': 'B'}
        for margin, raw in ((10, 84), (20, 88), (30, 92)):
            with self.subTest(margin=margin), patch('app.modules.compras.service.listar_productos_para_compra', return_value=[product]):
                response, status = obtener_pedido_sugerido(margin)
                row = response['productos'][0]
                self.assertEqual(status, 200)
                self.assertEqual(row['cantidad_sugerida'], 96)
                self.assertEqual(row['cantidad_sin_redondear'], raw)
                self.assertEqual(row['paquetes_sugeridos'], 4)
