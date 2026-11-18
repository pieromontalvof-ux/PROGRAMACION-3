import unittest
from unittest.mock import patch
from app.multiagente.agents.demanda import summary
from app.multiagente.agents.orchestrator import purchase_review
from app.multiagente.agents.eventos import research


class CleanTablesTests(unittest.TestCase):
    def test_unverified_distance_is_visible_with_explicit_warning(self):
        row={'nombre':'Westin San Isidro','fecha_desde':'2026-11-20','recinto':'Westin',
             'decision':'PENDIENTE','cercania':'PENDIENTE','relevancia':'POTENCIAL','motivo':'Cercanía sin comprobar'}
        self.assertIn('Westin',research.render([row]))
        self.assertIn('Cercanía sin confirmar',research.render([row]))
        self.assertIn('Cercanía sin comprobar',research.render([row]))
        self.assertNotIn('Westin',research.render_details([row]))

    def test_sales_and_coverage_are_numeric_tables_without_technical_paragraphs(self):
        report={'recurso':'demanda_rotacion','total':141,'registros':[{'id_producto':1,'nombre':'Limón','unidad':'KGM',
                'stock_actual':1.753,'consumo_diario':0.6133,'cobertura_dias':2.86}],
                'contexto':{'desde':'2026-10-16','hasta':'2026-11-14','dias_calendario':30,
                'articulos':[{'nombre':'Mojito','cantidad':92.0,'ventas_diarias':3.0667}],
                'resumen':{'productos_con_consumo':15}}}
        with patch.object(summary.configuration,'authorize'),patch.object(summary.demand,'read',return_value=report):
            result=summary.analyze({}, {})
        self.assertIn('| Producto | Cantidad vendida | Promedio por día |',result['respuesta'])
        self.assertIn('| Mojito | 92 | 3.07 |',result['respuesta'])
        self.assertIn('| Insumo | Stock | Consumo diario | Cobertura estimada (días) |',result['respuesta'])
        for text in ('Período analizado','Ranking por','Se evaluaron','Se muestran','Este análisis histórico'):
            self.assertNotIn(text,result['respuesta'])

    def test_replenishment_is_table_without_rounding_explanation(self):
        data={'productos':[{'id_producto':1,'nombre':'Limón','unidad':'KGM','stock_actual':1.753,
              'cantidad_sugerida':17,'cantidad_sin_redondear':16.557}]}
        with patch.object(purchase_review,'base',return_value=data):
            lines,_=purchase_review.replenishment({},None)
        text='\n'.join(lines)
        self.assertIn('| Insumo | Stock actual | Reponer |',text)
        self.assertIn('| Limón | 1.753 kg | 17 kg |',text)
        self.assertNotIn('antes de redondear',text)
        self.assertNotIn('Se muestran',text)

    def test_related_pending_events_are_visible_and_only_discards_go_to_review(self):
        rows=[{'nombre':'Concierto','fecha_desde':'','recinto':'Parque','tipo':'Música','relevancia':'POTENCIAL','decision':'PENDIENTE','cercania':'ACREDITADA','motivo':'Hora pendiente'},
              {'nombre':'Lejano','fecha_desde':'2026-11-15','recinto':'Otro distrito','tipo':'Música','decision':'DESCARTADO','motivo':'Fuera del radio'}]
        main=research.render(rows)
        self.assertIn('Concierto',main)
        self.assertIn('Por confirmar',main)
        self.assertNotIn('Lejano',main)
        self.assertNotIn('candidatos pendientes',main)
        detail=research.render_details(rows)
        self.assertIn('Lejano',detail)
        self.assertIn('| Día | Evento publicado | Tipo | Lugar | Motivo |',detail)
        self.assertNotIn('Concierto',detail)
