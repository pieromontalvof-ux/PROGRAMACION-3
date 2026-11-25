import unittest
from datetime import date
from decimal import Decimal


class VariedWeekRulesTests(unittest.TestCase):
    def test_single_day_funds_stock_and_uses_distinct_idempotency_tag(self):
        from unittest.mock import patch
        from scripts import demo_varied_week as loader
        with patch.multiple(loader, START=loader.START, END=loader.END, DAYS=loader.DAYS, TAG=loader.TAG):
            loader.configure_period(date(2026,11,24),date(2026,11,24))
            self.assertEqual(loader.DAYS,[date(2026,11,24)])
            self.assertNotEqual(loader.TAG,'DEMO-SEMANA-VARIADA-20261117-23-V1')
            delivery=loader.deliveries({date(2026,11,24):{1:Decimal('15')}},{1:Decimal('-2')},{1:Decimal('10')})
            self.assertEqual(delivery,{date(2026,11,24):{1:Decimal('27.000')}})

    def test_schedule_varies_tickets_payments_and_respects_recipe_line_values(self):
        from scripts.demo_varied_week import schedule
        menu = [{'id_presentacion': n, 'nombre': 'Producto ' + str(n), 'precio': Decimal('12.50')} for n in range(1, 31)]
        days = [date(2026, 11, d) for d in range(17, 24)]
        runs = [schedule(1, day, menu) for day in days]
        self.assertTrue(all(12 <= len(run) <= 25 for run in runs))
        self.assertGreater(len({len(run) for run in runs}), 2)
        self.assertEqual({ticket['metodo'] for run in runs for ticket in run}, {'EFECTIVO', 'TARJETA'})
        self.assertEqual(runs, [schedule(1, day, menu) for day in days])
        for run in runs:
            for ticket in run:
                self.assertEqual(ticket['total'], sum(line['precio'] * line['cantidad'] for line in ticket['lineas']))

    def test_receipts_fund_consumption_and_positive_buffer_in_three_deliveries(self):
        from scripts.demo_varied_week import deliveries
        usage = {date(2026, 11, d): {1: Decimal(d)} for d in range(17, 24)}
        plan = deliveries(usage, {1: Decimal('-2')}, {1: Decimal('10')})
        self.assertEqual(set(plan), {date(2026, 11, 17), date(2026, 11, 20), date(2026, 11, 23)})
        stock = Decimal('-2')
        for day, amounts in usage.items():
            stock += plan.get(day, {}).get(1, 0) - amounts[1]
            self.assertGreaterEqual(stock, 0)
        self.assertEqual(stock, Decimal('10'))
