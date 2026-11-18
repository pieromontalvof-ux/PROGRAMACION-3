"""Map-based venue hints for targeted event research, not evidence of an event."""
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from flask import current_app, has_app_context
from . import geography


def parse(elements, origin, radius):
    rows={}
    for item in elements[:250]:
        try:
            tags=item.get('tags') or {}
            name=tags.get('name')
            point=item.get('center') or item
            lat,lon=float(point['lat']),float(point['lon'])
            if not isinstance(name,str) or not name.strip():
                continue
            meters=geography.distance((origin['lat'],origin['lon']),(lat,lon))
            if not math.isfinite(meters) or meters>radius or item['type'] not in ('node','way','relation'):
                continue
            kind=tags.get('amenity') or tags.get('leisure') or tags.get('tourism')
            if kind not in ('theatre','events_venue','conference_centre','arts_centre','museum','gallery','park','stadium','hotel'):
                continue
            rows[(name.casefold(),kind)]={'nombre':name[:160],'tipo':kind,'distancia_aprox_m':round(meters),
                'direccion':' '.join(str(tags.get(k) or '') for k in ('addr:street','addr:housenumber')).strip(),
                'mapa':f"https://www.openstreetmap.org/{item['type']}/{int(item['id'])}"}
        except (KeyError,TypeError,ValueError):
            continue
    ordered=sorted(rows.values(),key=lambda r:r['distancia_aprox_m'])
    # Preserve variety so hotels do not crowd out parks and concert venues.
    selected=[]
    for kind in ('hotel','park','theatre','museum','events_venue','conference_centre','stadium','arts_centre','gallery'):
        row=next((r for r in ordered if r['tipo']==kind),None)
        if row:
            selected.append(row)
    selected.extend(r for r in ordered if r not in selected)
    return selected[:12]


def query_map(query):
    primary=os.getenv('EVENT_VENUES_URL','https://overpass-api.de/api/interpreter')
    endpoints=list(dict.fromkeys((primary,'https://overpass.kumi.systems/api/interpreter')))
    for url in endpoints:
        request=Request(url,data=urlencode({'data':query}).encode(),headers={'User-Agent':'BarbaritoLocal/1.0 (nearby venue discovery)'})
        try:
            with geography.provider_gate(), urlopen(request,timeout=10) as response:
                data=json.loads(response.read(500000))
            if isinstance(data.get('elements'),list) and not data.get('remark'):
                return data['elements']
        except (OSError,ValueError,TypeError,AttributeError):
            continue
    return []


def venues(location):
    if not has_app_context() or current_app.testing or not current_app.config.get('SQLALCHEMY_DATABASE_URI'):
        return []
    origin=geography.locate(str(location.get('nombre') or ''),str(location.get('direccion') or ''))
    if not origin:
        return []
    radius=geography.radius()
    key=hashlib.sha256(json.dumps(['v2-culture',origin['lat'],origin['lon'],radius]).encode()).hexdigest()
    target=Path(current_app.instance_path)/'event_venues'/(key+'.json')
    try:
        saved=json.loads(target.read_text(encoding='utf-8'))
        if 0<=time.time()-saved['created']<86400:
            return saved['venues']
    except (OSError,ValueError,KeyError,TypeError):
        pass
    around=f'(around:{radius},{origin["lat"]},{origin["lon"]})'
    query=('[out:json][timeout:8];('
           f'nwr{around}[amenity~"^(theatre|events_venue|conference_centre|arts_centre)$"][name];'
           f'nwr{around}[leisure~"^(park|stadium)$"][name];'
           f'nwr{around}[tourism~"^(hotel|museum|gallery)$"][name];);out center tags;')
    rows=parse(query_map(query),origin,radius)
    if not rows:
        # Known map results remain useful if the nearby-map service is temporarily unavailable.
        for cached in list((Path(current_app.instance_path)/'event_geocoding').glob('*.json'))[:200]:
            try:
                point=json.loads(cached.read_text(encoding='utf-8')).get('point')
                if point and geography.distance((origin['lat'],origin['lon']),(point['lat'],point['lon']))<=radius:
                    name=str(point['nombre']).split(',')[0]
                    if not any(row['nombre']==name for row in rows):
                        rows.append({'nombre':name,'mapa':point['url'],'tipo':'recinto previamente ubicado'})
            except (OSError,ValueError,KeyError,TypeError):
                pass
        return rows[:12]
    temporary=None
    try:
        target.parent.mkdir(parents=True,exist_ok=True)
        with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=target.parent,delete=False) as file:
            temporary=file.name
            json.dump({'created':time.time(),'venues':rows},file,ensure_ascii=False)
        os.replace(temporary,target)
    except OSError:
        pass
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
    return rows
