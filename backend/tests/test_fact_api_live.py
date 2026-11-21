"""Opt-in HTTP checks against the configured LOCAL demo Laravel bridge."""
import copy
import hashlib
import json
import os
import unittest
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
from app.modules.facturacion.transport import call, ApiError


@unittest.skipUnless(os.getenv('FACT_API_LIVE_TEST')=='1','API Laravel local opt-in')
class LiveBridgeTests(unittest.TestCase):
    def payload(self, origin='VENTA'):
        result={'version':1,'origen':origin,'referencia':'TEST-'+str(uuid4())[:8], 'id_local':1,
            'empresa':{'nombre':'BARBARIAN · DEMOSTRACIÓN','ruc':'00000000000'},'tipo':'03','serie':'T001',
            'fecha':'2026-11-21','moneda':'PEN','tercero':{'nombre':'Prueba integración ñ','documento':'','tipo':'1'},
            'lineas':[{'codigo':'TEST','nombre':'Artículo de prueba','cantidad':'1','unidad':'C62',
                        'subtotal':'10.00','igv':'1.80','total':'11.80','tasa_igv':'18','afectacion':'GRAVADO'}],
            'subtotal':'10.00','igv':'1.80','total':'11.80'}
        if origin=='COMPRA':result.update(numero_proveedor='TEST-1',orden_compra='TEST-OC')
        return result

    def test_concurrent_creation_and_lost_response_return_same_document(self):
        payload=self.payload();key=str(uuid4())
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda _:call('documents',payload,key),range(2)))
        self.assertEqual(results[0],results[1])
        self.assertEqual(call('documents',payload,key),results[0])
        expected=hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
        self.assertEqual(results[0]['payload_hash'],expected)
        self.assertEqual(call('documents/'+key)['estado'],'DEMO_GENERADO')
        for format in ('A4','80mm'):
            data=call('documents/'+key+'/pdf?format='+format,binary=True)
            self.assertTrue(data.startswith(b'%PDF-'))
            self.assertEqual(data,call('documents/'+key+'/pdf?format='+format,binary=True))
        changed=copy.deepcopy(payload);changed['tercero']['nombre']='Otro'
        with self.assertRaises(ApiError) as error:call('documents',changed,key)
        self.assertEqual(error.exception.status,409)

    def test_purchase_pdf_and_invalid_totals(self):
        payload=self.payload('COMPRA');key=str(uuid4())
        self.assertEqual(call('documents',payload,key)['numero'],'TEST-1')
        self.assertTrue(call('documents/'+key+'/pdf',binary=True).startswith(b'%PDF-'))
        payload['total']='1.00'
        with self.assertRaises(ApiError) as error:call('documents',payload,str(uuid4()))
        self.assertEqual(error.exception.status,422)
