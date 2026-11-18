"""Resolve prospective event windows independently of historic sales periods."""
import re
from datetime import date, timedelta

from app.multiagente.api.tools import normalized

MONTHS = ('enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre').split()
WEEKDAYS = ('lunes martes miercoles jueves viernes sabado domingo').split()
NUMBERS = {'un':1, 'uno':1, 'dos':2, 'tres':3, 'cuatro':4, 'cinco':5,
           'seis':6, 'siete':7, 'ocho':8, 'nueve':9, 'diez':10, 'quince':15, 'treinta':30}


def resolve(instruction, today, *, allow_day_only=False, next_delivery=None):
    value = normalized(instruction)
    event = re.search(r'\b(?:eventos|conciertos|congresos)\b', value)
    if event:
        value = value[event.start():]
    # Sales lookback must never become the forward-looking event window.
    value = re.split(r'\b(?:y analiza|analiza|ventas|consumo)\b', value)[0]
    dates = re.findall(r'\b\d{4}-\d{2}-\d{2}\b', value)
    try:
        if dates:
            single_day = len(dates) == 1 and re.search(r'\bel\s+' + dates[0], value) and 'hasta' not in value
            start = date.fromisoformat(dates[0]) if len(dates) > 1 or single_day else today
            end = date.fromisoformat(dates[-1])
        else:
            days = re.search(r'proxim[oa]s?\s+(\d+|' + '|'.join(NUMBERS) + r')\s+dias?', value)
            until = re.search(r'hasta\s+(?:el\s+)?(\d{1,2})\s+de\s+(' + '|'.join(MONTHS) + r')(?:\s+(?:de\s+)?(\d{4}))?', value)
            weekday = re.search(r'\b(?:(proximo|este)\s+)?(' + '|'.join(WEEKDAYS) + r')\b', value)
            weekday_day = re.search(r'\b(' + '|'.join(WEEKDAYS) + r')\s+(\d{1,2})(?:\s+de\s+(' + '|'.join(MONTHS) + r'))?\b', value)
            short_day=re.search(r'\bhasta\s+(?:el\s+)?(?:dia\s+)?(\d{1,2})(?!\d)'
                                r'(?:\s+(?:de\s+(?:este|ese)\s+(?:mismo\s+)?|del\s+)mes)?'
                                r'(?=\s*(?:$|[,.;!?]|por favor\b|y\b))',value)
            if short_day is None and allow_day_only:
                short_day=re.fullmatch(r'\s*(?:el\s+)?(\d{1,2})[.!]?\s*',value)
            if days:
                count = int(days[1]) if days[1].isdigit() else NUMBERS[days[1]]
                start, end = today, today + timedelta(days=count - 1)
            elif until:
                start, end = today, date(int(until[3] or today.year), MONTHS.index(until[2]) + 1, int(until[1]))
            elif weekday_day:
                end = date(today.year, MONTHS.index(weekday_day[3]) + 1 if weekday_day[3] else today.month, int(weekday_day[2]))
                if end.weekday() != WEEKDAYS.index(weekday_day[1]):
                    raise ValueError()
                start = today if re.search(r'\b(?:hasta|hata)\b', value) else end
            elif short_day:
                start,end=today,date(today.year,today.month,int(short_day[1]))
            elif weekday:
                offset = (WEEKDAYS.index(weekday[2]) - today.weekday()) % 7
                if 'proxima semana' in value or 'semana que viene' in value:
                    offset = 7 - today.weekday() + WEEKDAYS.index(weekday[2])
                elif offset == 0 and weekday[1] == 'proximo':
                    offset = 7
                end = today + timedelta(days=offset)
                start = today if re.search(r'\bhasta\b', value) else end
            elif next_delivery is not None and re.search(r'\bhasta\s+(?:la\s+)?(?:proxima|siguiente)\s+entrega\b',value):
                start,end=today,next_delivery
            elif re.search(r'\b(?:proxima semana|esta semana)\b', value):
                start, end = today, today + timedelta(days=6)
            elif re.search(r'\bmanana\b', value):
                start = end = today + timedelta(days=1)
                if re.search(r'\bhasta\b', value):
                    start = today
            elif re.search(r'\bhoy\b', value):
                start = end = today
            else:
                return None
        if start < today or end < start or (end - start).days > 90:
            raise ValueError()
    except (ValueError, OverflowError):
        raise ValueError('Indica fechas desde hoy, en un período de hasta 91 días.') from None
    return start.isoformat(), end.isoformat()
