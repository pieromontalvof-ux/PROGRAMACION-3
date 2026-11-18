"""Draft-only skill author. Independent validation happens after this response."""
import json
from pathlib import Path
from app.multiagente.agents.document_inputs import messages
from app.multiagente.api import provider
from app.multiagente.api.provider import AssistantError

SKILL = Path(__file__).parents[2] / 'api/skills/actualizador_skills/SKILL.md'


def update(proposal):
    output = provider.respond(messages(SKILL.read_text(encoding='utf-8'), proposal), [], max_output_tokens=6000)
    text = '\n'.join(part.get('text', '') for item in output for part in item.get('content', []) if part.get('type') == 'output_text').strip()
    if text.startswith('```'):
        text = '\n'.join(text.splitlines()[1:-1])
    try:
        result = json.loads(text)
        if not isinstance(result, dict) or set(result) != {'contenido', 'resumen', 'informacion_faltante'}:
            raise ValueError()
        if not isinstance(result['contenido'], str) or not result['contenido'].strip() or len(result['contenido']) > 30000:
            raise ValueError()
        if not isinstance(result['resumen'], str) or len(result['resumen']) > 4000:
            raise ValueError()
        if not isinstance(result['informacion_faltante'], list) or len(result['informacion_faltante']) > 20 or any(not isinstance(row, str) or len(row) > 1500 for row in result['informacion_faltante']):
            raise ValueError()
        return result
    except (ValueError, TypeError):
        raise AssistantError('El actualizador no devolvió una propuesta válida. La skill guardada sigue intacta.', 502) from None
