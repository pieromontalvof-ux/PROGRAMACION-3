import io
import json
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch


class OfflineEvalTests(unittest.TestCase):
    def test_default_suite_passes_without_network(self):
        from app.multiagente.evals.runner import run_cases

        with patch('socket.socket.connect', side_effect=AssertionError('Network forbidden')):
            results = run_cases()
        self.assertGreaterEqual(len(results), 15)
        self.assertTrue(all(result['passed'] for result in results), results)

    def test_wrong_route_and_exception_are_reported_as_failures(self):
        from app.multiagente.evals.runner import run_cases

        results = run_cases([
            {'id': 'wrong-route', 'kind': 'route', 'instruction': 'Crear receta', 'expected': 'inventario'},
            {'id': 'invalid-kind', 'kind': 'unknown', 'expected': None},
        ])
        self.assertEqual([result['passed'] for result in results], [False, False])
        self.assertEqual(results[0]['actual'], 'recetas')
        self.assertIn('error', results[1])

    def test_cli_json_reports_counts_and_returns_nonzero_on_failure(self):
        from app.multiagente.evals.runner import main

        output = io.StringIO()
        with patch('app.multiagente.evals.runner.run_cases', return_value=[
            {'id': 'failure', 'passed': False, 'expected': True, 'actual': False},
        ]), redirect_stdout(output):
            status = main(['--json'])
        self.assertEqual(status, 1)
        self.assertEqual(json.loads(output.getvalue())['summary'], {'total': 1, 'passed': 0, 'failed': 1})

    def test_cli_text_reports_successful_gate(self):
        from app.multiagente.evals.runner import main

        output = io.StringIO()
        with redirect_stdout(output):
            status = main([])
        self.assertEqual(status, 0)
        self.assertIn('failed=0', output.getvalue())
        self.assertIn('offline', output.getvalue().lower())
