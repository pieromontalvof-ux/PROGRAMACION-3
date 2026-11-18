import unittest
from unittest.mock import patch
from app.modules.compras import service


class SendDraftTests(unittest.TestCase):
    def test_existing_draft_is_sent_without_creating_another_order(self):
        with patch.object(service,'obtener_orden_historial',return_value={'codigo':'OC-003','estado_orden_compra':'BORRADOR'}), \
             patch.object(service,'obtener_detalle_orden_historial',return_value=[{'id_producto':1,'cantidad_solicitada':3}]), \
             patch.object(service,'obtener_total_recibido_orden',return_value=0), \
             patch.object(service,'producto_activo_existe',return_value=True), \
             patch.object(service,'enviar_orden_borrador') as send, \
             patch.object(service,'guardar_historial_estado_orden'),patch.object(service,'registrar_actividad'), \
             patch.object(service.db.session,'commit'),patch.object(service,'crear_cabecera_orden') as create:
            result,status=service.enviar_borrador(146,1)
        self.assertEqual(status,200)
        self.assertEqual(result['orden']['estado_orden_compra'],'ENVIADA')
        send.assert_called_once_with(146,1)
        create.assert_not_called()

    def test_received_order_cannot_be_sent_again(self):
        with patch.object(service,'obtener_orden_historial',return_value={'codigo':'OC-003','estado_orden_compra':'RECEPCIONADA'}), \
             patch.object(service.db.session,'rollback'),patch.object(service,'enviar_orden_borrador') as send:
            _,status=service.enviar_borrador(146,1)
        self.assertEqual(status,409)
        send.assert_not_called()
