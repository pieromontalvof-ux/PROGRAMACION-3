import unittest
from dataclasses import replace
from unittest.mock import patch

from app.multiagente.agents.catalog_specialists import SPECIALISTS
from app.multiagente.agents.manifest import catalog


class AgentManifestGraphTests(unittest.TestCase):
    def test_administration_agents_are_visible_without_operational_routing(self):
        manifest = catalog()
        administration = manifest['administracion']
        self.assertEqual({agent['id'] for agent in administration}, {'actualizador_skills', 'validador_skills'})
        for agent in administration:
            self.assertTrue(agent['skills'][0]['contenido'])
            self.assertEqual(agent['recursos_modificables'], [])
            self.assertNotIn(agent['id'], manifest['coordinador']['relaciones'])

    def test_coordinator_connects_every_specialist_and_includes_purchase_routing(self):
        manifest = catalog()
        self.assertEqual(
            {edge['destino'] for edge in manifest.get('conexiones', [])
             if edge['origen'] == 'orquestador' and edge['tipo'] == 'coordinacion'},
            {'compras', 'inventario', 'recepcion', 'eventos', 'demanda', 'carta_recetas', 'categorias_carta', 'menajes',
             'presentaciones', 'subproductos', 'recetas', 'promociones'},
        )
        self.assertIn('compra', manifest['coordinador']['reglas_ruta'].get('compras', []))

    def test_dependencies_point_from_consumer_to_resource_owner(self):
        dependencies = {(edge['origen'], edge['destino'])
                        for edge in catalog().get('conexiones', []) if edge['tipo'] == 'dependencia'}
        self.assertEqual(dependencies, {
            ('compras', 'demanda'), ('compras', 'eventos'),
            ('compras', 'inventario'),
            ('presentaciones', 'categorias_carta'), ('presentaciones', 'menajes'),
            ('subproductos', 'carta_recetas'), ('recetas', 'presentaciones'),
            ('recetas', 'carta_recetas'), ('recetas', 'subproductos'),
            ('promociones', 'presentaciones'),
            ('promociones', 'recetas'), ('promociones', 'subproductos'),
            ('promociones', 'carta_recetas'), ('promociones', 'inventario'),
            ('promociones', 'demanda'),
            ('presentaciones', 'carta_recetas'), ('presentaciones', 'inventario'),
            ('recetas', 'inventario'), ('subproductos', 'inventario'),
            ('presentaciones', 'recetas'), ('presentaciones', 'subproductos'),
        })

    def test_dependency_changes_in_canonical_specialist_reach_manifest(self):
        changed = replace(SPECIALISTS['promociones'], dependencies=('menajes', 'productos'))
        with patch.dict(SPECIALISTS, promociones=changed):
            dependencies = {(edge['origen'], edge['destino']) for edge in
                            catalog().get('conexiones', []) if edge['tipo'] == 'dependencia'}
        self.assertIn(('promociones', 'menajes'), dependencies)
        self.assertIn(('promociones', 'carta_recetas'), dependencies)
        self.assertNotIn(('promociones', 'presentaciones'), dependencies)
