import unittest
from unittest.mock import patch
from decimal import Decimal


def mock_capacity_catalog(self):
    rows = [
        dict(codigo='MLT', alias='ML', factor=Decimal(1)),
        dict(codigo='LTR', alias='L', factor=Decimal(1000)),
        dict(codigo='FLOZ_US', alias=None, factor=Decimal('29.5735295625')),
        dict(codigo='FLOZ_UK', alias=None, factor=Decimal('28.4130625')),
    ]
    loader = patch('app.modules.carta.measurements._leer_unidades_capacidad', return_value=rows)
    loader.start()
    self.addCleanup(loader.stop)


class TablewareMeasurementTests(unittest.TestCase):
    def setUp(self):
        mock_capacity_catalog(self)
        self.reglas = {
            campo: dict(etiqueta=campo, maximo=Decimal(1000000 if campo == 'capacidad' else 10000), decimales=3)
            for campo in ('capacidad', 'diametro_cm', 'altura_cm', 'largo_cm', 'ancho_cm')
        }
        reglas = patch('app.modules.carta.measurements._reglas_medidas', return_value=self.reglas)
        reglas.start()
        self.addCleanup(reglas.stop)

    def test_limits_and_precision_follow_configured_rules(self):
        from app.modules.carta.measurements import validated

        self.reglas['altura_cm'].update(maximo=Decimal('20'), decimales=4)
        self.assertEqual(validated({'altura_cm': '19.1234'})['altura_cm'], Decimal('19.1234'))
        with self.assertRaises(ValueError):
            validated({'altura_cm': '21'})
        with self.assertRaises(ValueError):
            validated({'altura_cm': '19.12345'})
        self.assertEqual(validated({'nombre': 'Existing'}, {'altura_cm': Decimal(30)})['altura_cm'], Decimal(30))


    def test_rectangular_dimensions_and_demo_label(self):
        from app.modules.carta.measurements import validated, serialize
        dimensions=validated({'largo_cm':40,'ancho_cm':30,'altura_cm':3})
        self.assertEqual(dimensions['largo_cm'],Decimal(40))
        self.assertEqual(dimensions['ancho_cm'],Decimal(30))
        self.assertIsNone(serialize(dimensions)['capacidad_ml'])
        with self.assertRaises(ValueError):validated({'ancho_cm':0})

    def test_fluid_ounces_and_liters_convert_to_ml(self):
        from app.modules.carta.measurements import milliliters
        self.assertEqual(milliliters(12,'FLOZ_US'),Decimal('354.8823547500'))
        self.assertEqual(milliliters('0.5','LTR'),Decimal('500'))
        self.assertEqual(milliliters(12,'FLOZ_UK'),Decimal('340.9567500'))
        with self.assertRaises(ValueError):milliliters(12,'oz')

    def test_edit_preserves_unmentioned_measurements_and_allows_explicit_clearing(self):
        from app.modules.carta.measurements import validated
        old={'capacidad':12,'unidad_capacidad':'FLOZ_US','diametro_cm':8,'altura_cm':12}
        self.assertEqual(validated({'nombre':'Nuevo nombre'},old)['capacidad'],Decimal(12))
        cleared=validated({'capacidad':None,'unidad_capacidad':None},old)
        self.assertIsNone(cleared['capacidad'])
        self.assertEqual(cleared['diametro_cm'],Decimal(8))

    def test_rejects_invalid_or_unpaired_measurements(self):
        from app.modules.carta.measurements import validated
        for values in ({'capacidad':0,'unidad_capacidad':'MLT'},{'capacidad':12},
                       {'capacidad':12,'unidad_capacidad':'oz'},{'diametro_cm':-5},
                       {'altura_cm':'NaN'},{'capacidad':True,'unidad_capacidad':'MLT'}):
            with self.subTest(values=values),self.assertRaises(ValueError):validated(values)

    def test_capacity_cannot_be_inferred_from_plate_diameter(self):
        from app.modules.carta.measurements import serialize,ensure_fits
        row=serialize({'nombre':'Plato','diametro_cm':24})
        self.assertIsNone(row['capacidad_ml'])
        ensure_fits(row,500,'MLT')
        with self.assertRaises(ValueError):
            ensure_fits({'capacidad':12,'unidad_capacidad':'FLOZ_US'},500,'MLT')
