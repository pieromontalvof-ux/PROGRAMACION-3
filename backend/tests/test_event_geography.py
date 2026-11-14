import unittest
from unittest.mock import patch
from app.agents.eventos import geography


class GeographyTests(unittest.TestCase):
    def test_nearby_venue_discovery_filters_distance_and_keeps_variety(self):
        from app.agents.eventos.nearby import parse
        origin={'lat':-12.057,'lon':-77.036}
        elements=[{'type':'node','id':1,'lat':-12.058,'lon':-77.036,'tags':{'name':'Hotel Próximo','tourism':'hotel'}},
                  {'type':'way','id':2,'center':{'lat':-12.059,'lon':-77.036},'tags':{'name':'Parque Cercano','leisure':'park'}},
                  {'type':'node','id':3,'lat':-12.15,'lon':-77.036,'tags':{'name':'Teatro Lejano','amenity':'theatre'}}]
        rows=parse(elements,origin,1500)
        self.assertEqual({r['nombre'] for r in rows},{'Hotel Próximo','Parque Cercano'})

    def test_distance_and_radius_use_server_coordinates_not_model_claim(self):
        origin={'lat':-12.057,'lon':-77.036,'url':'https://www.openstreetmap.org/node/1'}
        nearby={**origin,'lat':-12.060}
        far={**origin,'lat':-12.10}
        candidates=[{'nombre':'Cerca','fecha_desde':'2026-11-12','recinto':'Parque','direccion':'Av. 28 de Julio s/n','cercania':'PENDIENTE'},
                    {'nombre':'Lejos','fecha_desde':'2026-11-12','recinto':'Costa','direccion':'Otra dirección','cercania':'ACREDITADA'}]
        with patch.object(geography,'locate',side_effect=[origin,nearby,far]):
            result=geography.check({'nombre':'Sheraton','direccion':'Paseo de la República 170, Lima'},candidates)
        self.assertEqual(result['venues'][('cerca','2026-11-12')]['estado'],'DENTRO')
        self.assertEqual(result['venues'][('lejos','2026-11-12')]['estado'],'FUERA')
        self.assertGreater(result['venues'][('lejos','2026-11-12')]['distancia_m'],1500)

    def test_unknown_origin_never_accepts_model_nearby_flag(self):
        with patch.object(geography,'locate',return_value=None) as locate:
            result=geography.check({'nombre':'Bar','direccion':'Dirección incompleta'},[{'nombre':'Hotel','cercania':'ACREDITADA'}])
        self.assertIsNone(result['origin'])
        self.assertFalse(result['venues'])
        self.assertEqual(locate.call_count,1)

    def test_ambiguous_or_city_results_do_not_become_exact_venue(self):
        city={'lat':'-12.05','lon':'-77.03','addresstype':'city','name':'Lima','address':{'country_code':'pe'}}
        place={'lat':'-12.05','lon':'-77.03','addresstype':'hotel','name':'Hotel Uno','osm_type':'node','osm_id':1,
               'address':{'country_code':'pe','road':'Avenida Test','house_number':'100'}}
        self.assertIsNone(geography.select([city],'Hotel Uno','Avenida Test 100'))
        self.assertIsNone(geography.select([place,{**place,'lat':'-12.09'}],'Hotel Uno','Avenida Test 100'))
        self.assertIsNone(geography.select([place],'Hotel Uno','Avenida Test 999'))
        self.assertIsNotNone(geography.select([place],'Hotel Uno','Avenida Test 100'))

    def test_haversine_is_symmetric_and_zero_for_same_place(self):
        self.assertEqual(geography.distance((-12,-77),(-12,-77)),0)
        self.assertAlmostEqual(geography.distance((-12,-77),(-12.01,-77)),1112,delta=2)

    def test_radius_boundary_with_uncertainty_remains_pending(self):
        origin={'lat':-12,'lon':-77,'incertidumbre_m':20,'url':'https://www.openstreetmap.org/node/1'}
        venue={**origin,'lat':-12.0135,'incertidumbre_m':100}
        row={'nombre':'Borde','fecha_desde':'2026-11-12','recinto':'Parque','direccion':'Dirección Lima'}
        with patch.object(geography,'locate',side_effect=[origin,venue]):
            result=geography.check({'nombre':'Bar','direccion':'Dirección Lima'},[row])
        self.assertEqual(result['venues'][('borde','2026-11-12')]['estado'],'PENDIENTE')

    def test_street_date_is_not_house_number_and_large_polygons_are_not_precise(self):
        row={'lat':'-12.05','lon':'-77.03','addresstype':'theatre','name':'Teatro Uno','osm_type':'way','osm_id':1,
             'boundingbox':['-12.0501','-12.0499','-77.0301','-77.0299'],
             'address':{'country_code':'pe','road':'Avenida 28 de Julio','house_number':'800'}}
        self.assertIsNotNone(geography.select([row],'Teatro Uno','Avenida 28 de Julio 800'))
        self.assertIsNone(geography.select([{**row,'address':{**row['address'],'house_number':'28'}}],'Teatro Uno','Avenida 28 de Julio 800'))
        huge={**row,'boundingbox':['-12.1','-12.0','-77.1','-77.0']}
        self.assertIsNone(geography.select([huge],'Teatro Uno','Avenida 28 de Julio 800'))
