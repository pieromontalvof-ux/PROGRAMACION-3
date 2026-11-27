"""Original supplier files, never interpreted as fiscal acceptance."""
import hashlib
from uuid import uuid4
from xml.etree import ElementTree
from sqlalchemy import Uuid, bindparam, cast, func, select
from app.core.extensions import db
from .worker import storage_root


def validate_file(data, kind):
    if not data or len(data)>5*1024*1024:
        raise ValueError('El archivo debe tener como máximo 5 MB.')
    if kind=='PDF' and data.startswith(b'%PDF-'):
        return 'application/pdf'
    if kind=='XML':
        try:
            value=data.decode('utf-8-sig')
            if '<!DOCTYPE' in value.upper() or '<!ENTITY' in value.upper() or '\x00' in value:
                raise ValueError('XML con entidades no permitido.')
            ElementTree.fromstring(value)
        except (ElementTree.ParseError,UnicodeDecodeError):
            raise ValueError('XML no válido.') from None
        return 'application/xml'
    raise ValueError('Selecciona un PDF o XML válido, sin entidades externas.')


def save_original(local,source,data,kind):
    validate_file(data,kind)
    digest=hashlib.sha256(data).hexdigest()
    identity=str(uuid4())
    relative=f'{local}/compra/originales/{source}/{identity}.{kind.lower()}'
    path=storage_root()/relative
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(data)
    result=db.session.execute(select(func.public.facturacion_guardar_adjunto(cast(bindparam('id'), Uuid), bindparam('local'), bindparam('source'), bindparam('kind'), bindparam('path'), bindparam('hash'), bindparam('size'))),{'id':identity,'local':local,'source':source,'kind':kind,
                                 'path':relative,'hash':digest,'size':len(data)}).scalar_one()
    if str(result)!=identity:path.unlink(missing_ok=True)
    return str(result)
