import unittest
from decimal import Decimal


class FactApiContractTests(unittest.TestCase):
    def test_sale_date_uses_lima_even_when_postgres_returns_utc(self):
        from app.modules.facturacion.contract import venta
        data=venta({'id_cobro':1,'id_local':1,'tipo':'BOLETA','total':10,
            'creado_en':'2026-11-22T02:30:00+00:00','comprobante':{'lineas':[{'nombre':'A','cantidad':1,'precio':10}]}},
            {'tasa_igv':18,'serie_boleta':'B001','empresa':{}})
        self.assertEqual(data['fecha'],'2026-11-21')

    def test_sales_prices_include_tax_and_totals_reconcile(self):
        from app.modules.facturacion.contract import venta
        data = venta({'id_cobro': 7, 'id_local': 2, 'tipo': 'FACTURA', 'documento': '20123456789',
                      'cliente': 'Empresa', 'total': Decimal('125.00'), 'creado_en': '2026-11-21',
                      'comprobante': {'lineas': [{'nombre': 'Producto', 'cantidad': 1, 'precio': 125}]}},
                     {'tasa_igv': 18, 'serie_factura': 'F002', 'serie_boleta': 'B002', 'empresa': {'nombre': 'Prueba'}})
        self.assertEqual(data['total'], '125.00')
        self.assertEqual(data['subtotal'], '105.93')
        self.assertEqual(data['igv'], '19.07')
        self.assertEqual(data['serie'], 'F002')

    def test_mismatched_totals_are_not_silently_recomputed(self):
        from app.modules.facturacion.contract import venta
        with self.assertRaises(ValueError):
            venta({'id_cobro': 1, 'id_local': 1, 'tipo': 'BOLETA', 'total': 10,
                   'creado_en': '2026-11-21', 'comprobante': {'lineas': [{'nombre': 'A', 'cantidad': 1, 'precio': 9}]}},
                  {'tasa_igv': 18, 'serie_boleta': 'B001', 'empresa': {}})

    def test_retry_is_bounded_and_rejection_is_terminal(self):
        from app.modules.facturacion.policy import next_retry, outcome
        self.assertEqual(next_retry(1, 0), 5)
        self.assertLessEqual(next_retry(6, 1), 330)
        self.assertEqual(outcome(422), 'RECHAZADO')
        self.assertEqual(outcome(429), 'REINTENTO')
        self.assertEqual(outcome(503), 'REINTENTO')
        self.assertEqual(outcome(401), 'BLOQUEADO')

    def test_transport_rejects_untrusted_origin(self):
        from app.modules.facturacion.transport import validate_url
        for url in ('http://example.com', 'https://user:password@example.com', 'file:///tmp/a', 'http://127.0.0.1:8091/path'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate_url(url)
        self.assertEqual(validate_url('http://127.0.0.1:8091'), 'http://127.0.0.1:8091')

    def test_late_worker_cannot_overwrite_another_leases_pdf(self):
        from app.modules.facturacion.worker import persist_pdf
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        from pathlib import Path
        with TemporaryDirectory() as folder, patch('app.modules.facturacion.worker.storage_root',return_value=Path(folder)):
            job={'id_local':1,'origen':'VENTA','id_operacion':'operation','lease_token':'first'}
            first=persist_pdf(job,'A4',b'%PDF-first')
            second=persist_pdf({**job,'lease_token':'second'},'A4',b'%PDF-second')
            self.assertNotEqual(first['path'],second['path'])
            self.assertEqual((Path(folder)/first['path']).read_bytes(),b'%PDF-first')


if __name__ == '__main__':
    unittest.main()
