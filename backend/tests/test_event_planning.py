import unittest
from datetime import date, datetime, timezone
from unittest.mock import patch

import test_purchase_review as fixtures
from app.multiagente.agents.eventos import agent
from app.multiagente.agents.orchestrator import purchase_flow as flow, purchase_review


class EventPeriodTests(unittest.TestCase):
    def test_short_date_answers_use_current_month_without_confusing_percentages(self):
        from app.multiagente.agents.eventos.period import resolve
        today=date(2026,11,14)
        for phrase in ('hasta el 18','hasta 18','hasta el 18 de este mes'):
            self.assertEqual(resolve(phrase,today),('2026-11-14','2026-11-18'))
        self.assertEqual(resolve('18',today,allow_day_only=True),('2026-11-14','2026-11-18'))
        self.assertIsNone(resolve('18',today))
        self.assertIsNone(resolve('18%',today,allow_day_only=True))
        for phrase in ('hasta el 31','hasta el 5'):
            with self.assertRaises(ValueError):
                resolve(phrase,today)

    def test_weekday_deadlines_and_relative_days(self):
        from app.multiagente.agents.eventos.period import resolve
        today = date(2026, 11, 11)
        self.assertEqual(resolve('hasta el próximo miercoles', today), ('2026-11-11', '2026-11-18'))
        self.assertEqual(resolve('hasta el miércoles de la próxima semana', today), ('2026-11-11', '2026-11-18'))
        self.assertEqual(resolve('hasta el viernes', today), ('2026-11-11', '2026-11-13'))
        self.assertEqual(resolve('el próximo miércoles', today), ('2026-11-18', '2026-11-18'))
        self.assertEqual(resolve('hasta mañana', today), ('2026-11-11', '2026-11-12'))
        self.assertEqual(resolve('hasta el próximo lunes', date(2026, 11, 15)), ('2026-11-15', '2026-11-16'))

    def test_explicit_periods_use_lima_calendar_and_include_today(self):
        from app.multiagente.agents.eventos.period import resolve
        today = date(2026, 11, 6)
        self.assertEqual(resolve('próximos siete días', today), ('2026-11-06', '2026-11-12'))
        self.assertEqual(resolve('hasta el 15 de noviembre', today), ('2026-11-06', '2026-11-15'))
        self.assertEqual(resolve('del 2026-11-08 al 2026-11-12', today), ('2026-11-08', '2026-11-12'))
        self.assertIsNone(resolve('revisa eventos y ventas de los últimos 30 días', today))
        self.assertEqual(resolve('Analiza ventas y revisa eventos de los próximos siete días', today), ('2026-11-06', '2026-11-12'))
        self.assertEqual(resolve('Busca eventos el 2026-11-15', today), ('2026-11-15', '2026-11-15'))

    def test_invalid_or_past_period_does_not_search(self):
        with patch.object(agent, 'search_response') as search:
            report = agent.events('eventos hasta 2020-01-01', local={'nombre':'Mi bar','direccion':'Av. Test 100'})
        search.assert_not_called()
        self.assertEqual(report['estado'], 'fechas_invalidas')

    def test_search_uses_requested_dates_and_active_bar_without_hardcoded_venues(self):
        with patch.object(agent, 'datetime') as clock, patch.object(agent, 'search_response', return_value={'status':'completed','output':[]}) as search:
            clock.now.return_value = datetime(2026, 11, 6, 14, tzinfo=timezone.utc)
            agent.events('eventos del 2026-11-08 al 2026-11-15', local={'nombre':'Barranco','direccion':'Av. Test 100'})
        prompt = search.call_args.args[0]['input']
        self.assertIn('2026-11-08 al 2026-11-15', prompt)
        self.assertIn('Barranco', prompt)
        self.assertIn('congresos', prompt)
        self.assertIn('"candidatos"', prompt)
        self.assertIn('hoteles', prompt)
        self.assertNotIn('Sheraton', prompt)

    def test_purchase_summary_keeps_sourced_event_table_and_period(self):
        table = '| Evento | Fecha | Lugar |\n| --- | --- | --- |\n| [Congreso](https://example.org) | 6 nov | Hotel |'
        result = {'respuesta':'Sede: Mi bar\nPeríodo: 2026-11-06 al 2026-11-12\n\n'+table,
                  'consultas':[{'recurso':'eventos_cercanos','registros':[{'estado':'consultado','informe':table}]}]}
        summary = purchase_review.event_brief(result)
        self.assertIn(table, summary)
        self.assertIn('2026-11-12', summary)


class PurchaseDateConversationTests(unittest.TestCase):
    setUp = fixtures.PurchaseReviewTests.setUp
    review = fixtures.PurchaseReviewTests.review
    def test_hasta_el_18_continues_pending_original_purchase(self):
        request=fixtures.REQUEST.replace('de los próximos siete días','')
        first,_,_,_=self.review(instruction=request)
        with patch.object(flow,'datetime') as clock:
            clock.now.return_value=datetime(2026,11,14,14,tzinfo=timezone.utc)
            second,search,demand,native=self.review(instruction='hasta el 18',token=first['flujo_compra'])
        self.assertEqual(search.call_count,1)
        self.assertEqual(demand.call_count,1)
        self.assertEqual(native.call_count,2)
        self.assertEqual(flow.load(second['flujo_compra'])['periodo_eventos'],['2026-11-14','2026-11-18'])
        self.assertNotIn('¿Hasta qué fecha',second['respuesta'])
        self.assertIsNone(second['plan'])

    def test_next_wednesday_continues_pending_purchase_without_repeating_question(self):
        request = fixtures.REQUEST.replace('de los próximos siete días', '')
        first, _, _, _ = self.review(instruction=request)
        with patch.object(flow, 'datetime') as clock:
            clock.now.return_value = datetime(2026, 11, 11, 14, tzinfo=timezone.utc)
            second, search, demand, native = self.review(instruction='hasta el próximo miercoles', token=first['flujo_compra'])
        self.assertEqual(search.call_count, 1)
        self.assertEqual(demand.call_count, 1)
        self.assertEqual(native.call_count, 2)
        self.assertEqual(flow.load(second['flujo_compra'])['periodo_eventos'], ['2026-11-11', '2026-11-18'])
        self.assertIn('2026-11-18', second['respuesta'])
        self.assertNotIn('¿Hasta qué fecha', second['respuesta'])
        self.assertIsNone(second['plan'])

    def test_missing_period_asks_before_search_and_continues_original_request(self):
        request = fixtures.REQUEST.replace('de Sheraton', '').replace('de los próximos siete días', '')
        first, search, demand, native = self.review(instruction=request)
        search.assert_not_called()
        demand.assert_not_called()
        native.assert_not_called()
        self.assertIn('¿Hasta qué fecha', first['respuesta'])
        state = flow.load(first['flujo_compra'])
        self.assertEqual(state['paso'], 'fechas_eventos_futuros')
        second, search, demand, native = self.review(instruction='próximos siete días', token=first['flujo_compra'])
        self.assertEqual(search.call_count, 1)
        self.assertEqual(demand.call_count, 1)
        self.assertIn('Período de eventos confirmado', search.call_args.args[1])
        self.assertIn('qué conviene reponer', flow.load(second['flujo_compra'])['solicitud'])
        self.assertIsNone(second['plan'])
