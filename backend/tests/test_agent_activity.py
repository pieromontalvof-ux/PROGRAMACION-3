import tempfile
import unittest
from unittest.mock import patch
from flask import Flask


class AgentActivityTests(unittest.TestCase):
    def test_real_delegation_tools_and_final_are_saved_and_scoped(self):
        from app.agents import activity
        app=Flask(__name__)
        with tempfile.TemporaryDirectory() as folder, app.test_request_context('/api/asistente-ia/preparar',base_url='https://demo.example'):
            app.config['APP_DATA_DIR']=folder
            scope={'usuario':1,'perfil':2,'local':1}
            token=activity.begin('quiero revisar la demanda',scope)
            @activity.agent('demanda')
            def specialist(session,instruction):
                @activity.tool('analizar_demanda')
                def read(filters):return {'total':3,'registros':[{'nombre':'A'}],'api_key':'secreto'}
                read({'desde':'2026-10-01','token':'oculto'})
                return {'respuesta':'Hay tres registros.'}
            specialist({},'revisar demanda del local')
            trace=activity.finish({'respuesta':'Hay tres registros.'})
            activity.reset(token)
            self.assertEqual(trace['entrada'],'quiero revisar la demanda')
            self.assertEqual(trace['respuesta_final'],'Hay tres registros.')
            self.assertEqual(trace['agentes'],['orquestador','demanda'])
            self.assertTrue(any(e['tipo']=='delegacion' for e in trace['eventos']))
            self.assertTrue(any(e.get('herramienta')=='analizar_demanda' for e in trace['eventos']))
            self.assertNotIn('secreto',str(trace));self.assertNotIn('oculto',str(trace))
            with patch.object(activity,'scope',return_value=scope):self.assertEqual(activity.load(trace['id']),trace)
            with patch.object(activity,'scope',return_value={**scope,'local':2}):
                with self.assertRaises(Exception):activity.load(trace['id'])

    def test_failure_is_recorded_and_does_not_leak_internal_error(self):
        from app.agents import activity
        app=Flask(__name__)
        with tempfile.TemporaryDirectory() as folder,app.test_request_context('/'):
            app.config['APP_DATA_DIR']=folder
            token=activity.begin('consulta',{'usuario':1,'perfil':2,'local':1})
            @activity.tool('consultar')
            def broken():raise RuntimeError('password=secreto')
            with self.assertRaises(RuntimeError):broken()
            trace=activity.finish({'mensaje':'No disponible'},status=500)
            activity.reset(token)
            self.assertEqual(trace['estado'],'error')
            self.assertNotIn('secreto',str(trace))

    def test_validation_rejection_does_not_create_log_files(self):
        from app.agents import activity
        from pathlib import Path
        app=Flask(__name__)
        with tempfile.TemporaryDirectory() as folder,app.test_request_context('/'):
            app.config['APP_DATA_DIR']=folder
            token=activity.begin('',{'usuario':1,'perfil':2,'local':1})
            self.assertIsNone(activity.finish({'mensaje':'Instrucción inválida'},400))
            activity.reset(token)
            self.assertFalse(list(Path(folder).rglob('*.json')))

    def test_storage_failure_does_not_destroy_answer(self):
        from app.agents import activity
        app=Flask(__name__)
        with app.test_request_context('/'):
            token=activity.begin('Consulta',{'usuario':1,'perfil':2,'local':1})
            with patch('pathlib.Path.mkdir',side_effect=OSError('disk')):
                self.assertIsNone(activity.finish({'respuesta':'Respuesta útil'}))
            activity.reset(token)

