from datetime import datetime, timedelta, timezone
from hashlib import sha256
import unittest
from unittest.mock import patch

from flask_jwt_extended import create_access_token
from sqlalchemy import create_engine, select

from app import create_app
from app.modules.integraciones.external import FalloTemporal
from app.core.extensions import db
from app.modules.integraciones.routes import ClaveIntegracion, ConsultaIntegracion, Solicitud, procesar_consulta


class InboxTest(unittest.TestCase):
    def test_named_keys_coexist_and_revoking_one_preserves_the_other(self):
        app = create_app()
        app.config.update(TESTING=True, JWT_SECRET_KEY='jwt-local-para-probar-integraciones',
                          INTEGRACIONES_API_TOKEN='')
        engine = create_engine('sqlite://').execution_options(schema_translate_map={'public': None})
        ClaveIntegracion.__table__.create(engine)
        Solicitud.__table__.create(engine)
        ConsultaIntegracion.__table__.create(engine)
        with app.app_context(), patch.object(db.session(), 'get_bind', return_value=engine), patch(
            'app.modules.integraciones.routes.exigir_admin', return_value=1,
        ), patch('app.modules.integraciones.routes.local_actual', return_value=5):
            cliente = app.test_client()
            token = create_access_token(identity='1')
            admin = {'Authorization': 'Bearer ' + token}
            base = '/api/v1/integraciones'
            ruta = base + '/mi-api/clave'
            conector_a = cliente.post(ruta, headers=admin, json={'nombre': 'AcadeSys', 'permiso': 'clientes', 'vigencia_dias': 30})
            conector_b = cliente.post(ruta, headers=admin, json={'nombre': 'Otro sistema'})
            self.assertEqual(conector_a.status_code, 201)
            self.assertEqual(conector_b.status_code, 201)
            a, b = conector_a.json, conector_b.json
            def enviar(conector):
                return cliente.post(base + '/entrada', json={'tipo': 'clientes', 'datos': {'nombre': 'Prueba'}},
                    headers={'Authorization': 'Bearer ' + conector['clave'], 'Idempotency-Key': 'envio-01'})
            self.assertEqual(a['permiso'], 'clientes')
            self.assertIsNotNone(a['vence_en'])
            denegado = cliente.post(base + '/entrada', json={'tipo': 'proveedores', 'datos': {}},
                headers={'Authorization': 'Bearer ' + a['clave'], 'Idempotency-Key': 'proveedor-01'})
            self.assertEqual(denegado.status_code, 403)
            self.assertEqual(enviar(a).status_code, 202)
            self.assertEqual(enviar(b).status_code, 202)
            listado = cliente.get(ruta, headers=admin)
            self.assertEqual(len(listado.json['claves']), 2)
            self.assertTrue(all('clave' not in replica for replica in listado.json['claves']))
            huellas = set(db.session.scalars(select(ClaveIntegracion.huella)))
            self.assertEqual(huellas, {sha256(conector['clave'].encode()).hexdigest() for conector in (a, b)})
            self.assertEqual(cliente.delete(ruta + '/' + a['id'], headers=admin).status_code, 200)
            self.assertEqual(enviar(a).status_code, 401)
            self.assertEqual(enviar(b).status_code, 202)
            db.session.get(ClaveIntegracion, b['id']).vence_en = datetime.now(timezone.utc) - timedelta(days=1)
            db.session.commit()
            self.assertEqual(enviar(b).status_code, 401)
            self.assertEqual(len(cliente.get(base+'/bandeja', headers=admin).json['solicitudes']), 2)
        engine.dispose()

    def test_reception_waits_and_duplicate_submissions_reuse_tracking(self):
        app = create_app()
        app.config.update(TESTING=True, INTEGRACIONES_API_TOKEN='token-local-de-prueba-solo-para-tests',
                          INTEGRACIONES_API_LOCAL=5, INTEGRACIONES_API_ORIGEN='Prueba')
        db_engine = create_engine('sqlite://').execution_options(schema_translate_map={'public': None})
        Solicitud.__table__.create(db_engine)
        ConsultaIntegracion.__table__.create(db_engine)
        with app.app_context(), patch.object(db.session(), 'get_bind', return_value=db_engine):
            client = app.test_client()
            url = '/api/v1/integraciones/entrada/clientes'
            headers = {'Authorization': 'Bearer ' + app.config['INTEGRACIONES_API_TOKEN'],
                       'Idempotency-Key': 'origen-123'}
            datos = {'nombre': 'Cliente de prueba'}
            with patch('app.modules.integraciones.routes.clientes.crear') as alta:
                self.assertEqual(client.post(url, json=datos).status_code, 401)
                respuesta = client.post(url, json=datos, headers=headers)
                self.assertEqual(respuesta.status_code, 202)
                self.assertEqual(respuesta.json['estado'], 'PENDIENTE')
                self.assertEqual(client.post('/api/v1/integraciones/entrada', headers=headers,
                                             json={'tipo': 'clientes', 'datos': datos}).json, respuesta.json)
                self.assertEqual(client.post(url, json={'nombre': 'Otro'}, headers=headers).status_code, 409)
                alta.assert_not_called()
                app.config['JWT_SECRET_KEY'] = 'jwt-local-para-probar-integraciones'
                token = create_access_token(identity='1', additional_claims={'id_perfil': 1, 'tipo_token': 'operativo'})
                admin = {'Authorization': 'Bearer ' + token}
                with patch('app.modules.integraciones.routes.exigir_admin', return_value=1):
                    identificador = respuesta.json['id']
                    alta.return_value = {'id_cliente': 'id-creado'}
                    pendiente = client.get('/api/v1/integraciones/bandeja', headers=admin)
                    self.assertEqual(pendiente.json['solicitudes'][0]['estado'], 'PENDIENTE')
                    ruta = f'/api/v1/integraciones/bandeja/{identificador}'
                    aprobada = client.post(ruta, headers=admin, json={'accion': 'agregar'})
                    self.assertEqual(aprobada.json['estado'], 'AGREGADO')
                    self.assertEqual(client.post(ruta, headers=admin, json={'accion': 'agregar'}).status_code, 409)
                    alta.assert_called_once_with(5, datos, commit=False)
                    headers['Idempotency-Key'] = 'origen-124'
                    pendiente = client.post(url, json=datos, headers=headers).json
                    descartada = client.post(f"/api/v1/integraciones/bandeja/{pendiente['id']}",
                                              headers=admin, json={'accion': 'descartar'})
                    self.assertEqual(descartada.json['estado'], 'DESCARTADO')
                    self.assertEqual(alta.call_count, 1)
                app.config['ACADESYS_API_TOKEN'] = 'clave-fixture'
                ruta = '/api/v1/integraciones/consultar'
                historial_url = '/api/v1/integraciones/historial/consultas'

                def pedir(entrada):
                    respuesta = client.post(ruta, headers=admin, json=entrada)
                    self.assertEqual(respuesta.status_code, 202)
                    return respuesta.json['id']

                def consultar_trabajo(identidad):
                    historial = client.get(historial_url, headers=admin).json
                    return next(fila for fila in historial['consultas'] if fila['id'] == identidad)

                resultado = ('catalogo.example', '/directorio',
                             {'clientes': [{'nombre': 'Cliente externo'}],
                              'proveedores': [{'nombre': 'Proveedor'}, {}]})
                with patch('app.modules.integraciones.routes.exigir_admin', return_value=1), patch(
                    'app.modules.integraciones.routes.local_actual', return_value=5,
                ), patch('app.modules.integraciones.routes.external.consultar',
                         side_effect=[FalloTemporal('API ocupada'), resultado, resultado]) as consultar:
                    consulta = {'url': 'https://catalogo.example/directorio'}
                    identidad = pedir(consulta)
                    consultar.assert_not_called()
                    self.assertEqual(consultar_trabajo(identidad)['estado'], 'EN_COLA')
                    self.assertTrue(procesar_consulta())
                    self.assertEqual(consultar_trabajo(identidad)['estado'], 'REINTENTO')
                    self.assertFalse(procesar_consulta())
                    trabajo = db.session.get(ConsultaIntegracion, identidad)
                    trabajo.ejecutar_en = datetime.now(timezone.utc) - timedelta(seconds=1)
                    db.session.commit()
                    self.assertTrue(procesar_consulta())
                    respuesta = consultar_trabajo(identidad)
                    self.assertEqual(respuesta['intentos'], 2)
                    self.assertEqual(respuesta['registros'], {'PENDIENTE': 2})
                    self.assertEqual(respuesta['resumen']['clientes']['nuevos'], 1)
                    self.assertEqual(respuesta['resumen']['proveedores']['invalidos'], 1)
                    self.assertEqual(consultar.call_args.args, (consulta['url'], ''))
                    repetida = pedir(consulta)
                    self.assertTrue(procesar_consulta())
                    self.assertEqual(consultar_trabajo(repetida)['resumen']['clientes']['repetidos'], 1)
                    pendiente = db.session.scalar(select(Solicitud).filter_by(consulta_id=identidad, tipo='clientes'))
                    with patch('app.modules.integraciones.routes.clientes.crear',
                               return_value={'id_cliente': 'cliente-prueba'}):
                        revision = client.post(f"/api/v1/integraciones/bandeja/{pendiente.id}",
                                               headers=admin, json={'accion': 'agregar'})
                    self.assertEqual(revision.json['estado'], 'AGREGADO')
                    self.assertEqual(consultar_trabajo(identidad)['registros'], {'AGREGADO': 1, 'PENDIENTE': 1})
                app.config['SECRET_KEY'] = 'secreto-ficticio-para-la-cola-de-integraciones'
                with patch('app.modules.integraciones.routes.exigir_admin', return_value=1), patch(
                    'app.modules.integraciones.routes.local_actual', return_value=5,
                ), patch('app.modules.integraciones.routes.external.consultar', return_value=resultado) as privada:
                    clave = 'clave-externa-de-prueba'
                    url_privada = 'https://catalogo.example/directorio'
                    identidad = pedir({'url': url_privada, 'clave': clave})
                    trabajo = db.session.get(ConsultaIntegracion, identidad)
                    self.assertTrue(trabajo.clave_cifrada)
                    self.assertNotIn(clave, trabajo.clave_cifrada)
                    self.assertNotIn('clave_cifrada', consultar_trabajo(identidad))
                    self.assertTrue(procesar_consulta())
                    privada.assert_called_once_with(url_privada, clave)
                    self.assertIsNone(db.session.get(ConsultaIntegracion, identidad).clave_cifrada)
                alumno = {'idCliente': 'ACAD-01', 'version': 'a' * 64, 'nombres': 'Ana',
                          'apellidoPaterno': 'Prueba', 'tipoDocumento': 'DNI',
                          'numeroDocumento': '12345678', 'correo': 'ana@example.org', 'celular': '999999999'}
                with patch('app.modules.integraciones.routes.exigir_admin', return_value=1), patch(
                    'app.modules.integraciones.routes.local_actual', return_value=5,
                ), patch('app.modules.integraciones.routes.external.consultar', return_value=(
                    'acadesys-api.onrender.com', '/api/integracion/v1/clientes/pendientes',
                    {'datos': [alumno, {'nombres': 'Invalido'}],
                     'paginacion': {'hayMas': True, 'siguienteCursor': 'cursor+1'}},
                )) as consultar:
                    url = 'https://acadesys-api.onrender.com/api/integracion/v1/clientes/pendientes?limite=100'
                    entrada = {'url': url}
                    with patch.dict(app.config, ACADESYS_API_TOKEN=''):
                        sin_clave = pedir(entrada)
                        self.assertTrue(procesar_consulta())
                        self.assertEqual(consultar_trabajo(sin_clave)['codigo'], 503)
                        consultar.assert_not_called()
                    identidad = pedir(entrada)
                    self.assertTrue(procesar_consulta())
                    respuesta = consultar_trabajo(identidad)
                    self.assertEqual(respuesta['codigo'], 200)
                    self.assertTrue(respuesta['tiene_siguiente'])
                    self.assertEqual(respuesta['resumen']['clientes']['nuevos'], 1)
                    self.assertEqual(respuesta['resumen']['clientes']['invalidos'], 1)
                    consultar.assert_called_once_with(url, 'clave-fixture')
                    segunda = pedir({'anterior': identidad})
                    self.assertTrue(procesar_consulta())
                    self.assertIn('cursor=cursor%2B1', consultar.call_args.args[0])
                    self.assertEqual(consultar_trabajo(segunda)['resumen']['clientes']['repetidos'], 1)
                    solicitudes = client.get('/api/v1/integraciones/bandeja?tipo=clientes', headers=admin)
                    fila = next(f for f in solicitudes.json['solicitudes'] if f['origen'] == 'acadesys-api.onrender.com')
                    self.assertEqual(fila['datos']['nombre'], 'Ana Prueba')
                    self.assertEqual(fila['datos']['numero_documento'], '12345678')
                    self.assertEqual(fila['datos']['acadesys']['idCliente'], 'ACAD-01')
                    self.assertNotIn('clave-fixture', str(fila))
        db_engine.dispose()
