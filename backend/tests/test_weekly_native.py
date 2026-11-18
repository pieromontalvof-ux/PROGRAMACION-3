import unittest
from unittest.mock import patch
from datetime import date, timedelta
from app.modules.inventarios import weekly


TODAY = date(2026, 11, 15)


def data():
    days = [TODAY - timedelta(days=n) for n in range(1, 29)]
    coverage = [dict(fecha=d, cobros=1, cobros_con_inventario=1) for d in days]
    consumption = [dict(fecha=d, id_producto=1, cantidad=2) for d in days]
    products = [dict(id_producto=1, nombre='Harina', stock_actual=3, stock_minimo=2,
                     stock_maximo=50, presentacion=6)]
    return consumption, products, coverage


def test_weekday_projection_ceils_packs_after_percentage_and_stock():
    consumption, products, coverage = data()
    result = weekly.calculate(TODAY, [], consumption, products, coverage, porcentaje=10)
    row = result['reposicion'][0]
    assert row['consumo_proyectado'] == 15.4
    assert row['cantidad_sin_redondear'] == 12.4
    assert row['cantidad_sugerida'] == 18
    assert row['paquetes_sugeridos'] == 3
    assert result['periodos']['semanas_completas'][-1] == {'desde': '2026-11-02', 'hasta': '2026-11-08', 'dias': 7}
    assert result['periodos']['proyeccion']['hasta'] == '2026-11-21'


def test_missing_inventory_day_is_unknown_and_all_products_are_returned():
    consumption, products, coverage = data()
    coverage[0]['cobros_con_inventario'] = 0
    products += [dict(id_producto=n, nombre=str(n), stock_actual=0, presentacion=1) for n in range(2, 9)]
    result = weekly.calculate(TODAY, [], consumption, products, coverage)
    assert len(result['productos']) == 8
    assert not result['reposicion']
    assert result['productos'][0]['cantidad_sugerida'] is None
    assert result['metadata']['dias_con_cobros'] == 28
    assert result['metadata']['dias_con_inventario'] == 27


def test_presentation_changes_and_week_comparisons_keep_dates():
    consumption, products, coverage = data()
    items = [dict(fecha=TODAY-timedelta(days=1), id_presentacion=1, id_promocion=None, nombre='A', cantidad=12),
             dict(fecha=TODAY-timedelta(days=8), id_presentacion=1, id_promocion=None, nombre='A', cantidad=8)]
    result = weekly.calculate(TODAY, items, consumption, products, coverage)
    row = result['articulos'][0]
    assert (row['cantidad'], row['cantidad_anterior'], row['variacion_porcentaje']) == (12, 8, 50)
    assert len(row['semanas']) == 4


class WeeklyNativeTests(unittest.TestCase):
    def test_endpoint_uses_session_local_and_validates_percentage(self):
        from app import create_app
        from flask_jwt_extended import create_access_token
        app = create_app()
        app.config['JWT_SECRET_KEY'] = 'weekly-tests-only-at-least-32-characters'
        client = app.test_client()
        url = '/api/inventario-operativo/plan-semanal'
        self.assertEqual(client.get(url).status_code, 401)
        with app.app_context():
            token = create_access_token(identity='2', additional_claims={
                'tipo_token':'operativo','id_perfil':2,'id_local':7})
        headers = {'Authorization':'Bearer '+token}
        with patch('app.core.extensions.db.session.execute') as execute, \
             patch('app.modules.inventarios.operativo.contexto', return_value=(7,2,2)), \
             patch('app.modules.inventarios.weekly.report', return_value={}) as report:
            execute.return_value.scalar.return_value = True
            self.assertEqual(client.get(url+'?local=999&porcentaje=10', headers=headers).status_code, 200)
            self.assertEqual(report.call_args.args[0], 7)
            for value in ('NaN','Infinity','-1','1001','oops'):
                self.assertEqual(client.get(url+'?porcentaje='+value, headers=headers).status_code, 400)

    def test_unknown_stock_and_ineligible_suppliers_cannot_be_ordered(self):
        consumption, products, coverage = data()
        products[0]['stock_actual'] = None
        result = weekly.calculate(TODAY, [], consumption, products, coverage)
        self.assertEqual(result['reposicion'], [])
        self.assertIsNone(result['productos'][0]['consumo_proyectado'])
        products[0].update(stock_actual=0, compra_habilitada=False)
        result = weekly.calculate(TODAY, [], consumption, products, coverage)
        self.assertEqual(result['reposicion'], [])
        self.assertTrue(result['advertencias'])

    def test_weekday_projection_ceils_packs_after_percentage_and_stock(self):
        test_weekday_projection_ceils_packs_after_percentage_and_stock()

    def test_missing_inventory_day_is_unknown_and_all_products_are_returned(self):
        test_missing_inventory_day_is_unknown_and_all_products_are_returned()

    def test_presentation_changes_and_week_comparisons_keep_dates(self):
        test_presentation_changes_and_week_comparisons_keep_dates()
