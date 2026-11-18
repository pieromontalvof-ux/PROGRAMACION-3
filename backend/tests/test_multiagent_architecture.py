"""Dependency boundaries keep business modules independent of the assistant."""
import ast
from importlib.util import resolve_name
from pathlib import Path
import unittest

APP = Path(__file__).resolve().parents[1] / 'app'


class MultiagentArchitectureTests(unittest.TestCase):
    def test_multiagent_packages_are_consolidated(self):
        self.assertTrue((APP / 'multiagente' / 'agents' / '__init__.py').is_file())
        self.assertTrue((APP / 'multiagente' / 'api' / '__init__.py').is_file())
        self.assertFalse((APP / 'agents').exists())
        self.assertFalse((APP / 'modules' / 'asistente_ia').exists())

    def test_business_dependencies_do_not_import_multiagent(self):
        violations = []
        for root in (APP / 'modules', APP / 'core'):
            for source in root.rglob('*.py'):
                for node in ast.walk(ast.parse(source.read_text(encoding='utf-8-sig'))):
                    names = []
                    if isinstance(node, ast.Import):
                        names = [alias.name for alias in node.names]
                    elif isinstance(node, ast.ImportFrom):
                        module = node.module or ''
                        if node.level:
                            package = '.'.join(source.relative_to(APP.parent).parts[:-1])
                            module = resolve_name('.' * node.level + module, package)
                        names = [module, *(module + '.' + alias.name for alias in node.names)]
                    if any(name.startswith(('app.multiagente', 'app.agents', 'app.modules.asistente_ia')) for name in names):
                        violations.append(str(source.relative_to(APP)))
        self.assertEqual([], sorted(set(violations)))
