import unittest
from datetime import date
from decimal import Decimal

from app.modules.inventarios.demand import calculate


class DemandCalculationTests(unittest.TestCase):
    def report(self, products, items=()):
        return calculate(date(2026, 10, 1), date(2026, 10, 10), items, products)

    def test_consumption_and_coverage_use_inclusive_calendar_days(self):
        r = self.report([dict(id_producto=1, nombre='IPA', unidad='L', stock_actual=18,
                              consumo_ventas=Decimal('60'), entradas=90)])
        p = r['productos'][0]
        self.assertEqual(p['consumo_diario'], 6)
        self.assertEqual(p['cobertura_dias'], 3)
        self.assertEqual(p['prioridad'], 'REVISAR_REPOSICION')
        self.assertEqual(r['dias_calendario'], 10)

    def test_zero_sales_does_not_invent_coverage_or_rejection(self):
        p = self.report([dict(id_producto=2, nombre='Queso', unidad='kg', stock_actual=5,
                              consumo_ventas=0, entradas=10)])['productos'][0]
        self.assertIsNone(p['cobertura_dias'])
        self.assertEqual(p['prioridad'], 'SIN_CONSUMO_REGISTRADO')

    def test_shared_ingredients_are_already_aggregated_and_units_stay_separate(self):
        r = self.report([
            dict(id_producto=1, nombre='Queso', unidad='kg', stock_actual=3, consumo_ventas=2, entradas=0),
            dict(id_producto=2, nombre='IPA', unidad='L', stock_actual=-1, consumo_ventas=20, entradas=0),
        ], [dict(id_presentacion=8, nombre='Hamburguesa', cantidad=10, total=250)])
        self.assertEqual(r['articulos'][0]['ventas_diarias'], 1)
        self.assertEqual(r['productos'][0]['cobertura_dias'], 0)
        self.assertEqual({p['unidad'] for p in r['productos']}, {'kg', 'L'})
        self.assertNotIn('consumo_total', r)

    def test_empty_period_keeps_unknowns_explicit(self):
        self.assertEqual(self.report([])['productos'], [])


if __name__ == '__main__':
    unittest.main()
