"""Resolve a user-confirmed supply boundary, never infer it from 'weekly'."""
import re
from datetime import timedelta
from app.multiagente.api.tools import normalized
from app.multiagente.agents.eventos.period import resolve as event_period, NUMBERS

QUESTION='¿Hasta qué fecha necesitas que alcance este pedido? Puedes indicar una fecha o una duración, por ejemplo «10 días» o «dos semanas».'
WORDS={**NUMBERS,'una':1,'doce':12,'catorce':14,'veinte':20,'veintiuno':21}


def resolve(instruction,today,*,waiting=False):
    value=normalized(instruction).strip()
    # Historical lookbacks must not set a future supply duration.
    clauses=re.split(r'[.;!?]|\by\s+(?=(?:quiero|prepara|preparar|hacer|genera|generar|necesito|pedido|hasta|para)\b)',value)
    value=' '.join(re.split(r'\b(?:ventas|consumo|historial)\b',clause,maxsplit=1)[0] for clause in clauses).strip()
    pattern=r'(\d+|'+'|'.join(WORDS)+r')\s+(dias?|semanas?)\b'
    duration=re.search(r'\b(?:para|por|durante|proximos|proximas)\s+(?:los\s+|las\s+)?'+pattern,value)
    if duration is None and waiting:
        duration=re.fullmatch(r'\s*'+pattern+r'\s*[.!]?\s*',value)
    if duration:
        count=int(duration[1]) if duration[1].isdigit() else WORDS[duration[1]]
        days=count*(7 if duration[2].startswith('semana') else 1)
        if not 1<=days<=90:
            raise ValueError('Indica un plazo de entre 1 y 90 días.')
        return today.isoformat(),(today+timedelta(days=days)).isoformat()
    period=event_period(value,today,allow_day_only=waiting)
    if period:
        from datetime import date
        if not 1<=(date.fromisoformat(period[1])-today).days<=90:
            raise ValueError('Indica una fecha de próxima entrega posterior a hoy, hasta 90 días.')
        return today.isoformat(),period[1]
    return None
