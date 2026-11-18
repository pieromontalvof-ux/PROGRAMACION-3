import io
import json
import ssl
import socket
import unittest
from unittest.mock import patch
from urllib.error import URLError, HTTPError

from app.multiagente.api import provider


class ProviderTransportTests(unittest.TestCase):
    def test_output_limit_retries_once_and_discards_all_partial_tool_calls(self):
        partial={'status':'incomplete','incomplete_details':{'reason':'max_output_tokens'},
                 'output':[{'type':'function_call','name':'preparar_cambio','arguments':'{"broken"'}]}
        complete={'status':'completed','output':[{'type':'message','content':[]}]}
        with patch.object(provider,'call',side_effect=[partial,complete]) as call:
            self.assertEqual(provider.respond([{'role':'user','content':'Tres semanas'}],[],3500),complete['output'])
        first=json.loads(call.call_args_list[0].args[1]);second=json.loads(call.call_args_list[1].args[1])
        self.assertEqual(first['input'],second['input'])
        self.assertEqual(second['max_output_tokens'],7000)
        self.assertFalse(second['store'])
        self.assertNotIn(partial['output'][0],second['input'])

    def test_incomplete_retry_is_bounded_and_does_not_blame_user(self):
        data={'status':'incomplete','incomplete_details':{'reason':'max_output_tokens'},'output':[]}
        with patch.object(provider,'call',return_value=data) as call:
            with self.assertRaises(provider.AssistantError) as error:provider.respond([],[],7000)
        self.assertEqual(call.call_count,2)
        self.assertEqual(json.loads(call.call_args.args[1])['max_output_tokens'],12000)
        self.assertNotIn('Divide',str(error.exception))

    def test_other_incomplete_reasons_are_not_retried(self):
        for reason in ('content_filter',None):
            with patch.object(provider,'call',return_value={'status':'incomplete','incomplete_details':{'reason':reason},'output':[]}) as call:
                with self.assertRaises(provider.AssistantError):provider.respond([],[])
                self.assertEqual(call.call_count,1)

    def setUp(self):
        p = patch.dict('os.environ', {'OPENAI_API_KEY': 'test-only-secret'})
        p.start()
        self.addCleanup(p.stop)

    def test_temporary_connection_failure_recovers_without_losing_the_request(self):
        response = io.BytesIO(b'{"status":"completed","output":[]}')
        with patch.object(provider, 'urlopen', side_effect=[URLError(ConnectionResetError('temporary')), response]) as send, \
             patch('time.sleep'):
            result = provider.call('responses', b'{"input":"test"}')
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(send.call_count, 2)
        self.assertEqual(send.call_args.args[0].data, b'{"input":"test"}')

    def test_repeated_connection_failure_stops_after_three_attempts(self):
        with patch.object(provider, 'urlopen', side_effect=URLError(ConnectionRefusedError('offline'))) as send, \
             patch('time.sleep'):
            with self.assertRaises(provider.AssistantError) as caught:
                provider.call('responses', b'{}')
        self.assertEqual(send.call_count, 3)
        self.assertEqual(caught.exception.status, 502)

    def test_authentication_error_is_not_retried(self):
        with patch.object(provider, 'urlopen', side_effect=HTTPError('https://api.openai.com', 401, 'Unauthorized', {}, None)) as send, \
             patch('time.sleep'):
            with self.assertRaises(provider.AssistantError):
                provider.call('responses', b'{}')
        self.assertEqual(send.call_count, 1)

    def test_certificate_and_permanent_dns_errors_are_not_retried(self):
        for reason in (ssl.SSLCertVerificationError('invalid certificate'), socket.gaierror(socket.EAI_NONAME, 'unknown host')):
            with self.subTest(reason=type(reason).__name__), \
                 patch.object(provider, 'urlopen', side_effect=URLError(reason)) as send, \
                 patch('time.sleep'):
                with self.assertRaises(provider.AssistantError):
                    provider.call('responses', b'{}')
                self.assertEqual(send.call_count, 1)

    def test_retry_does_not_exceed_the_original_time_budget(self):
        with patch.object(provider, 'urlopen', side_effect=URLError(ConnectionResetError('offline'))) as send, \
             patch('time.monotonic', side_effect=[0, 0, 59.9]), patch('time.sleep') as sleep:
            with self.assertRaises(provider.AssistantError):
                provider.call('responses', b'{}', timeout=60)
        self.assertEqual(send.call_count, 1)
        sleep.assert_not_called()

    def test_connection_diagnostics_do_not_include_secret_or_provider_error_text(self):
        with patch.object(provider, 'urlopen', side_effect=URLError(ConnectionResetError('test-only-secret private-content'))), \
             patch('time.sleep'), self.assertLogs(provider.__name__, level='WARNING') as logs:
            with self.assertRaises(provider.AssistantError):
                provider.call('responses', b'{"input":"private-content"}')
        recorded = ' '.join(logs.output)
        self.assertIn('ConnectionResetError', recorded)
        self.assertNotIn('test-only-secret', recorded)
        self.assertNotIn('private-content', recorded)
