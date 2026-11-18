"""Administrative reviewer: no tools, no grants, no writes."""
import json
from pathlib import Path
from app.multiagente.api import provider
from app.multiagente.api.provider import AssistantError
from app.multiagente.agents.document_inputs import messages as reference_messages

SKILL = Path(__file__).parents[2] / 'api/skills/revisor_configuracion/SKILL.md'


def review(proposal):
    messages = reference_messages(SKILL.read_text(encoding='utf-8'), proposal)
    output = provider.respond(messages, [])
    text = '\n'.join(content.get('text', '') for item in output for content in item.get('content', []) if content.get('type') == 'output_text').strip()
    if text.startswith('```'):
        text = '\n'.join(text.splitlines()[1:-1])
    try:
        report = json.loads(text)
        keys = {'resumen', 'informacion_faltante', 'accesos_necesarios', 'recomendaciones', 'conflictos'}
        if not isinstance(report, dict) or set(report) != keys or not isinstance(report['resumen'], str) or len(report['resumen']) > 4000:
            raise ValueError()
        for key in keys - {'resumen'}:
            if not isinstance(report[key], list) or len(report[key]) > 20 or any(not isinstance(item, str) or len(item) > 1500 for item in report[key]):
                raise ValueError()
        return report
    except (ValueError, TypeError):
        raise AssistantError('El revisor no devolvió un informe válido. Conserva tus cambios y vuelve a revisar.', 502) from None
