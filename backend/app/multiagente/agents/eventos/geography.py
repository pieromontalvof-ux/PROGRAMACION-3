"""Independent OSM geocoding and approximate straight-line distance, never model coordinates."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
import threading
import time
from contextlib import contextmanager
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from flask import current_app, has_app_context
from app.multiagente.api.tools import normalized

_lock=threading.Lock()


@contextmanager
def provider_gate():
    root=Path(current_app.instance_path)/'event_geocoding'
    root.mkdir(parents=True,exist_ok=True)
    with (root/'provider.lock').open('a+b') as file:
        if file.seek(0,2)==0:
            file.write(b'0')
            file.flush()
        deadline=time.monotonic()+6
        while True:
            try:
                file.seek(0)
                if os.name=='nt':
                    import msvcrt
                    msvcrt.locking(file.fileno(),msvcrt.LK_NBLCK,1)
                else:
                    import fcntl
                    fcntl.flock(file.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic()>deadline:
                    raise TimeoutError('Geocoder ocupado')
                time.sleep(.05)
        try:
            stamp=root/'last_request.txt'
            try:
                pause=1.05-(time.time()-float(stamp.read_text()))
            except (OSError,ValueError):
                pause=0
            if pause>0:
                time.sleep(min(pause,1.05))
            stamp.write_text(str(time.time()))
            yield
        finally:
            file.seek(0)
            if os.name=='nt':
                msvcrt.locking(file.fileno(),msvcrt.LK_UNLCK,1)
            else:
                fcntl.flock(file.fileno(),fcntl.LOCK_UN)


def radius():
    try:
        value=int(os.getenv('EVENT_NEARBY_RADIUS_M','1000'))
        return value if 100<=value<=10000 else 1000
    except ValueError:
        return 1000


def distance(a,b):
    lat1,lat2=map(math.radians,(a[0],b[0]))
    dlat=lat2-lat1
    dlon=math.radians(b[1]-a[1])
    value=math.sin(dlat/2)**2+math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return 6371000*2*math.asin(min(1,math.sqrt(value)))


def words(value):
    return set(re.findall(r'\w{3,}',normalized(value)))-{'avenida','calle','jiron','lima','peru','del','los','las','hotel'}


def select(results,name,address,area=False):
    matches=[]
    no_number=bool(re.search(r'\bs\s*/\s*n\b|sin numero',normalized(address)))
    number=None if no_number else re.search(r'\b\d{1,5}\s*$',address.split(',')[0].strip())
    for row in results if isinstance(results,list) else []:
        try:
            details=row.get('address') or {}
            kind=row.get('addresstype',row.get('type',''))
            if details.get('country_code')!='pe' or kind in ('city','state','country','county','municipality','suburb','quarter','road','residential','neighbourhood','administrative'):
                continue
            lat,lon=float(row['lat']),float(row['lon'])
            if not (-19<lat<1 and -82<lon<-68):
                continue
            number_found=details.get('house_number')
            if number and number_found and number[0].strip()!=str(number_found):
                continue
            named=bool(words(name)) and words(name)<=words(row.get('name',''))
            road=details.get('road') or details.get('pedestrian') or ''
            street_match=bool(words(road)) and words(road)<=words(address)
            numbered=bool(number and number_found and number[0].strip()==str(number_found) and street_match)
            if not (numbered or (named and (street_match or not number))):
                continue
            osm_type=row.get('osm_type')
            osm_id=int(row['osm_id'])
            if osm_type not in ('node','way','relation') or osm_id<=0:
                continue
            uncertainty=20
            if area or row.get('boundingbox'):
                bounds=list(map(float,row['boundingbox']))
                if len(bounds)!=4 or not all(math.isfinite(v) for v in bounds):
                    continue
                uncertainty=max(20,max(distance((lat,lon),(a,b)) for a in bounds[:2] for b in bounds[2:]))
                if uncertainty>1000:
                    continue
            matches.append({'lat':lat,'lon':lon,'incertidumbre_m':math.ceil(uncertainty),'precision':'area del recinto' if area else 'punto del recinto','url':f'https://www.openstreetmap.org/{osm_type}/{osm_id}',
                            'nombre':row.get('display_name') or row.get('name'),'consulta':name+', '+address})
        except (ValueError,TypeError,KeyError,AttributeError):
            continue
    if not matches or any(distance((matches[0]['lat'],matches[0]['lon']),(r['lat'],r['lon']))>100 for r in matches[1:]):
        return None
    return matches[0]


def locate(name,address):
    if not has_app_context() or current_app.testing or not address:
        return None
    if re.search(r'no (?:publicad|corroborad|verificad)|por confirmar|sin direccion',normalized(address)):
        return None
    query=', '.join(v for v in (name,address,'Perú') if v)
    base=os.getenv('EVENT_GEOCODER_URL','https://nominatim.openstreetmap.org/search')
    key=hashlib.sha256(('v4:'+base+normalized(query)).encode()).hexdigest()
    target=Path(current_app.instance_path)/'event_geocoding'/(key+'.json')
    with _lock:
        try:
            saved=json.loads(target.read_text(encoding='utf-8'))
            if 0<=time.time()-saved['created']<(2592000 if saved['point'] else 600):
                return saved['point']
        except (OSError,ValueError,KeyError,TypeError):
            pass
        point=None
        city='Lima' if 'lima' in normalized(address) else ''
        queries=[(query,name,False)]
        if city and words(name):
            queries.append((name+', '+city+', Perú',name,False))
            parent=re.search(r'^(?:anfiteatro|explanada|auditorio)\s+(?:del|de la)\s+(parque\b.+)',name,re.I)
            if parent:
                queries.append((parent[1]+', '+city+', Perú',parent[1],True))
        for attempt,match_name,area in queries:
            params=urlencode({'q':attempt,'format':'jsonv2','addressdetails':1,'countrycodes':'pe','limit':3})
            try:
                request=Request(base+'?'+params,headers={'User-Agent':'BarbaritoLocal/1.0 (bar event proximity lookup)','Accept':'application/json'})
                with provider_gate(), urlopen(request,timeout=5) as response:
                    data=json.loads(response.read(250000))
                point=select(data,match_name,address,area=area)
            except (OSError,ValueError):
                return None
            if point:
                break
        temporary=None
        try:
            target.parent.mkdir(parents=True,exist_ok=True)
            with tempfile.NamedTemporaryFile(mode='w',dir=target.parent,encoding='utf-8',delete=False) as file:
                temporary=file.name
                json.dump({'created':time.time(),'point':point},file,ensure_ascii=False)
            os.replace(temporary,target)
        except OSError:
            pass
        finally:
            if temporary and os.path.exists(temporary):
                os.unlink(temporary)
        return point


def check(location,candidates):
    from .research import identity
    origin=locate(str(location.get('nombre') or ''),str(location.get('direccion') or ''))
    result={'origin':origin,'radius_m':radius(),'venues':{}}
    if not origin:
        return result
    deadline=time.monotonic()+30
    known={}
    for row in candidates[:30]:
        if not isinstance(row,dict):
            continue
        name,address=str(row.get('recinto') or ''),str(row.get('direccion') or '')
        key=(normalized(name),normalized(address))
        if key not in known:
            if len(known)>=16 or time.monotonic()>deadline:
                break
            known[key]=locate(name,address)
        point=known[key]
        if not point:
            result['venues'][identity(row)]={'estado':'PENDIENTE','motivo':'Ubicación del recinto no resuelta o ambigua.'}
            continue
        meters=distance((origin['lat'],origin['lon']),(point['lat'],point['lon']))
        uncertainty=origin.get('incertidumbre_m',0)+point.get('incertidumbre_m',0)
        state='DENTRO' if meters+uncertainty<=result['radius_m'] else ('FUERA' if meters-uncertainty>result['radius_m'] else 'PENDIENTE')
        result['venues'][identity(row)]={'estado':state,'incertidumbre_m':uncertainty,'precision':point.get('precision'),
            'distancia_m':round(meters),'url':point['url'],'lat':point['lat'],'lon':point['lon']}
    return result
