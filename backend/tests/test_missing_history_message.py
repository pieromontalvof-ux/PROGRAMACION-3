import unittest
from datetime import date,timedelta
from unittest.mock import patch
from app.modules.inventarios.weekly import calculate
from app.multiagente.agents.demanda.weekly_summary import analyze


class MissingHistoryMessageTests(unittest.TestCase):
    def test_unknown_dates_are_explicit_not_observed_zero(self):
        today=date(2026,11,16)
        records=[dict(fecha=today-timedelta(days=i),cobros=1,cobros_con_inventario=1) for i in range(2,29)]
        report=calculate(today,[],[],[],records)
        self.assertEqual(report['metadata']['fechas_sin_registro'],['2026-11-15'])
        self.assertFalse(report['metadata']['cobertura_completa'])

    def test_unknown_coverage_does_not_claim_no_low_coverage_items(self):
        report={'productos':[],'periodos':{},'metadata':{'cobertura_completa':False,
                'fechas_sin_registro_cobertura':['2026-11-15'],'fechas_sin_registro':['2026-11-15']}}
        with patch('app.multiagente.api.configuration.authorize'),patch('app.multiagente.api.tools.authorize'),patch('app.multiagente.api.tools.native',return_value=report):
            text=analyze({})['respuesta']
        self.assertIn('2026-11-15',text)
        self.assertIn('No se pudo calcular la cobertura',text)
        self.assertNotIn('No hay insumos con cobertura',text)
