"""Customer directory shared across restaurants; documents are identifiers, not keys."""
import re
from uuid import uuid4
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from werkzeug.exceptions import BadRequest, Conflict, NotFound
from app.core.extensions import db


def texto_opcional(datos, campo, limite):
    valor = datos.get(campo)
    if valor is not None and not isinstance(valor, str):
        raise BadRequest(f'{campo} debe ser texto')
    valor = valor.strip() if valor else None
    if valor and len(valor) > limite:
        raise BadRequest(f'{campo} excede {limite} caracteres')
    return valor or None


def validar(data):
    if not isinstance(data, dict):
        raise BadRequest('Se requiere un objeto con los datos del cliente')
    result = {}
    for field, maximum in [('nombre',200),('direccion',300),('email',200),('telefono',40),('numero_documento',30)]:
        result[field] = texto_opcional(data, field, maximum)
    if not result['nombre']:
        raise BadRequest('El nombre o razon social es obligatorio')
    persona=data.get('tipo_persona','NATURAL')
    documento=data.get('tipo_documento') or None
    if persona not in ('NATURAL','JURIDICA'):
        raise BadRequest('Tipo de persona invalido')
    if documento not in (None,'DNI','RUC','CE','PASAPORTE'):
        raise BadRequest('Tipo de documento invalido')
    numero=result['numero_documento']
    if numero and not documento:
        raise BadRequest('Indica el tipo de documento')
    if numero:
        pattern={'DNI':r'[0-9]{8}','RUC':r'[0-9]{11}','CE':r'[A-Za-z0-9]{1,20}','PASAPORTE':r'[A-Za-z0-9]{1,30}'}[documento]
        if not re.fullmatch(pattern,numero):
            raise BadRequest('Numero de documento invalido')
    if persona=='JURIDICA' and documento not in (None,'RUC'):
        raise BadRequest('Una persona juridica utiliza RUC')
    result.update(tipo_persona=persona,tipo_documento=documento)
    return result


def _json(row):
    result=dict(row)
    result['id_cliente']=str(result['id_cliente'])
    return result


def perfil_autorizado(perfil, salon=False):
    if type(perfil) is not int:
        return False
    return bool(db.session.execute(select(func.public.clientes_perfil_autorizado(perfil, salon))).scalar())


def directorio_disponible():
    return bool(db.session.execute(select(func.public.clientes_directorio_disponible())).scalar())


def _filas(consulta):
    clientes = consulta.table_valued(
        'id_cliente', 'tipo_persona', 'tipo_documento', 'numero_documento',
        'nombre', 'direccion', 'email', 'telefono',
    )
    return db.session.execute(select(clientes)).mappings()


def buscar(local,q='',limit=25,offset=0):
    q=q.strip()
    if not 1<=limit<=100 or offset<0 or len(q)>200:
        raise BadRequest('Parametros de busqueda invalidos')
    pattern='%'+q.replace('\\','\\\\').replace('%','\\%').replace('_','\\_')+'%'
    rows = _filas(func.public.clientes_buscar(local, q, pattern, limit, offset)).all()
    return [_json(row) for row in rows]


def obtener(local,id_cliente):
    row = _filas(func.public.clientes_obtener(local, str(id_cliente))).first()
    return _json(row) if row else None


def crear(local,data, *, commit=True):
    values=validar(data)
    values.update(id_cliente=str(uuid4()),id_local=local)
    try:
        alta = func.public.clientes_crear(
            values['id_cliente'], local, values['tipo_persona'], values['tipo_documento'],
            values['numero_documento'], values['nombre'], values['direccion'],
            values['email'], values['telefono'],
        )
        db.session.execute(select(alta))
        if commit:
            db.session.commit()
    except IntegrityError as exc:
        if commit:
            db.session.rollback()
        if getattr(exc.orig,'pgcode',None)=='23505':
            raise Conflict('Ya existe un cliente con ese documento en el directorio') from exc
        raise
    values.pop('id_local')
    return values


def actualizar_contacto(local, id_cliente, datos):
    if (not isinstance(datos, dict) or not {'email', 'telefono'}.issubset(datos)
            or set(datos) - {'email', 'telefono', 'direccion'}):
        raise BadRequest('Envia correo y telefono. Puedes dejar cualquiera vacio.')
    email = texto_opcional(datos, 'email', 200)
    telefono = texto_opcional(datos, 'telefono', 40)
    direccion = texto_opcional(datos, 'direccion', 300)
    consulta = func.public.clientes_actualizar_contacto(
        local, str(id_cliente), email, telefono, direccion, 'direccion' in datos,
    ).table_valued('id_cliente', 'email', 'telefono', 'direccion')
    fila = db.session.execute(select(consulta)).mappings().first()
    if fila is None:
        raise NotFound('Cliente no encontrado en el directorio')
    resultado = _json(fila)
    db.session.commit()
    return resultado
