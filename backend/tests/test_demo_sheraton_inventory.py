"""Safety checks for the authorized local inventory fixture."""
import importlib.util
import unittest
from pathlib import Path
from decimal import Decimal


def test_plan_has_fourteen_dates_and_positive_varied_counts():
    path = Path(__file__).resolve().parents[1] / 'scripts/demo_sheraton_inventory.py'
    assert path.exists(), 'The protected inventory loader must exist'
    spec = importlib.util.spec_from_file_location('sheraton_inventory_fixture', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert len(module.dates()) == 14
    assert str(module.dates()[0]) == '2026-11-01'
    assert str(module.dates()[-1]) == '2026-11-14'
    product = dict(id_producto=7, unidad='KGM', presentacion=Decimal('1'), stock_minimo=Decimal('5'))
    values = [module.fictional_count(product, day) for day in module.dates()]
    assert all(v > 0 for v in values)
    assert len(set(values)) > 1
    product['unidad'] = 'C62'
    assert all(module.fictional_count(product, day) % 1 == 0 for day in module.dates())
    import uuid
    assert module.digest({'clave': uuid.UUID(int=0)}) == module.digest({'clave': str(uuid.UUID(int=0))})


def load_tests(loader, tests, pattern):
    return unittest.TestSuite([unittest.FunctionTestCase(test_plan_has_fourteen_dates_and_positive_varied_counts)])
