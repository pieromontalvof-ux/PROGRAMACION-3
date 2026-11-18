import unittest
from datetime import date,timedelta
from unittest.mock import patch
from app.modules.inventarios.weekly import calculate
from app.multiagente.agents.demanda.weekly_summary import analyze

class CoverageWindowTests(unittest.TestCase):
    def test_coverage_uses_twenty_days_without_changing_weekly_order(self):
        today=date(2026,11,15)
        days=[today-timedelta(days=i) for i in range(1,29)]
        history=[dict(fecha=d,cobros=1,cobros_con_inventario=1) for d in days]
        consumption=[dict(fecha=d,id_producto=1,cantidad=2 if i<20 else 10) for i,d in enumerate(days)]
        r=calculate(today,[],consumption,[dict(id_producto=1,nombre='A',stock_actual=10,presentacion=1)],history)
        self.assertEqual(r['productos'][0]['consumo_diario'],2)
        self.assertEqual(r['productos'][0]['cobertura_dias'],5)
        self.assertEqual(r['periodos']['base_cobertura']['dias'],20)
        self.assertEqual(r['periodos']['proyeccion']['dias'],7)

    def test_only_coverage_up_to_ten_days_is_rendered(self):
        report={'productos':[dict(nombre=name,cobertura_dias=value) for name,value in [('Urgente',2),('Limite',10),('Lejano',10.01)]], 'periodos':{}}
        with patch('app.multiagente.api.configuration.authorize'),patch('app.multiagente.api.tools.authorize'),patch('app.multiagente.api.tools.native',return_value=report):
            answer=analyze({})['respuesta']
        self.assertIn('Urgente',answer)
        self.assertIn('Limite',answer)
        self.assertNotIn('Lejano',answer)
