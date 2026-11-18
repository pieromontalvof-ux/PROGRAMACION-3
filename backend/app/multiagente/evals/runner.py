"""Run with: python -m app.multiagente.evals [--json], from backend.

This gate covers native routing and menu authorization only. It does not
measure live LLM quality, native HTTP local scoping or database behavior.
"""
import argparse
import json

from app.multiagente.api import tools
from app.multiagente.api.provider import AssistantError
from app.multiagente.agents.orchestrator.router import route
from .cases import CASES


def run_cases(cases=None):
    results = []
    for case in CASES if cases is None else cases:
        result = {'id': case['id'], 'expected': case['expected'], 'passed': False}
        try:
            if case['kind'] == 'route':
                actual = route(case['instruction'], case.get('previous', ''))
            elif case['kind'] == 'permission':
                actual = tools.allowed(case['session'], case['resource'], case.get('action', 'consultar'))
            elif case['kind'] == 'authorize':
                try:
                    tools.authorize(case['session'], case['resource'], case.get('action', 'consultar'))
                    actual = 200
                except AssistantError as error:
                    actual = error.status
            else:
                raise ValueError('Unknown case kind: ' + str(case['kind']))
            result.update(actual=actual, passed=actual == case['expected'])
        except Exception as error:
            result['error'] = type(error).__name__ + ': ' + str(error)
        results.append(result)
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true', help='Emit machine-readable results')
    args = parser.parse_args(argv)
    results = run_cases()
    passed = sum(result['passed'] for result in results)
    summary = {'total': len(results), 'passed': passed, 'failed': len(results) - passed}
    if args.json:
        print(json.dumps({'mode': 'offline-synthetic', 'summary': summary, 'results': results}, ensure_ascii=True))
    else:
        print('Offline synthetic gate: ' + ' '.join(f'{key}={value}' for key, value in summary.items()))
        for result in results:
            if not result['passed']:
                print('FAIL ' + json.dumps(result, ensure_ascii=True))
    return 1 if summary['failed'] or not results else 0
