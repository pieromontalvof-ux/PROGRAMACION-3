import unittest
from unittest.mock import patch
from datetime import date
from decimal import Decimal
from werkzeug.exceptions import BadRequest, NotFound
from app.modules.recepciones.invoices import calcular_factura, validar_comercial


class PurchaseInvoiceTests(unittest.TestCase):
    def datos(self):
        return {'fecha_emision': '2026-11-18', 'moneda': 'PEN', 'lineas': [
            {'id_producto': 1, 'cantidad_facturada': 20, 'precio_unitario': '10.125',
             'descuento': '2.50', 'igv_porcentaje': 18}]}

    def test_cost_total_includes_tax_and_derives_unit_price(self):
        datos=self.datos();datos['lineas']=[dict(id_producto=1,cantidad_facturada=3,costo_total=118,afectacion_igv='GRAVADO')]
        f=calcular_factura(datos)
        self.assertEqual((f['subtotal'],f['igv'],f['total']),(100,18,118))
        self.assertAlmostEqual(f['lineas'][0]['precio_unitario'],33.333333,places=6)
        datos['lineas'][0]['afectacion_igv']='EXONERADO'
        f=calcular_factura(datos)
        self.assertEqual((f['subtotal'],f['igv'],f['total']),(118,0,118))

    def test_decimal_totals_discount_and_tax(self):
        factura = calcular_factura(self.datos())
        self.assertEqual((factura['subtotal'], factura['igv'], factura['total']), (200, 36, 236))
        self.assertEqual(factura['lineas'][0]['cantidad_facturada'], 20)

    def test_mixed_tax_treatments_are_separate(self):
        datos = self.datos()
        datos['lineas'] += [dict(datos['lineas'][0], id_producto=2, afectacion_igv='EXONERADO', igv_porcentaje=0),
                            dict(datos['lineas'][0], id_producto=3, afectacion_igv='INAFECTO', igv_porcentaje=0)]
        factura = calcular_factura(datos)
        self.assertEqual((factura['base_gravada'], factura['base_exonerada'], factura['base_inafecta']), (200, 200, 200))
        self.assertEqual((factura['igv'], factura['total']), (36, 636))
        self.assertEqual(factura['lineas'][1]['afectacion_igv'], 'EXONERADO')

    def test_tax_treatment_must_agree_with_rate(self):
        for tipo, tasa in [('EXONERADO', 18), ('INAFECTO', 10), ('GRAVADO', 0), ('OTRO', 0)]:
            datos = self.datos()
            datos['lineas'][0].update(afectacion_igv=tipo, igv_porcentaje=tasa)
            with self.assertRaises(ValueError): calcular_factura(datos)

    def test_legacy_zero_tax_remains_unclassified(self):
        datos = self.datos(); datos['lineas'][0]['igv_porcentaje'] = 0
        factura = calcular_factura(datos)
        self.assertEqual(factura['lineas'][0]['afectacion_igv'], 'SIN_CLASIFICAR')

    def test_invalid_amounts_duplicates_and_dates(self):
        for campo, valor in [('precio_unitario', 'NaN'), ('precio_unitario', -1),
                              ('cantidad_facturada', 0), ('descuento', 999),
                              ('igv_porcentaje', 101)]:
            datos = self.datos(); datos['lineas'][0][campo] = valor
            with self.assertRaises(ValueError): calcular_factura(datos)
        datos = self.datos(); datos['lineas'] *= 2
        with self.assertRaises(ValueError): calcular_factura(datos)
        datos = self.datos(); datos['fecha_emision'] = 'ayer'
        with self.assertRaises(ValueError): calcular_factura(datos)

    def test_supplier_optional_fields_and_validation(self):
        self.assertEqual(validar_comercial({'ruc': '20123456789', 'razon_social': ' Empresa '})['razon_social'], 'Empresa')
        for datos in ({'ruc': '123'}, {'email': 'incorrecto'}, {'telefono': '1'*41}):
            with self.assertRaises(ValueError): validar_comercial(datos)

    def test_delivery_updates_only_received_and_rejects_overdelivery(self):
        from app.modules.recepciones import invoice_delivery as delivery, invoice_storage as storage
        from app.modules.recepciones import repository, service
        with patch.object(repository, 'obtener_factura_recepcion', return_value={'id_orden_compra': 1, 'id_proveedor': 2, 'estado_orden_compra': 'RECEPCION_PARCIAL', 'fecha_recepcion': date(2026,11,18)}), \
             patch.object(storage, 'obtener', return_value=({'fecha_emision': '2026-11-18', 'lineas': [{'id_producto':1,'cantidad_facturada':20}]}, [])), \
             patch.object(repository, 'listar_detalles_factura', return_value=[{'id_producto':1,'id_factura_recepcion_detalle':9,'cantidad_recibida':Decimal(15)}]), \
             patch.object(repository, 'obtener_producto_pendiente', return_value={'cantidad_solicitada':Decimal(20),'cantidad_recibida':Decimal(15)}), \
             patch.object(repository, 'actualizar_cantidad_recepcion') as actualizar, patch.object(storage, 'anotar_entrega'), \
             patch.object(service, 'recalcular_estado_orden', return_value='RECEPCIONADA'), \
             patch('app.modules.auditoria.service.registrar_actividad'), patch.object(delivery, 'db') as db:
            with self.assertRaises(BadRequest):
                delivery.entregar(3, 1, {'fecha':'2026-11-19', 'detalles':[{'id_producto':1,'cantidad_recibida':6}]})
            actualizar.assert_not_called()
            resultado, estado = delivery.entregar(3, 1, {'fecha':'2026-11-19', 'detalles':[{'id_producto':1,'cantidad_recibida':5}]})
            self.assertEqual(estado, 201)
            actualizar.assert_called_once_with(9, Decimal(20))
            db.session.commit.assert_called_once()

    def test_delivery_respects_local_scope(self):
        from app.modules.recepciones import invoice_delivery as delivery, invoice_storage as storage, repository
        with patch.object(repository, 'obtener_factura_recepcion', side_effect=NotFound()), patch.object(delivery, 'db') as db:
            with self.assertRaises(NotFound): delivery.entregar(3, 1, {'fecha':'2026-11-19'})
            db.session.rollback.assert_called_once()

    def test_delivery_rules_accept_a_pending_quantity_lookup_without_database(self):
        from app.modules.recepciones.invoice_delivery_rules import validar_detalles_entrega

        detalles = [{'id_producto': 1, 'cantidad_recibida': '2'}]
        factura = [{'id_producto': 1, 'cantidad_facturada': 4}]
        with self.assertRaises(BadRequest):
            validar_detalles_entrega(detalles, factura, [], lambda _: Decimal(1))
        self.assertEqual(
            validar_detalles_entrega(detalles, factura, [], {1: Decimal(2)}.get),
            [(1, Decimal(2), Decimal(2), None)],
        )

    def test_retry_of_same_delivery_does_not_add_inventory_twice(self):
        import hashlib, json
        from app.modules.recepciones import invoice_delivery as delivery, invoice_storage as storage, repository
        datos = {'clave': '24c5c195-9462-4185-a15b-37dc58767fe9', 'fecha': '2026-11-19',
                 'detalles': [{'id_producto':1, 'cantidad_recibida':5}]}
        firma = hashlib.sha256(json.dumps(datos, sort_keys=True, ensure_ascii=True).encode()).hexdigest()
        with patch.object(repository, 'obtener_factura_recepcion', return_value={'estado_orden_compra':'RECEPCIONADA'}), \
             patch.object(storage, 'obtener', return_value=({'lineas':[]}, [{'clave':datos['clave'],'solicitud':firma}])), \
             patch.object(repository, 'actualizar_cantidad_recepcion') as actualizar, patch.object(delivery, 'db'):
            self.assertEqual(delivery.entregar(3, 1, datos)[1], 200)
            actualizar.assert_not_called()


if __name__ == '__main__': unittest.main()
