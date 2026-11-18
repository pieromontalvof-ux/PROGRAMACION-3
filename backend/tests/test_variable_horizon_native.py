import unittest
from datetime import date, timedelta
from app.modules.inventarios import weekly


class VariableHorizonNativeTests(unittest.TestCase):
    def test_ten_days_sum_actual_weekdays_and_preserve_seven_day_alias(self):
        today = date(2026, 11, 16)
        days = [today-timedelta(days=n) for n in range(1,29)]
        coverage = [dict(fecha=d,cobros=1,cobros_con_inventario=1) for d in days]
        consumption = [dict(fecha=d,id_producto=1,cantidad=d.weekday()+1) for d in days]
        products = [dict(id_producto=1,nombre='A',stock_actual=3,presentacion=6)]
        result = weekly.calculate(today,[],consumption,products,coverage,porcentaje=10,dias=10)
        row = result['productos'][0]
        self.assertEqual(row['consumo_proyectado'],37.4)
        self.assertEqual(row['consumo_proyectado_7_dias'],30.8)
        self.assertEqual(row['cantidad_sin_redondear'],34.4)
        self.assertEqual(row['cantidad_sugerida'],36)
        self.assertEqual(result['periodos']['proyeccion'],dict(desde='2026-11-16',hasta='2026-11-25',dias=10))
        self.assertEqual(result['periodos']['proxima_entrega'],'2026-11-26')
        self.assertEqual(result['metadata']['dias_abastecimiento'],10)
        self.assertEqual(result['periodos']['base_cobertura']['dias'],20)

    def test_calculator_rejects_invalid_horizon(self):
        for value in (0,-1,91,1.5,float('nan'),True,'1.0','NaN'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                weekly.calculate(date(2026,11,16),[],[],[],[],dias=value)


    def test_native_endpoints_validate_and_forward_days(self):
        from unittest.mock import patch
        from app import create_app
        from flask_jwt_extended import create_access_token
        app=create_app()
        app.config['JWT_SECRET_KEY']='variable-horizon-tests-at-least-32-characters'
        with app.app_context():
            token=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':7})
        client=app.test_client()
        headers={'Authorization':'Bearer '+token}
        fake={'reposicion':[],'metadata':{'historial_completo':True},'periodos':{}}
        with patch('app.core.extensions.db.session.execute') as execute, patch('app.modules.inventarios.operativo.contexto',return_value=(7,2,2)), patch('app.core.local_scope.local_actual',return_value=7), patch.object(weekly,'report',return_value=fake) as report:
            execute.return_value.scalar.return_value=True
            for url in ('/api/inventario-operativo/plan-semanal','/api/ordenes-compra/pedido-sugerido?horizonte=semanal'):
                separator='&' if '?' in url else '?'
                response=client.get(url+separator+'dias=10',headers=headers)
                self.assertEqual(response.status_code,200,response.get_json())
                self.assertEqual(report.call_args.kwargs['dias'],10)
                for value in ('0','-1','91','1.5','NaN','Infinity','oops'):
                    self.assertEqual(client.get(url+separator+'dias='+value,headers=headers).status_code,400)
