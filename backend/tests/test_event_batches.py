import json
import unittest
from app.multiagente.api.provider import AssistantError


def response(rows,status='completed'):
    return {'status':status,'output':[{'type':'web_search_call','action':{'sources':[{'url':'https://official.example'}]}},
        {'type':'message','content':[{'type':'output_text','text':json.dumps({'candidatos':rows,'limitaciones':''})}]}]}


class EventBatchTests(unittest.TestCase):
    def test_map_discovery_uses_alternate_service_if_first_fails(self):
        from unittest.mock import patch,MagicMock
        from contextlib import nullcontext
        from app.multiagente.agents.eventos import nearby
        reply=MagicMock()
        reply.__enter__.return_value.read.return_value=b'{"elements":[{"id":7}]}'
        with patch.object(nearby.geography,'provider_gate',side_effect=lambda:nullcontext()), \
             patch.object(nearby,'urlopen',side_effect=[OSError('Offline'),reply]) as request:
            self.assertEqual(nearby.query_map('query'),[{'id':7}])
        self.assertEqual(request.call_count,2)
        self.assertNotEqual(request.call_args_list[0].args[0].full_url,request.call_args_list[1].args[0].full_url)

    def test_citation_annotations_survive_aggregation(self):
        from app.multiagente.agents.eventos import batches,research
        value=response([{'nombre':'Evento','fecha_desde':'2026-11-23'}])
        value['output']=value['output'][1:]
        value['output'][0]['content'][0]['annotations']=[{'type':'url_citation','url':'https://official.example/event'}]
        result=batches.run([{}],lambda payload:value)
        self.assertIn('https://official.example/event',research.unpack(result)[1])

    def test_new_discoveries_are_not_crowded_out_by_stale_cache(self):
        from app.multiagente.agents.eventos import research
        old=[{'nombre':f'Antiguo {i}','fecha_desde':'2026-11-17'} for i in range(30)]
        new=[{'nombre':'Nuevo del último día','fecha_desde':'2026-11-23'}]
        rows,omitted=research.refresh_candidates(new,old)
        self.assertIn(new[0],rows)
        self.assertEqual(omitted,1)

    def test_truncated_json_recovers_complete_candidates_only(self):
        from app.multiagente.agents.eventos import research
        raw='{"candidatos": [{"nombre":"Evento completo","fecha_desde":"2026-11-23"},{"nombre":"Cortado'
        data,_=research.unpack({'status':'incomplete','output':[{'type':'message','content':[{'type':'output_text','text':raw}]}]})
        self.assertEqual(len(data['candidatos']),1)
        self.assertEqual(data['candidatos'][0]['nombre'],'Evento completo')
        self.assertTrue(data['_partial'])

    def test_discovery_covers_three_venue_families_and_keeps_successes(self):
        from app.multiagente.agents.eventos import batches,research
        prompts=[]
        def search(payload):
            prompts.append(payload['input'])
            if 'GRUPO HOTELES' in payload['input']:
                raise AssistantError('Tiempo agotado')
            return response([{'nombre':'Teatro' if 'GRUPO CULTURA' in payload['input'] else 'Parque','fecha_desde':'2026-11-23'}])
        result=batches.discover({'input':'Sede X, del 17 al 23','max_output_tokens':7000},search,[])
        data,urls=research.unpack(result)
        self.assertEqual(len(prompts),3)
        self.assertEqual(len(data['candidatos']),2)
        self.assertEqual(result['status'],'incomplete')
        self.assertIn('https://official.example',urls)
        self.assertTrue(all('del 17 al 23' in p for p in prompts))

    def test_verification_batches_keep_all_candidates_and_partial_results(self):
        from app.multiagente.agents.eventos import batches,research
        candidates=[{'nombre':f'Evento {i}','fecha_desde':'2026-11-23'} for i in range(15)]
        def search(payload):
            chunk=json.loads(payload['input'].split('\nCandidatos: ')[-1])
            if chunk[0]['nombre']=='Evento 6':
                raise AssistantError('Tiempo agotado')
            return response(chunk)
        result=batches.verify({'input':'Verifica\nCandidatos: []'},search,candidates)
        data,_=research.unpack(result)
        merged=research.merge(candidates,data['candidatos'])
        self.assertEqual(len(merged),15)
        self.assertEqual(sum(r['verificacion_pendiente'] for r in merged),6)
        self.assertEqual(result['status'],'incomplete')
