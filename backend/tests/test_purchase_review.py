import unittest
from datetime import datetime,timedelta,timezone
from unittest.mock import patch
from flask import Flask

from app.multiagente.agents.orchestrator import purchase_flow as flow
from app.multiagente.api.provider import AssistantError


REQUEST = ('Quiero preparar el pedido de insumos de Sheraton. Revisa los eventos cercanos de los próximos siete días '
           'y analiza nuestras ventas y el stock disponible. Muéstrame qué conviene reponer y pregúntame qué incremento '
           'aplicar antes de preparar el pedido. No confirmes ninguna compra todavía.')
EVENTS = {'respuesta':'Informe largo de eventos', 'plan':None, 'consultas':[{
    'recurso':'eventos_cercanos','registros':[{'estado':'consultado','periodo':['2026-11-06','2026-11-12'],
        'informe':'### Eventos con cercanía verificada\nNo pude verificar eventos cercanos.\n'
                  '### Referencias sin cercanía verificada\n- Concierto lejano. Cercanía por confirmar.\n' + 'Detalles. '*100,
        'fuentes':[{'titulo':'Fuente oficial','url':'https://example.org/evento'}]}]}]}
ANALYSIS = {'respuesta':'Ventas analizadas: 2026-10-08 al 2026-11-06. IPA: 20 ventas. Limón: stock 1 kg; cobertura 2 días.',
            'plan':None,'consultas':[{'recurso':'demanda_rotacion','total':1,'registros':[
                {'id_producto':1,'nombre':'Limón','stock_actual':1,'unidad':'KGM','cobertura_dias':2}],
                'contexto':{'desde':'2026-10-08','hasta':'2026-11-06','dias_calendario':30,
                            'articulos':[{'nombre':'IPA','cantidad':20,'ventas_diarias':.67}],'total_articulos':1}}]}
BASE = {'productos':[{'id_producto':1,'nombre':'Limón','unidad':'KGM','stock_actual':1,
                      'cantidad_sugerida':5,'cantidad_sin_redondear':4.6}],
        'diagnostico':{'motivo':'con_sugerencia','mensaje':'Consumo registrado en los últimos 30 días.'}}
STOCK = {'productos':[{'id_producto':1,'nombre':'Limón','unidad':'KGM','stock_actual':1,'stock_minimo':2,'estado_stock':'STOCK_BAJO'},
                       {'id_producto':2,'nombre':'Maracuyá','unidad':'LTR','stock_actual':0,'stock_minimo':1,'estado_stock':'AGOTADO'},
                       {'id_producto':3,'nombre':'Otro insumo','unidad':'LTR','stock_actual':None,'stock_minimo':1,'estado_stock':'SIN_CONTEO'}]}


class PurchaseReviewTests(unittest.TestCase):
    def test_natural_product_analysis_uses_the_same_weekly_review_before_margin(self):
        instruction=('quiero hacer un nuevo pedido semanal, que entrará el lunes 23 de este mes, '
                     'analiza los eventos hasta esa fecha y un análisis de los productos para saber como hacer los pedidos')
        from app.multiagente.agents.orchestrator import purchase_review
        self.assertTrue(purchase_review.requested(instruction))
        # The semantic interpreter supplies the confirmed delivery date.
        today=datetime.now(timezone(timedelta(hours=-5))).date()
        result,_,demand,_=self.review(instruction=f'Eventos del {today} al {today+timedelta(days=6)}. '+instruction)
        demand.assert_called_once()
        self.assertTrue(demand.call_args.kwargs['bounded'])
        self.assertTrue(demand.call_args.kwargs['filters']['semanal'])
        self.assertTrue(flow.load(result['flujo_compra'])['revision_completada'])
        self.assertNotIn('¿Quieres revisar las ventas',result['respuesta'])

    def setUp(self):
        self.app = Flask(__name__)
        self.app.config['SECRET_KEY'] = 'purchase-review-test-secret'
        self.ctx = self.app.app_context()
        self.ctx.push()
        self.addCleanup(self.ctx.pop)
        for target, kwargs in (
            ('app.multiagente.api.drafts.scope', {'return_value':{'usuario':1,'perfil':2,'local':4}}),
            ('app.multiagente.api.tools.authorize', {}),
            ('app.multiagente.api.configuration.authorize', {}),
        ):
            p = patch(target, **kwargs)
            p.start()
            self.addCleanup(p.stop)

    def review(self, events=EVENTS, analysis=ANALYSIS, base=BASE, instruction=REQUEST, token=None):
        with patch.object(flow.event_agent, 'run', return_value=events) as search, \
             patch.object(flow.demand_agent, 'run', return_value=analysis) as demand, \
             patch.object(flow.tools, 'native', side_effect=lambda path: STOCK if path == '/inventarios/stock' else base) as native, \
             patch.object(flow.purchase_agent, 'run', side_effect=AssertionError('No drafts during review')):
            result = flow.handle({'local_activo':{'nombre':'Sheraton'}}, instruction, token=token)
        return result, search, demand, native

    def test_explicit_sales_stock_and_replenishment_run_after_events_before_margin(self):
        result, search, demand, native = self.review()
        self.assertEqual(demand.call_count, 1)
        self.assertTrue(demand.call_args.kwargs['bounded'])
        self.assertEqual(native.call_args.args[0], '/ordenes-compra/pedido-sugerido?porcentaje=0&horizonte=semanal')
        self.assertIn('IPA', result['respuesta'])
        self.assertIn('Limón', result['respuesta'])
        self.assertIn('5 kg', result['respuesta'])
        self.assertIn('porcentaje', result['respuesta'])
        self.assertNotIn('¿Quieres revisar las ventas', result['respuesta'])
        self.assertLess(len(result['respuesta']), 1800)
        self.assertIsNone(result['plan'])
        self.assertEqual(flow.load(result['flujo_compra'])['paso'], 'porcentaje')
        self.assertEqual(search.call_count, 1)

    def test_event_failure_does_not_stop_sales_stock_and_base_reads(self):
        result, _, demand, native = self.review(events={'respuesta':'Falló la consulta de eventos','plan':None,
            'consultas':[{'recurso':'eventos_cercanos','registros':[{'estado':'no_disponible','motivo':'Tiempo agotado'}]}]})
        self.assertEqual(demand.call_count, 1)
        self.assertEqual(native.call_count, 2)
        self.assertIn('Limón', result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_unverified_event_list_is_compact_but_sources_are_preserved(self):
        result, _, _, _ = self.review()
        self.assertNotIn('Concierto lejano', result['respuesta'])
        self.assertIn('no justifica', result['respuesta'].lower())
        self.assertEqual(result['consultas'][0]['registros'][0]['fuentes'], EVENTS['consultas'][0]['registros'][0]['fuentes'])

    def test_user_percentage_continues_without_repeating_events_or_analysis(self):
        first, _, _, _ = self.review()
        proposal = {'respuesta':'Revisa propuesta','consultas':[],'plan':{'recurso':'ordenes_compra'}}
        with patch.object(flow.event_agent, 'run', side_effect=AssertionError('No new search')), \
             patch.object(flow.demand_agent, 'run', side_effect=AssertionError('Already analyzed')), \
             patch.object(flow.purchase_agent, 'run', return_value=proposal) as purchase:
            result = flow.handle({}, '10%', token=first['flujo_compra'])
        self.assertIn('10%', purchase.call_args.args[1])
        self.assertIsNotNone(result['plan'])

    def test_existing_percentage_is_preserved_and_not_asked_again(self):
        result, _, _, _ = self.review(instruction=REQUEST.replace('No confirmes ninguna compra todavía.', 'Usa 15% de incremento.'))
        self.assertEqual(flow.load(result['flujo_compra'])['margen'], '15')
        self.assertNotIn('¿Qué porcentaje', result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_old_event_only_token_can_finish_the_already_requested_review_without_web_retry(self):
        token = flow.serializer().dumps({'scope':{'usuario':1,'perfil':2,'local':4},'paso':'analisis','margen':None,
            'solicitud':REQUEST,'eventos':'No se verificó cercanía. Referencias sin cercanía verificada: detalles.'})
        result, search, demand, native = self.review(instruction='Continúa con el análisis solicitado', token=token)
        self.assertEqual(search.call_count, 0)
        self.assertEqual(demand.call_count, 1)
        self.assertEqual(native.call_count, 2)
        self.assertEqual(flow.load(result['flujo_compra'])['paso'], 'porcentaje')

    def test_analysis_permission_failure_still_shows_base_and_the_limitation(self):
        with patch.object(flow.event_agent, 'run', return_value=EVENTS), \
             patch.object(flow.demand_agent, 'run', side_effect=AssistantError('Sin permiso de análisis',403)), \
             patch.object(flow.tools, 'native', return_value=BASE):
            result = flow.handle({}, REQUEST)
        self.assertIn('Sin permiso', result['respuesta'])
        self.assertIn('Limón', result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_empty_base_explains_missing_data_not_sufficient_stock(self):
        result, _, _, _ = self.review(base={'productos':[], 'diagnostico':{'motivo':'sin_consumo',
            'mensaje':'No hay consumo registrado. Esto no demuestra que el stock sea suficiente.'}})
        self.assertIn('No hay consumo', result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_simple_request_keeps_analyses_optional(self):
        result, _, demand, native = self.review(instruction='Quiero hacer un pedido')
        self.assertEqual(demand.call_count, 0)
        self.assertEqual(native.call_count, 0)
        self.assertIn('¿Hasta qué fecha necesitas que alcance este pedido?',result['respuesta'])

    def test_excluded_analysis_is_not_run_just_because_events_were_requested(self):
        result, _, demand, native = self.review(instruction='Quiero hacer un pedido. Revisa eventos, pero no analices ventas y stock todavía.')
        self.assertEqual(demand.call_count, 0)
        self.assertEqual(native.call_count, 0)

    def test_explicit_sales_dates_on_a_followup_are_not_replaced_by_the_old_request(self):
        token = flow.serializer().dumps({'scope':{'usuario':1,'perfil':2,'local':4},'paso':'analisis','margen':None,
            'solicitud':'Quiero hacer un pedido', 'eventos':'Búsqueda completada.','dias_abastecimiento':7})
        _, _, demand, _ = self.review(instruction='Analiza ventas del 2026-10-01 al 2026-10-10 y el stock', token=token)
        self.assertEqual(demand.call_args.kwargs['filters'], {'desde':'2026-10-01','hasta':'2026-10-10'})

    def test_initial_percentage_is_kept_when_the_user_only_forbids_confirmation(self):
        result, _, _, _ = self.review(instruction=REQUEST.replace('pregúntame qué incremento aplicar', 'aplica 10% de incremento'))
        self.assertEqual(flow.load(result['flujo_compra'])['margen'], '10')
        self.assertNotIn('¿Qué porcentaje', result['respuesta'])

    def test_proximity_on_a_separate_line_is_not_misclassified_as_verified(self):
        events = {'respuesta':'Eventos', 'plan':None, 'consultas':[{'recurso':'eventos_cercanos','registros':[{
            'estado':'consultado', 'informe':'- Concierto lejano\n  Cercanía por confirmar.\n  Lugar: otro distrito.',
            'fuentes':EVENTS['consultas'][0]['registros'][0]['fuentes']}]}]}
        result, _, _, _ = self.review(events=events)
        self.assertNotIn('referencias verificadas', result['respuesta'].lower())
        self.assertNotIn('Concierto lejano', result['respuesta'])

    def test_explicit_event_retry_does_not_repeat_completed_internal_analysis(self):
        first, _, _, _ = self.review()
        _, search, demand, native = self.review(instruction='Reintentar eventos', token=first['flujo_compra'])
        self.assertEqual(search.call_count, 1)
        self.assertEqual(demand.call_count, 0)
        self.assertEqual(native.call_count, 0)

    def test_stock_is_shown_even_without_sales_or_calculated_purchase_quantities(self):
        analysis = {'respuesta':'No hay ventas cobradas registradas.', 'consultas':[], 'plan':None}
        result, _, _, _ = self.review(analysis=analysis, base={'productos':[], 'diagnostico':{
            'motivo':'sin_consumo','mensaje':'No hay consumo registrado; no demuestra stock suficiente.'}})
        self.assertIn('Maracuyá', result['respuesta'])
        self.assertIn('agotado', result['respuesta'].lower())
        self.assertIn('sin conteo', result['respuesta'].lower())
        self.assertIn('no demuestra', result['respuesta'].lower())
        self.assertIn('stock', [q['recurso'] for q in result['consultas']])

    def test_denied_stock_report_does_not_stop_the_other_authorized_reads(self):
        def authorize(agent, resource, *args):
            if agent == 'inventario' and resource == 'stock':
                raise AssistantError('Sin permiso para revisar stock', 403)
        with patch('app.multiagente.api.configuration.authorize', side_effect=authorize):
            result, _, demand, native = self.review()
        self.assertIn('Sin permiso para revisar stock', result['respuesta'])
        self.assertEqual(demand.call_count, 1)
        self.assertEqual(native.call_count, 1)
        self.assertIsNone(result['plan'])

    def test_stock_summary_preserves_native_minimum_boundary_and_unknown_count(self):
        rows = [{'id_producto':1,'nombre':'Limón','unidad':'KGM','stock_actual':1,'stock_minimo':1,'estado_stock':'STOCK_BAJO'},
                {'id_producto':2,'nombre':'Sin verificar','unidad':'LTR','stock_actual':0,'stock_minimo':1,'estado_stock':'SIN_CONTEO'}]
        with patch.dict(STOCK, {'productos':rows}):
            result, _, _, _ = self.review()
        query = next(q for q in result['consultas'] if q['recurso'] == 'stock')
        self.assertEqual(query['contexto']['resumen']['STOCK_BAJO'], 1)
        self.assertEqual(query['contexto']['resumen']['SIN_CONTEO'], 1)
        self.assertEqual(query['contexto']['resumen']['AGOTADO'], 0)

    def test_sales_can_be_excluded_while_stock_and_base_are_requested(self):
        result, _, demand, native = self.review(instruction='Quiero hacer un pedido para 7 días. Revisa el stock, pero no analices ventas todavía.')
        self.assertEqual(demand.call_count, 0)
        self.assertEqual(native.call_count, 2)
        self.assertNotIn('IPA', result['respuesta'])
        self.assertIn('stock', [q['recurso'] for q in result['consultas']])

    def test_sales_only_excludes_stock_summary_and_base_without_leaking_stock_details(self):
        result, _, demand, native = self.review(instruction='Quiero preparar el pedido para 7 días. Analiza ventas, pero no revises stock ni reposición todavía.')
        self.assertEqual(demand.call_count, 1)
        self.assertEqual(native.call_count, 0)
        self.assertIn('IPA', result['respuesta'])
        self.assertNotIn('Limón', result['respuesta'])
        self.assertNotIn('stock_actual', str(result['consultas']))

    def test_events_can_be_excluded_without_blocking_the_requested_internal_analysis(self):
        result, search, demand, native = self.review(instruction='Quiero preparar el pedido para 7 días. Sin análisis de eventos; analiza ventas y stock.')
        self.assertEqual(search.call_count, 0)
        self.assertEqual(demand.call_count, 1)
        self.assertEqual(native.call_count, 2)
        self.assertIsNone(result['plan'])
