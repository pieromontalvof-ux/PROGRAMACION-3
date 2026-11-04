"""Reject unsupported promotion edits before creating a reviewable draft."""
import copy
import unittest
from unittest.mock import patch

from app.modules.asistente_ia import tools
from app.modules.asistente_ia.provider import AssistantError


PROMOTION = {
    'id_promocion': 9, 'codigo': 'P-009', 'nombre': 'Dos bebidas', 'precio': 30,
    'activo': True, 'hora_inicio': '18:00', 'hora_fin': '22:00', 'reposiciones': [11],
    'grupos': [{'id_promocion_grupo': 7, 'cantidad_elegir': 1, 'permite_repetir': False,
                'opciones': [{'id_presentacion_venta': 11}, {'id_presentacion_venta': 12}]}],
}


class AssistantPromotionSafetyTests(unittest.TestCase):
    def prepare(self, changes, previous=None):
        # Exercise real current_record/editable/prepare; only native HTTP reads
        # are replaced, using the actual service's reposiciones:list[int] shape.
        with patch.object(tools, 'authorize'), patch.object(tools, 'native',
                return_value={'promociones': [previous if previous is not None else copy.deepcopy(PROMOTION)]}):
            return tools.prepare({}, 'promociones', 'editar', 9, changes)

    def group(self, options, group_id=7):
        return {'id_promocion_grupo': group_id, 'cantidad_elegir': 1,
                'permite_repetir': False, 'opciones': options}

    def test_removing_a_replenishment_option_is_rejected_before_a_plan_exists(self):
        with self.assertRaises(AssistantError) as caught:
            self.prepare({'grupos': [self.group([12])]})
        self.assertEqual(caught.exception.status, 400)
        self.assertIn('Promociones', str(caught.exception))
        self.assertIn('reposición', str(caught.exception))

    def test_price_only_edit_keeps_groups_and_original_replenishment_state(self):
        plan = self.prepare({'precio': 35})
        self.assertEqual(plan['datos']['precio'], 35)
        self.assertEqual(plan['datos']['grupos'], [self.group([11, 12])])
        self.assertEqual(plan['anterior']['reposiciones'], [11])
        self.assertNotIn('reposiciones', plan['datos'])

    def test_can_remove_other_options_or_move_replenishment_option_to_another_group(self):
        for groups in ([self.group([11])], [self.group([12]), self.group([11], None)]):
            with self.subTest(groups=groups):
                self.assertEqual(self.prepare({'grupos': groups})['datos']['grupos'], groups)

    def test_promotion_without_replenishments_can_replace_options(self):
        previous = {**copy.deepcopy(PROMOTION), 'reposiciones': []}
        self.assertEqual(self.prepare({'grupos': [self.group([12])]}, previous)['datos']['grupos'],
                         [self.group([12])])

    def test_ai_cannot_clear_replenishments_to_bypass_option_guard(self):
        with self.assertRaises(AssistantError):
            self.prepare({'grupos': [self.group([12])], 'reposiciones': []})

    def test_malformed_replacement_options_fail_with_a_reviewable_error(self):
        for groups in (None, 'invalid', [None], [{'opciones': {}}], [{'opciones': [{}]}]):
            with self.subTest(groups=groups), self.assertRaises(AssistantError):
                self.prepare({'grupos': groups})


if __name__ == '__main__':
    unittest.main()
