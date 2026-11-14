import copy
import json
import tempfile
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from flask import Flask

from app.agents.eventos import research
from app.agents.eventos import agent
from app.modules.asistente_ia.provider import AssistantError

LOCAL = {'id_local':4,'nombre':'Sheraton','direccion':'Paseo de la República 170'}
PERIOD = ['2026-11-11','2026-11-18']
URL = 'https://organizador.example/evento'


def candidate(**changes):
    return dict(nombre='Congreso', fecha_desde='2026-11-12', fecha_hasta='2026-11-14', hora='09:00',
                recinto='Hotel cercano', direccion='Paseo de la República 170', tipo='Congreso', publico='Profesionales',
                url=URL, fuente_fecha=URL, fuente_ubicacion=URL, cercania='ACREDITADA',
                sustento_cercania='El recinto publica la misma dirección de referencia.',
                acceso='INSCRIPCION', estado='ACTIVO', relevancia='POTENCIAL', motivo='', **changes)


class EventResearchTests(unittest.TestCase):
    def setUp(self):
        patcher=patch('app.agents.eventos.geography.check',side_effect=lambda location,rows:self.geo(rows))
        patcher.start()
        self.addCleanup(patcher.stop)

    def geo(self,rows):
        return {'origin':{'lat':-12,'lon':-77},'radius_m':1500,'venues':{research.identity(r):{'estado':'DENTRO','distancia_m':500,'url':'https://www.openstreetmap.org/node/1'} for r in rows}}
    def response(self, rows):
        return {'status':'completed','output':[
            {'type':'web_search_call','action':{'sources':[{'url':URL}]}},
            {'type':'message','content':[{'type':'output_text','text':json.dumps({'candidatos':rows,'limitaciones':''})}]}]}

    def test_two_phases_and_repeated_question_reuses_report_but_retry_checks_previous_candidates(self):
        with tempfile.TemporaryDirectory() as folder:
            app=Flask(__name__,instance_path=folder)
            with app.app_context(), patch.object(agent,'datetime') as clock:
                clock.now.return_value=datetime(2026,11,11,14,tzinfo=timezone.utc)
                instruction='Eventos del 2026-11-11 al 2026-11-18. Quiero preparar el pedido.'
                with patch.object(agent,'search_response',side_effect=[self.response([candidate()]),self.response([candidate()])]) as search:
                    first=agent.events(instruction,local=LOCAL)
                self.assertEqual(search.call_count,2)
                self.assertIn('Congreso',search.call_args_list[1].args[0]['input'])
                self.assertEqual(first['candidatos'][0]['decision'],'INCLUIDO')
                with patch.object(agent,'search_response',side_effect=AssertionError('No new paid search')):
                    second=agent.events(instruction,local=LOCAL)
                self.assertTrue(second['cache_reutilizada'])
                self.assertEqual(first['informe'],second['informe'])
                with patch.object(agent,'search_response',side_effect=AssistantError('Offline')):
                    failed=agent.events('Reintentar eventos. '+instruction,local=LOCAL)
                self.assertEqual(failed['estado'],'parcial')
                self.assertEqual(failed['candidatos'][0]['decision'],'PENDIENTE')
                with patch.object(agent,'search_response',side_effect=[self.response([]),self.response([])]) as search:
                    updated=agent.events('Reintentar eventos. '+instruction,local=LOCAL)
                self.assertEqual(search.call_count,2)
                self.assertIn('Candidatos previos',search.call_args_list[0].args[0]['input'])
                self.assertEqual(updated['candidatos'][0]['decision'],'PENDIENTE')
                self.assertIn('no fue resuelto',updated['candidatos'][0]['motivo'])
                with patch.object(research.time,'time',return_value=research.time.time()+1801), patch.object(agent,'search_response',side_effect=[self.response([]),self.response([])]):
                    expired=agent.events(instruction,local=LOCAL)
                self.assertEqual(expired['candidatos'][0]['decision'],'PENDIENTE')

    def test_failed_verification_preserves_candidates_as_pending_and_does_not_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            app=Flask(__name__,instance_path=folder)
            with app.app_context(), patch.object(agent,'datetime') as clock, patch.object(agent,'search_response',side_effect=[self.response([candidate()]),AssistantError('Offline')]):
                clock.now.return_value=datetime(2026,11,11,14,tzinfo=timezone.utc)
                instruction='Eventos del 2026-11-11 al 2026-11-18'
                report=agent.events(instruction,local=LOCAL)
                self.assertIsNone(research.cached(research.cache_key({k:LOCAL.get(k) for k in ('id_local','codigo','nombre','direccion')},PERIOD,instruction)))
        self.assertEqual(report['estado'],'parcial')
        self.assertEqual(report['candidatos'][0]['decision'],'PENDIENTE')

    def test_classifies_and_preserves_reasons_without_filling_nearby_table(self):
        good = candidate()
        outside = {**good,'nombre':'Fuera de rango','fecha_desde':'2026-11-20','fecha_hasta':'2026-11-21'}
        private = {**good,'nombre':'Sesión legislativa','acceso':'RESTRINGIDO'}
        unproven = {**good,'nombre':'Concierto','fuente_ubicacion':'https://inventado.example','cercania':'ACREDITADA'}
        cancelled = {**good,'nombre':'Cancelado','estado':'CANCELADO'}
        candidates=[outside,good,private,unproven,cancelled,copy.deepcopy(good)]
        rows = research.classify(candidates, PERIOD, {URL},self.geo(candidates))
        self.assertEqual(len(rows), 5)
        statuses = {r['nombre']:r['decision'] for r in rows}
        self.assertEqual(statuses['Congreso'], 'INCLUIDO')
        self.assertEqual(statuses['Fuera de rango'], 'DESCARTADO')
        self.assertEqual(statuses['Sesión legislativa'], 'DESCARTADO')
        self.assertEqual(statuses['Concierto'], 'PENDIENTE')
        self.assertEqual(statuses['Cancelado'], 'DESCARTADO')
        self.assertTrue(all(r['motivo'] for r in rows))
        report = research.render(rows)
        self.assertIn('| Día | Evento publicado | Tipo | Lugar |',report)
        self.assertNotIn('Fuera de rango', report)
        detail=research.render_details(rows)
        self.assertIn('Fuera de rango',detail)
        self.assertIn('https://organizador.example', report)

    def test_missing_dates_and_unsearched_sources_cannot_be_included(self):
        rows = research.classify([{**candidate(),'fecha_desde':'no sé'},
                                  {**candidate(),'nombre':'Sin fuente','fuente_fecha':'https://inventado.example'}], PERIOD, {URL})
        self.assertTrue(all(r['decision']!='INCLUIDO' for r in rows))

    def test_model_claims_and_coordinates_cannot_override_missing_or_far_map_result(self):
        row={**candidate(),'lat':-12,'lon':-77,'distancia_m':0}
        self.assertEqual(research.classify([row],PERIOD,{URL})[0]['decision'],'PENDIENTE')
        far=self.geo([row])
        far['venues'][research.identity(row)].update(estado='FUERA',distancia_m=6000)
        result=research.classify([row],PERIOD,{URL},far)[0]
        self.assertEqual(result['decision'],'DESCARTADO')
        self.assertEqual(result['distancia_m'],6000)
        self.assertIn('Fuera del radio',result['motivo'])

    def test_cache_is_scoped_and_atomic_and_failure_does_not_replace_good_result(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Flask(__name__,instance_path=folder)
            with app.app_context():
                key = research.cache_key(LOCAL, PERIOD, 'todos')
                report = {'estado':'consultado','candidatos':[candidate()],'informe':'Tabla'}
                research.save(key, report)
                self.assertEqual(research.cached(key)['informe'], 'Tabla')
                self.assertIsNone(research.cached(research.cache_key({**LOCAL,'id_local':3},PERIOD,'todos')))
                self.assertIsNone(research.cached(research.cache_key(LOCAL,['2026-11-11','2026-11-20'],'todos')))
                research.save(key, {'estado':'no_disponible','informe':'Falló'})
                self.assertEqual(research.cached(key)['informe'], 'Tabla')
                with patch.object(research.time,'time',return_value=research.time.time()+1801):
                    self.assertIsNone(research.cached(key))

    def test_verification_cannot_silently_erase_discovered_candidates(self):
        merged = research.merge([candidate()], [])
        self.assertEqual(len(merged),1)
        self.assertEqual(merged[0]['cercania'],'PENDIENTE')
        self.assertIn('verificación', merged[0]['motivo'])

    def test_phase_opinions_do_not_override_classified_results_in_display(self):
        first=self.response([candidate()])
        first['output'][1]['content'][0]['text']=json.dumps({'candidatos':[candidate()],'limitaciones':'No hay congresos en este hotel. Comparte tus ventas.'})
        with patch.object(agent,'datetime') as clock, patch.object(agent,'search_response',side_effect=[first,self.response([candidate()])]):
            clock.now.return_value=datetime(2026,11,11,14,tzinfo=timezone.utc)
            report=agent.events('Eventos del 2026-11-11 al 2026-11-18',local=LOCAL)
        self.assertEqual(report['candidatos'][0]['decision'],'INCLUIDO')
        self.assertNotIn('No hay congresos',report['informe'])
        self.assertNotIn('Comparte tus ventas',report['informe'])
