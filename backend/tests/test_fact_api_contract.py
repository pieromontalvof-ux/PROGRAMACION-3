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

    def test_sale_sends_optional_contact_from_the_receipt_snapshot(self):
        from app.modules.facturacion.contract import venta
        base = {'id_cobro': 7, 'id_local': 2, 'tipo': 'FACTURA', 'documento': '20123456789',
                'cliente': 'Empresa', 'total': 10, 'creado_en': '2026-11-21',
                'comprobante': {'lineas': [{'nombre': 'A', 'cantidad': 1, 'precio': 10}],
                                'contacto': {'email': 'caja@example.org', 'telefono': '999777666',
                                             'direccion': 'Calle de prueba'}}}
        config = {'tasa_igv': 18, 'serie_factura': 'F002', 'empresa': {}}
        tercero = venta(base, config)['tercero']
        self.assertEqual(tercero['direccion'], 'Calle de prueba')
        self.assertEqual(tercero['email'], 'caja@example.org')
        self.assertEqual(tercero['telefono'], '999777666')
        base['comprobante'].pop('contacto')
        self.assertNotIn('email', venta(base, config)['tercero'])

    def test_boleta_sends_identification_code_and_classifies_customer(self):
        from app.modules.clientes.service import validar as validar_cliente
        from app.modules.facturacion.contract import venta
        from app.modules.salon.salon_payments import validar as validar_cobro
        from werkzeug.exceptions import BadRequest

        for clase, numero, codigo, persona in (
            ('DNI', '12345678', '1', 'NATURAL'),
            ('CE', 'ABC123456789', '4', 'NATURAL'),
            ('PASAPORTE', 'PA12345678901', '7', 'NATURAL'),
            ('RUC', '10123456789', '6', 'NATURAL'),
            ('RUC', '15123456789', '6', 'NATURAL'),
            ('RUC', '20123456789', '6', 'JURIDICA'),
        ):
            with self.subTest(documento=clase, codigo=codigo, persona=persona):
                datos = {'clave': '9dbdacad-5d96-4676-8911-933520ec52dd', 'revision': 'a' * 64,
                         'metodo': 'TARJETA', 'tipo': 'BOLETA_ELECTRONICA', 'tipo_documento': clase,
                         'documento': numero, 'cliente': 'Cliente de prueba'}
                comprobante = validar_cobro(datos)
                if clase == 'DNI':
                    self.assertNotIn('tipo_documento', comprobante)
                payload = venta({'id_cobro': 1, 'id_local': 1, 'tipo': datos['tipo'], 'documento': numero,
                    'total': 10, 'creado_en': '2026-11-21', 'comprobante': {
                        **comprobante, 'lineas': [{'nombre': 'A', 'cantidad': 1, 'precio': 10}],
                    }}, {'tasa_igv': 18, 'serie_boleta': 'B001', 'empresa': {}})
                self.assertEqual(payload['tercero']['tipo'], codigo)
                cliente = validar_cliente({'nombre': 'Prueba', 'tipo_documento': clase, 'numero_documento': numero})
                self.assertEqual(cliente['tipo_persona'], persona)
        with self.assertRaises(BadRequest):
            validar_cobro({**datos, 'tipo': 'FACTURA', 'tipo_documento': 'PASAPORTE', 'documento': 'PA12345'})

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

    def test_pdf_storage_uses_issue_date_and_document_kind(self):
        from app.modules.facturacion.worker import persist_pdf
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        from pathlib import Path

        job = {'id_local': 5, 'nombre_local': 'Santa Anita', 'origen': 'VENTA', 'id_operacion': 'operation', 'lease_token': 'lease'}
        with TemporaryDirectory() as folder, patch('app.modules.facturacion.worker.storage_root', return_value=Path(folder)):
            for fecha, origen, tipo, documento, categoria in (
                ('2026-11-30', 'VENTA', '01', '20123456789', 'facturas'),
                ('2026-12-01', 'VENTA', '03', '', 'boletas'),
                ('2027-01-01', 'VENTA', '03', '71234567', 'boletas-electronicas'),
                ('2027-01-02', 'COMPRA', '01', '20123456789', 'facturas-de-compra'),
            ):
                with self.subTest(fecha=fecha, categoria=categoria):
                    payload = {'fecha': fecha, 'tipo': tipo, 'tercero': {'documento': documento}}
                    archivo = persist_pdf({**job, 'origen': origen, 'payload': payload}, 'A4', b'%PDF-test', 'F005-123')
                    ruta = Path(archivo['path'])
                    self.assertEqual(ruta.parts[:5], (*fecha.split('-'), 'Santa Anita', categoria))
                    self.assertEqual(ruta.name, 'F005-123_A4.pdf')
                    self.assertEqual((Path(folder) / ruta).read_bytes(), b'%PDF-test')

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
