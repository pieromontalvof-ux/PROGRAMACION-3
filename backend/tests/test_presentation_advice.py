import unittest
from unittest.mock import patch
from flask import Flask

REQUEST='Quiero crear una presentación de venta llamada “Limonada especial”, de 400 mL, a S/ 15, en la categoría “Bebidas de temporada”. Si esa categoría no existe, quiero crearla primero. Revisa también qué menajes hay disponibles antes de continuar.'
ROWS={
 'productos':[], 'proveedores':[],
 'categorias_carta':[{'id_categoria_carta':1,'nombre':'Bebidas','prefijo':'BE','activo':True},{'id_categoria_carta':2,'nombre':'Otra','prefijo':'BT','activo':False}],
 'menajes':[{'id_menaje':5,'nombre':'Vaso','activo':True},{'id_menaje':6,'nombre':'Copa','activo':True}],
 'presentaciones':[{'id_presentacion_venta':10,'nombre':'Limonada clásica','id_categoria_carta':1,'id_menaje':5,'contenido':0.4,'unidad':'LTR','activo':True}],
}

class PresentationAdviceTests(unittest.TestCase):
 def setUp(self):
  self.ctx=Flask(__name__).test_request_context();self.ctx.push();self.addCleanup(self.ctx.pop)
  for target,kwargs in [('app.modules.asistente_ia.tools.allowed',{'return_value':True}),('app.modules.asistente_ia.tools.authorize',{}),('app.modules.asistente_ia.configuration.authorize',{}),('app.modules.asistente_ia.configuration.authorize_owner',{}),('app.modules.asistente_ia.configuration.owner_allows',{'return_value':True})]:
   p=patch(target,**kwargs);p.start();self.addCleanup(p.stop)

 def test_user_quote_styles_keep_the_same_name_category_and_amount(self):
  from app.agents.orchestrator.presentation_advice import parse
  for opening,closing in [('‘','’'),("'","'"),('“','”'),('«','»'),('"','"')]:
   instruction=(f'Quiero crear una presentación de venta llamada {opening}Limonada especial{closing}, '
                f'de 500 mL, a S/ 15, en la categoría {opening}Bebidas de temporada{closing}.')
   with self.subTest(opening=opening):
    self.assertEqual(parse(instruction),{'nombre':'Limonada especial','categoria':'Bebidas de temporada',
                     'cantidad':'500','unidad':'mL','precio':'15','mililitros':'500'})

 def test_apostrophe_inside_double_quotes_is_part_of_the_name(self):
  from app.agents.orchestrator.presentation_advice import parse
  for opening,closing in [('"','"'),('“','”'),('«','»')]:
   instruction=(f'Crear una presentación llamada {opening}Limonada d\'autor{closing}, '
                f'de 500 mL, a S/ 15, en la categoría {opening}Bebidas{closing}')
   with self.subTest(opening=opening):
    self.assertEqual(parse(instruction)['nombre'],"Limonada d'autor")

 def test_unclosed_or_mismatched_quotes_do_not_seal_a_partial_name(self):
  from app.agents.orchestrator.presentation_advice import parse
  for opening,closing in [('"','’'),('‘','"')]:
   instruction=(f'Crear una presentación llamada {opening}Limonada especial{closing}, '
                'de 500 mL, a S/ 15, en la categoría «Bebidas»')
   with self.subTest(opening=opening):
    self.assertIsNone(parse(instruction))

 def test_different_reference_volume_offers_a_choice_before_category_and_type(self):
  from app.agents.orchestrator import presentation_advice
  with patch('app.modules.asistente_ia.tools.records',side_effect=lambda session,resource:ROWS[resource]):
   result=presentation_advice.run({},REQUEST.replace('400 mL','500 mL'))
  answer=result['respuesta']
  self.assertIn('400 mL',answer)
  self.assertIn('500 mL',answer)
  self.assertIn('S/ 15.00',answer)
  self.assertIn('revisar el precio',answer)
  self.assertNotIn('capacidad de',answer)
  question=answer[answer.index('¿'):]
  self.assertNotIn('preparada',question)
  self.assertNotIn('prefijo',question)
  self.assertEqual(answer.count('¿'),1)
  self.assertEqual(result['_referencias_revisadas']['decision_pendiente'],'medida_precio')
  self.assertIsNone(result['plan'])

 def test_matching_volume_does_not_offer_an_unnecessary_size_adjustment(self):
  from app.agents.orchestrator import presentation_advice
  with patch('app.modules.asistente_ia.tools.records',side_effect=lambda session,resource:ROWS[resource]):
   result=presentation_advice.run({},REQUEST)
  self.assertNotIn('revisar el precio',result['respuesta'])
  self.assertEqual(result['_referencias_revisadas']['decision_pendiente'],'categoria')

 def test_compact_advice_combines_real_categories_tableware_and_comparable_volume(self):
  from app.agents.orchestrator import presentation_advice
  with patch('app.modules.asistente_ia.tools.records',side_effect=lambda session,resource:ROWS[resource]),patch('app.modules.asistente_ia.tools.execute') as write,patch('app.modules.asistente_ia.provider.respond') as model:
   result=presentation_advice.run({},REQUEST)
  self.assertIsNone(result['plan']);self.assertNotIn('formulario',result)
  self.assertIn('400 mL',result['respuesta']);self.assertIn('Vaso',result['respuesta'])
  self.assertIn('Bebidas',result['respuesta']);self.assertNotIn('prefijo **BT**',result['respuesta'])
  self.assertLess(len(result['respuesta']),1000)
  write.assert_not_called();model.assert_not_called()

 def test_no_matching_volume_does_not_invent_vessel_capacity(self):
  from app.agents.orchestrator import presentation_advice
  source={**ROWS,'presentaciones':[]}
  with patch('app.modules.asistente_ia.tools.records',side_effect=lambda session,resource:source[resource]):result=presentation_advice.run({},REQUEST)
  self.assertIn('sin una referencia de volumen comparable',result['respuesta'])
  self.assertNotIn('capacidad de 400',result['respuesta'])

 def test_unstructured_or_ambiguous_requests_remain_in_normal_conversation(self):
  from app.agents.orchestrator import presentation_advice
  with patch('app.modules.asistente_ia.tools.records') as read:
   self.assertIsNone(presentation_advice.run({},'Quiero crear una presentación'))
  read.assert_not_called()

 def test_native_item_names_prioritize_related_drinks_and_do_not_mix_units(self):
  from app.agents.orchestrator import presentation_advice
  source={**ROWS,'presentaciones':[
   {'id_menaje':6,'contenido':0.4,'unidad':'LTR','item':'174 IPA','id_categoria_carta':2,'activo':True},
   {'id_menaje':5,'contenido':0.4,'unidad':'KGM','item':'Limonada en polvo','activo':True},
   {'id_menaje':5,'contenido':0.5,'unidad':'LTR','item':'Limonada clásica','id_categoria_carta':1,'activo':True}]}
  with patch('app.modules.asistente_ia.tools.records',side_effect=lambda session,resource:source[resource]):result=presentation_advice.run({},REQUEST)
  self.assertIn('sugiero **Vaso**',result['respuesta'])
  self.assertEqual(result['_referencias_revisadas']['referencia_volumen']['unidad'],'LTR')
  self.assertEqual(result['_referencias_revisadas']['referencia_volumen']['item'],'Limonada clásica')

 def test_existing_presentation_is_not_proposed_as_a_new_record(self):
  from app.agents.orchestrator import presentation_advice
  source={**ROWS,'presentaciones':[{'id_presentacion_venta':9,'item':'Limonada especial','contenido':0.4,'unidad':'LTR','activo':True}]}
  with patch('app.modules.asistente_ia.tools.records',side_effect=lambda session,resource:source[resource]):result=presentation_advice.run({},REQUEST)
  self.assertIn('Ya existe',result['respuesta'])
  self.assertNotIn('Propongo crearla',result['respuesta'])
  self.assertIsNone(result['plan'])

 def test_inactive_duplicate_is_reported_instead_of_recreated(self):
  from app.agents.orchestrator import presentation_advice
  source={**ROWS,'presentaciones':[{'id_presentacion_venta':9,'item':'Limonada especial','contenido':0.4,'unidad':'LTR','activo':False}]}
  with patch('app.modules.asistente_ia.tools.records',side_effect=lambda session,resource:source[resource]):result=presentation_advice.run({},REQUEST)
  self.assertIn('inactiva',result['respuesta'])
  self.assertIn('coincidencias_existentes',result['_referencias_revisadas'])

 def test_out_of_range_numbers_do_not_crash_or_read_catalogs(self):
  from app.agents.orchestrator import presentation_advice
  with patch('app.modules.asistente_ia.tools.records') as read:
   for value in (REQUEST.replace('S/ 15','S/ '+'9'*40),REQUEST.replace('400 mL','9'*40+' mL')):
    self.assertIsNone(presentation_advice.run({},value))
  read.assert_not_called()
