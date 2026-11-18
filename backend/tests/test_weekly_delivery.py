import unittest
from datetime import date
from unittest.mock import patch
from app.modules.inventarios.weekly import calculate
from app.multiagente.agents.orchestrator import purchase_review

class WeeklyDeliveryTests(unittest.TestCase):
    def test_next_delivery_is_seven_days_later_without_extra_consumption_day(self):
        periods=calculate(date(2026,11,15),[],[],[],[])['periodos']
        self.assertEqual(periods['proxima_entrega'],'2026-11-22')
        self.assertEqual(periods['proyeccion']['dias'],7)

    def test_both_review_paths_show_next_delivery(self):
        periods={'proyeccion':{'desde':'2026-11-15','hasta':'2026-11-21','dias':7},'proxima_entrega':'2026-11-22'}
        weekly={'periodos':periods,'reposicion':[]}
        demand={'consultas':[{'contexto':{'plan_semanal':weekly}}]}
        lines,_=purchase_review.replenishment({},demand)
        self.assertIn('próxima entrega: 2026-11-22',' '.join(lines))
        self.assertNotIn('al 2026-11-21',' '.join(lines))
        with patch.object(purchase_review,'base',return_value={'horizonte':'semanal','periodos':periods,'productos':[]}):
            lines,_=purchase_review.replenishment({},None)
        self.assertIn('próxima entrega: 2026-11-22',' '.join(lines))
