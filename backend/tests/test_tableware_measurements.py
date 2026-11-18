import unittest
from decimal import Decimal


class TablewareMeasurementTests(unittest.TestCase):
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
