"""Historical fixture must fund consumption without changing current stock."""
import importlib.util
from pathlib import Path
from datetime import date, timedelta
from decimal import Decimal


def load():
    path = Path(__file__).resolve().parents[1] / 'scripts/demo_sheraton_four_months.py'
    assert path.exists(), 'Four month protected loader is missing'
    spec = importlib.util.spec_from_file_location('four_month_fixture', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_receipts_fund_each_week_without_changing_current_stock():
    m = load()
    start = date(2026, 7, 15)
    days = [(start + timedelta(days=i), {1: Decimal('1.250'), 2: Decimal(i+1)}) for i in range(9)]
    receipts = m.weekly_receipts(days)
    assert receipts[start] == {1: Decimal('8.750'), 2: Decimal(28)}
    assert receipts[date(2026, 7, 22)] == {1: Decimal('2.500'), 2: Decimal(17)}
    stock = {1: Decimal(0), 2: Decimal(0)}
    for day, consumed in days:
        for pid, quantity in receipts.get(day, {}).items():
            stock[pid] += quantity
        for pid, quantity in consumed.items():
            stock[pid] -= quantity
        assert min(stock.values()) >= 0
    assert stock == {1: 0, 2: 0}


def test_sales_vary_across_weeks_and_keep_recipe_identifiers():
    m = load()
    menu = [dict(id_presentacion=8, nombre='Demo', precio=Decimal('20'))]
    schedule = m.sale_schedule(menu, date(2026, 7, 15), date(2026, 8, 11))
    assert len(schedule) == 28
    weekly = [sum(lines[0]['cantidad'] for _, lines in schedule[i:i+7]) for i in range(0,28,7)]
    assert len(set(weekly)) >= 3
    assert all(lines[0]['id_presentacion'] == 8 and lines[0]['cantidad'] > 0 for _,lines in schedule)


def test_receipts_reset_at_preserved_closed_day():
    m = load()
    result=m.weekly_receipts([(date(2026,9,25),{1:Decimal(2)}),(date(2026,9,27),{1:Decimal(3)})])
    assert result == {date(2026,9,25):{1:Decimal(2)}, date(2026,9,27):{1:Decimal(3)}}


def load_tests(loader, tests, pattern):
    import unittest
    return unittest.TestSuite(unittest.FunctionTestCase(f) for f in (
        test_receipts_fund_each_week_without_changing_current_stock,
        test_sales_vary_across_weeks_and_keep_recipe_identifiers,
        test_receipts_reset_at_preserved_closed_day))
