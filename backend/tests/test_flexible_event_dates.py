import unittest
from datetime import date,datetime,timezone
from unittest.mock import patch
import test_purchase_review as fixtures
from app.multiagente.agents.eventos.period import resolve
from app.multiagente.agents.orchestrator import purchase_flow as flow


class FlexibleEventDatesTests(unittest.TestCase):
    def test_current_month_phrases_and_polite_replies(self):
        today=date(2026,11,16)
        for phrase in ('hasta el 22 de este mismo mes','hasta el 22 de este mes',
                       'hasta el dia 22 de este mes, por favor','busca hasta el 22 de este mismo mes',
                       'si, hasta el 22','hasta el 22 por favor'):
            with self.subTest(phrase=phrase):
                self.assertEqual(resolve(phrase,today,allow_day_only=True),('2026-11-16','2026-11-22'))
        self.assertIsNone(resolve('22%',today,allow_day_only=True))
        self.assertIsNone(resolve('precio de 22 soles',today,allow_day_only=True))
        with self.assertRaises(ValueError):resolve('hasta el 31 de este mismo mes',today)

    def test_delivery_uses_explicit_weekly_context_only(self):
        self.assertEqual(resolve('Busca eventos hasta la proxima entrega',date(2026,11,16),next_delivery=date(2026,11,23)),
                         ('2026-11-16','2026-11-23'))
        self.assertIsNone(resolve('hasta la proxima entrega',date(2026,11,16)))


class FlexibleDateConversationTests(unittest.TestCase):
    setUp=fixtures.PurchaseReviewTests.setUp
    review=fixtures.PurchaseReviewTests.review

    def test_screenshot_reply_resumes_original_task(self):
        original=fixtures.REQUEST.replace('de los próximos siete días','')
        first,_,_,_=self.review(instruction=original)
        with patch.object(flow,'datetime') as clock:
            clock.now.return_value=datetime(2026,11,16,12,tzinfo=timezone.utc)
            result,search,demand,_=self.review(instruction='hasta el 22 de este mismo mes',token=first['flujo_compra'])
        self.assertEqual(search.call_count,1)
        self.assertEqual(demand.call_count,1)
        self.assertEqual(flow.load(result['flujo_compra'])['periodo_eventos'],['2026-11-16','2026-11-22'])
        self.assertNotIn('Solo falta la fecha',result['respuesta'])

    def test_weekly_next_delivery_requires_user_confirmation(self):
        original=fixtures.REQUEST.replace('de los próximos siete días','hasta la próxima entrega')
        with patch.object(flow,'datetime') as clock:
            clock.now.return_value=datetime(2026,11,16,12,tzinfo=timezone.utc)
            result,search,_,_=self.review(instruction=original)
        self.assertEqual(search.call_count,0)
        self.assertNotIn('dias_abastecimiento',flow.load(result['flujo_compra']))
        self.assertIn('¿Hasta qué fecha necesitas que alcance este pedido?',result['respuesta'])
