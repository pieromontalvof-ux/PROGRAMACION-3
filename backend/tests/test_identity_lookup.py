import io
import json
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from werkzeug.exceptions import BadRequest, ServiceUnavailable, TooManyRequests

from app.modules.clientes.identity import consultar


class IdentityLookupTests(unittest.TestCase):
    def test_missing_token_does_not_contact_provider(self):
        with patch.dict('os.environ', {'FACTILIZA_TOKEN': ''}), patch('app.modules.clientes.identity.urlopen') as remote:
            with self.assertRaises(ServiceUnavailable): consultar('DNI', '00000000')
            remote.assert_not_called()

    def test_invalid_document_is_rejected_before_network(self):
        for kind, number in [('DNI', '123'), ('RUC', '../123'), ('OTHER', '00000000')]:
            with self.assertRaises(BadRequest): consultar(kind, number)

    def test_returns_only_needed_fields_and_preserves_document(self):
        payload={'success': True, 'data': {'numero':'00000000','nombre_completo':'CLIENTE PRUEBA','direccion':'PRIVATE','fecha_nacimiento':'PRIVATE'}}
        with patch.dict('os.environ', {'FACTILIZA_TOKEN':'test'}), patch('app.modules.clientes.identity.urlopen', return_value=io.BytesIO(json.dumps(payload).encode())) as remote:
            result=consultar('DNI','00000000')
        self.assertEqual(result['nombre'],'CLIENTE PRUEBA')
        self.assertNotIn('direccion',result)
        self.assertEqual(remote.call_args.args[0].full_url,'https://api.factiliza.com/v1/dni/info/00000000')

    def test_quota_exceeded_has_no_automatic_retry(self):
        with patch.dict('os.environ', {'FACTILIZA_TOKEN':'test'}), patch('app.modules.clientes.identity.urlopen', side_effect=HTTPError('url',429,'quota',{},None)) as remote:
            with self.assertRaises(TooManyRequests): consultar('RUC','20000000001')
            self.assertEqual(remote.call_count,1)

    def test_mismatched_identity_is_never_returned(self):
        payload={'success':True,'data':{'numero':'11111111','nombre_completo':'Other'}}
        with patch.dict('os.environ', {'FACTILIZA_TOKEN':'test'}), patch('app.modules.clientes.identity.urlopen', return_value=io.BytesIO(json.dumps(payload).encode())):
            with self.assertRaises(ServiceUnavailable): consultar('DNI','00000000')
