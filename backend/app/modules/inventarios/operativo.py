"""Jornadas persistentes, mix de ventas y conteos físicos sin ajuste de saldo."""
import json
from datetime import date
from decimal import Decimal, InvalidOperation
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import Numeric, bindparam, cast, func, select
from werkzeug.exceptions import BadRequest, Conflict, Forbidden, NotFound
from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.extensions import db
from app.core.stock_local import inventario_operativo_instalado as instalado
from app.core.local_scope import local_actual
from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import registrar_actividad, registrar_cambio

COLUMNAS_CONTEO = (
    'id_ronda', 'id_producto', 'asignado_a', 'teorico', 'contado', 'corregido', 'contado_por',
    'contado_en', 'estado', 'observacion', 'revisado_por', 'revisado_en', 'justificacion',
    'justificado_por', 'justificado_en', 'version',
)
COLUMNAS_CONTEO_PUESTOS = (
    'puesto_asignado', 'puesto_nombre', 'contado_perfil', 'contado_puesto', 'contado_perfil_nombre', 'contado_puesto_nombre'
)


def columnas_conteo():
    if puestos_instalados():
        return COLUMNAS_CONTEO + COLUMNAS_CONTEO_PUESTOS
    return COLUMNAS_CONTEO


operativo_bp = Blueprint('inventario_operativo', __name__)


def contexto(capacidad='operar_tienda'):
    if not perfil_tiene_capacidad(get_jwt().get('id_perfil'), capacidad):
        raise Forbidden('Tu perfil no puede realizar esta operación')
    local = local_actual()
    if not instalado():
        raise Conflict('Ejecuta database/migrations/20260926_jornadas_conteos.sql')
    return local, int(get_jwt_identity()), get_jwt()['id_perfil']


def serial(valor):
    return json.loads(json.dumps(valor, default=lambda v: float(v) if isinstance(v, Decimal) else v.isoformat()))


def filas(consulta, params=None):
    return [dict(r) for r in db.session.execute(consulta, params or {}).mappings()]


def bloqueo(local):
    db.session.execute(select(func.public.inv_operativo_bloqueo(bindparam('clave'))), {'clave': f'inventario-dia:{local}'})


def auditar(accion, identidad, detalle):
    registrar_actividad(int(get_jwt_identity()), 'INVENTARIO_OPERATIVO', accion, identidad, detalle,
                        id_perfil_utilizado=get_jwt()['id_perfil'], id_local=get_jwt()['id_local'])


def rango():
    try:
        desde = date.fromisoformat(request.args.get('desde', ''))
        hasta = date.fromisoformat(request.args.get('hasta', ''))
    except ValueError:
        raise BadRequest('Selecciona fechas válidas')
    if hasta < desde or (hasta-desde).days > 366:
        raise BadRequest('Selecciona un rango de hasta 367 días en orden cronológico')
    return desde, hasta


def datos_json():
    datos=request.get_json(silent=True)
    if not isinstance(datos,dict):raise BadRequest('Envía un objeto con los datos de la operación')
    return datos


def ventas(local, jornada=None, desde=None, hasta=None, horas=None, separar=False):
    return filas(select(func.public.inv_operativo_ventas(bindparam('separar'), bindparam('local'), bindparam('jornada'), bindparam('desde'), bindparam('hasta'), bindparam('todas'), bindparam('horas')).table_valued(
        'id_presentacion', 'nombre', 'hora', 'cantidad', 'total'
    )),
        dict(local=local,jornada=jornada,desde=desde,hasta=hasta,horas=horas or [],todas=not horas,separar=separar))


def reporte(jornada):
    identidad = jornada['id_jornada']
    productos = filas(select(func.public.inv_operativo_reporte_1(bindparam('id')).table_valued(
        'id_producto', 'codigo', 'nombre', 'unidad', 'inicial', 'entradas', 'salidas', 'final'
    )), {'id': identidad})
    motivos = filas(select(func.public.inv_operativo_reporte_2(bindparam('id')).table_valued(
        'id_producto', 'motivo', 'etiqueta', 'entradas', 'salidas'
    )), {'id': identidad})
    for p in productos:
        p['motivos'] = [m for m in motivos if m['id_producto'] == p['id_producto']]
    return serial({'inventario': productos, 'ventas': ventas(jornada['id_local'], jornada=identidad)})


@operativo_bp.get('/dias')
@requiere_permiso('cerrar_dia', 'consultar')
def dias():
    local, _, _ = contexto('gestionar_inventario')
    return jsonify(dias=serial(filas(select(func.public.inv_operativo_dias(bindparam('local')).table_valued(
        'id_jornada', 'fecha', 'abierto_en', 'cerrado_en'
    )), {'local':local})))


@operativo_bp.post('/dias/abrir')
@requiere_permiso('cerrar_dia', 'cerrar')
def abrir():
    local, usuario, _ = contexto('gestionar_inventario')
    try:
        bloqueo(local)
        identidad=db.session.execute(select(func.public.inv_operativo_abrir(bindparam('local'), bindparam('usuario'))),dict(local=local,usuario=usuario)).scalar_one()
        auditar('ABRIR_DIA',identidad,'Abrió o consultó la jornada operativa')
        db.session.commit()
        return jsonify(id_jornada=identidad)
    except Exception:
        db.session.rollback();raise


def jornada_local(local, identidad):
    registros=filas(select(func.public.inv_operativo_jornada_local(bindparam('id'), bindparam('local')).table_valued(
        'id_jornada', 'id_local', 'fecha', 'abierto_en', 'cerrado_en', 'abierto_por',
        'cerrado_por', 'reporte'
    )),dict(id=identidad,local=local))
    if not registros: raise NotFound('Día no encontrado en este local')
    return registros[0]


@operativo_bp.get('/dias/<int:identidad>')
@requiere_permiso('cerrar_dia','consultar')
def detalle_dia(identidad):
    local,_,_=contexto('gestionar_inventario')
    bloqueo(local)
    dia=jornada_local(local,identidad)
    return jsonify(serial({**dia,'reporte':dia['reporte'] if dia['cerrado_en'] else reporte(dia)}))


@operativo_bp.post('/dias/<int:identidad>/cerrar')
@requiere_permiso('cerrar_dia','cerrar')
def cerrar(identidad):
    local,usuario,_=contexto('gestionar_inventario')
    try:
        bloqueo(local)
        dia=jornada_local(local,identidad)
        if dia['cerrado_en']: return jsonify(serial(dia))
        # Impide que aparezca un nuevo envío entre la comprobación y el cierre.
        db.session.execute(select(func.public.inv_operativo_cerrar_1()))
        pendientes=db.session.execute(select(func.public.inv_operativo_cerrar_2(bindparam('local'))),{'local':local}).scalar()
        if pendientes: raise Conflict('Hay mesas con pedidos sin cobrar. Resuélvelas antes de cerrar el día.')
        contenido=reporte(dia)
        db.session.execute(select(func.public.inv_operativo_cerrar_3(bindparam('usuario'), bindparam('reporte'), bindparam('id'))),dict(id=identidad,usuario=usuario,reporte=json.dumps(contenido)))
        auditar('CERRAR_DIA',identidad,f"Cerró el día operativo {dia['fecha']}")
        resultado=jornada_local(local,identidad)
        db.session.commit()
        return jsonify(serial(resultado))
    except Exception:
        db.session.rollback();raise


@operativo_bp.get('/mix')
@requiere_permiso('mix_ventas','consultar')
def mix():
    local,_,_=contexto('gestionar_inventario')
    desde,hasta=rango()
    try: horas=sorted(set(int(h) for h in request.args.getlist('hora')))
    except ValueError: raise BadRequest('Horas inválidas')
    if any(h<0 or h>23 for h in horas): raise BadRequest('Las horas van de 0 a 23')
    resultados=ventas(local,desde=desde,hasta=hasta,horas=horas,separar=request.args.get('separar')=='1')
    return jsonify(serial({'productos':resultados,'total':sum((r['total'] for r in resultados),Decimal(0)),
                          'cantidad':sum((r['cantidad'] for r in resultados),Decimal(0))}))


@operativo_bp.get('/demanda')
@requiere_permiso('mix_ventas', 'consultar')
@requiere_permiso('stock_actual', 'consultar')
def demanda():
    from .demand import report
    from datetime import datetime, timedelta, timezone
    local, _, _ = contexto('gestionar_inventario')
    desde, hasta = rango()
    if not db.session.execute(select(func.public.inv_operativo_demanda())).scalar():
        raise Conflict('Falta instalar el registro de cobros de Salón para analizar demanda')
    if hasta > datetime.now(timezone(timedelta(hours=-5))).date():
        raise BadRequest('El análisis de ventas no admite fechas futuras')
    if request.args.get('detalle') == 'productos':
        from .product_outlook import report as product_report
        return jsonify(product_report(local,desde,hasta))
    return jsonify(report(local, desde, hasta))


@operativo_bp.get('/demanda-global')
@requiere_permiso('promociones', 'consultar')
def demanda_global():
    from .demand_global import report
    from datetime import datetime,timedelta,timezone
    if not perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'administrar_globalmente'):
        raise Forbidden('El análisis global requiere Administrador del sistema')
    if set(request.args)-{'desde','hasta'}:
        raise BadRequest('El análisis global considera todas las tiendas; no admite cambiar el local')
    today=datetime.now(timezone(timedelta(hours=-5))).date()
    try:
        start=date.fromisoformat(request.args.get('desde',(today-timedelta(days=29)).isoformat()))
        end=date.fromisoformat(request.args.get('hasta',today.isoformat()))
    except ValueError:
        raise BadRequest('Indica fechas válidas') from None
    if end<start or end>today or (end-start).days>366:
        raise BadRequest('Selecciona hasta 367 días sin fechas futuras')
    return jsonify(report(start,end))


@operativo_bp.get('/plan-semanal')
@requiere_permiso('mix_ventas', 'consultar')
@requiere_permiso('stock_actual', 'consultar')
def plan_semanal():
    from .weekly import report, validate_days
    local, _, _ = contexto('gestionar_inventario')
    try:
        dias = validate_days(request.args.get("dias", "7"))
    except ValueError as exc:
        raise BadRequest(str(exc))
    try:
        porcentaje = Decimal(request.args.get('porcentaje', '0'))
    except InvalidOperation:
        raise BadRequest('El porcentaje debe estar entre 0 y 1000')
    if not porcentaje.is_finite() or not 0 <= porcentaje <= 1000:
        raise BadRequest('El porcentaje debe estar entre 0 y 1000')
    if not db.session.execute(select(func.public.inv_operativo_plan_semanal())).scalar():
        raise Conflict('Falta instalar el registro de cobros de Salón para analizar demanda')
    return jsonify(report(local, porcentaje=porcentaje, dias=dias))


def equipo(local):
    return filas(select(func.public.inv_operativo_equipo(bindparam('local')).table_valued(
        'id_usuario', 'nombre'
    )),{'local':local})


def puestos_instalados():
    return bool(db.session.execute(select(func.public.inv_operativo_puestos_instalados())).scalar())


def puestos_conteo():
    return filas(select(func.public.inv_operativo_puestos_conteo().table_valued(
        'id_puesto_laboral', 'nombre'
    )))


def puesto_actual(usuario,perfil):
    if not perfil_tiene_capacidad(perfil, 'contar_por_puesto'):return None
    puesto=get_jwt().get('id_puesto_laboral')
    from app.modules.auth.repository import obtener_puesto_usuario
    if type(puesto) is not int or not obtener_puesto_usuario(usuario,puesto):
        raise Forbidden('Selecciona un puesto activo que tengas asignado')
    return puesto


@operativo_bp.get('/asignaciones')
@requiere_permiso('conteo_fisico','configurar')
def asignaciones():
    local,_,_=contexto('asignar_conteos')
    if not puestos_instalados():raise Conflict('Ejecuta database/migrations/20260928_asignacion_conteos_puestos.sql')
    return jsonify(puestos=puestos_conteo(),productos=filas(select(func.public.inv_operativo_asignaciones(bindparam('local')).table_valued(
        'id_producto', 'codigo', 'nombre', 'categoria', 'id_puesto_laboral', 'puesto'
    )),{'local':local}))


@operativo_bp.put('/asignaciones')
@requiere_permiso('conteo_fisico','configurar')
def guardar_asignaciones():
    local,usuario,_=contexto('asignar_conteos')
    if not puestos_instalados():raise Conflict('Ejecuta database/migrations/20260928_asignacion_conteos_puestos.sql')
    d=datos_json();productos=d.get('productos');puesto=d.get('id_puesto_laboral')
    if 'id_puesto_laboral' not in d:raise BadRequest('Indica el puesto de destino o quita la asignación explícitamente')
    if not isinstance(productos,list) or not 1<=len(productos)<=5000 or any(type(p) is not int or p<=0 for p in productos):
        raise BadRequest('Selecciona entre 1 y 5000 productos')
    productos=list(set(productos))
    if puesto is not None and (type(puesto) is not int or puesto not in {p['id_puesto_laboral'] for p in puestos_conteo()}):
        raise BadRequest('Selecciona Cocina, Bartender o Mesero')
    try:
        bloqueo(local)
        if db.session.execute(select(func.public.inv_operativo_guardar_asignaciones_1(bindparam('ids'))),{'ids':productos}).scalar()!=len(productos):
            raise BadRequest('Hay productos que ya no están disponibles; actualiza la lista')
        anterior=filas(select(func.public.inv_operativo_guardar_asignaciones_2(bindparam('local'), bindparam('ids')).table_valued(
        'id_local', 'id_producto', 'id_puesto_laboral', 'actualizado_por', 'actualizado_en'
    )),dict(local=local,ids=productos))
        if puesto is None:
            db.session.execute(select(func.public.inv_operativo_guardar_asignaciones_3(bindparam('local'), bindparam('ids'))),dict(local=local,ids=productos))
        else:
            db.session.execute(select(func.public.inv_operativo_guardar_asignaciones_4(bindparam('local'), bindparam('puesto'), bindparam('usuario'), bindparam('ids'))),dict(local=local,ids=productos,puesto=puesto,usuario=usuario))
        auditar('ASIGNAR_PUESTOS',local,f'Actualizó la asignación por puesto de {len(productos)} productos')
        registrar_cambio(usuario,'INVENTARIO_OPERATIVO','ASIGNAR_PUESTOS','inventario_asignacion_puesto',local,
                         serial(anterior),dict(productos=productos,id_puesto_laboral=puesto),id_local=local)
        db.session.commit();return jsonify(mensaje='Asignación guardada para los próximos conteos')
    except Exception:db.session.rollback();raise


@operativo_bp.get('/conteos')
@requiere_permiso('conteo_fisico','consultar')
def rondas():
    local,usuario,perfil=contexto()
    nuevo=puestos_instalados()
    puesto=puesto_actual(usuario,perfil) if nuevo else None
    registros=filas((select(func.public.inv_operativo_rondas_puestos(bindparam('local'), bindparam('gestor'), bindparam('puesto'), bindparam('usuario')).table_valued(
        'id_ronda', 'id_local', 'nombre', 'creado_por', 'creado_en', 'cerrado_en', 'por_puesto'
    )) if nuevo else select(func.public.inv_operativo_rondas(bindparam('local'), bindparam('gestor'), bindparam('usuario')).table_valued(
        'id_ronda', 'id_local', 'nombre', 'creado_por', 'creado_en', 'cerrado_en', 'por_puesto'
    ))),dict(local=local,usuario=usuario,puesto=puesto,gestor=perfil_tiene_capacidad(perfil, 'gestionar_inventario')))
    return jsonify(rondas=serial(registros),por_puesto=nuevo,equipo=equipo(local) if perfil_tiene_capacidad(perfil, 'asignar_conteos') else [])


@operativo_bp.post('/conteos')
@requiere_permiso('conteo_fisico','crear')
def crear_ronda():
    local,usuario,_=contexto('asignar_conteos')
    nuevo=puestos_instalados()
    datos=datos_json()
    nombre=datos.get('nombre','')
    if not isinstance(nombre,str) or not 1<=len(nombre.strip())<=120: raise BadRequest('Indica un nombre de hasta 120 caracteres')
    try:
        bloqueo(local)
        if nuevo and not db.session.execute(select(func.public.inv_operativo_crear_ronda_1(bindparam('local'))),{'local':local}).scalar():
            raise Conflict('Primero configura los productos en Asignación por puesto')
        if db.session.execute(select(func.public.inv_operativo_crear_ronda_2(bindparam('local'))),{'local':local}).scalar():
            raise Conflict('Ya existe una ronda abierta. Finalízala antes de iniciar otra.')
        identidad=db.session.execute(select(func.public.inv_operativo_crear_ronda_3(bindparam('local'), bindparam('nombre'), bindparam('usuario'))),dict(local=local,nombre=nombre.strip(),usuario=usuario)).scalar_one()
        db.session.execute(select(func.public.inv_operativo_crear_ronda_4(bindparam('id'), bindparam('local'))),dict(id=identidad,local=local))
        if nuevo:
            db.session.execute(select(func.public.inv_operativo_crear_ronda_5(bindparam('id'))),{'id':identidad})
            db.session.execute(select(func.public.inv_operativo_crear_ronda_6(bindparam('id'), bindparam('local'))),dict(id=identidad,local=local))
        auditar('INICIAR_CONTEO',identidad,nombre.strip())
        db.session.commit();return jsonify(id_ronda=identidad),201
    except Exception: db.session.rollback();raise


def ronda_local(local,identidad):
    registros=filas(select(func.public.inv_operativo_ronda_local(bindparam('id'), bindparam('local')).table_valued(
        'id_ronda', 'id_local', 'nombre', 'creado_por', 'creado_en', 'cerrado_en', 'por_puesto'
    )),dict(id=identidad,local=local))
    if not registros: raise NotFound('Conteo no encontrado en este local')
    return registros[0]


@operativo_bp.get('/conteos/<int:identidad>')
@requiere_permiso('conteo_fisico','consultar')
def detalle_conteo(identidad):
    local,usuario,perfil=contexto()
    ronda=ronda_local(local,identidad)
    puesto=puesto_actual(usuario,perfil) if ronda.get('por_puesto') else None
    registros=filas((select(func.public.inv_operativo_detalle_conteo_puestos(bindparam('id'), bindparam('gestor'), bindparam('puesto')).table_valued(
        'id_ronda', 'id_producto', 'asignado_a', 'teorico', 'contado', 'corregido',
        'contado_por', 'contado_en', 'estado', 'observacion', 'revisado_por', 'revisado_en',
        'justificacion', 'justificado_por', 'justificado_en', 'version', 'puesto_asignado',
        'puesto_nombre', 'contado_perfil', 'contado_puesto', 'contado_perfil_nombre',
        'contado_puesto_nombre', 'nombre', 'codigo', 'unidad', 'categoria', 'asignado_nombre',
        'contado_nombre', 'diferencia'
    )) if ronda.get('por_puesto') else select(func.public.inv_operativo_detalle_conteo(bindparam('id'), bindparam('gestor'), bindparam('usuario')).table_valued(
        'id_ronda', 'id_producto', 'asignado_a', 'teorico', 'contado', 'corregido',
        'contado_por', 'contado_en', 'estado', 'observacion', 'revisado_por', 'revisado_en',
        'justificacion', 'justificado_por', 'justificado_en', 'version', 'puesto_asignado',
        'puesto_nombre', 'contado_perfil', 'contado_puesto', 'contado_perfil_nombre',
        'contado_puesto_nombre', 'nombre', 'codigo', 'unidad', 'categoria', 'asignado_nombre',
        'contado_nombre', 'diferencia'
    ))),dict(id=identidad,usuario=usuario,puesto=puesto,gestor=perfil_tiene_capacidad(perfil, 'gestionar_inventario')))
    if perfil_tiene_capacidad(perfil, 'contar_por_puesto'):
        for r in registros:
            for k in ('teorico','diferencia','corregido','justificacion','justificado_por','justificado_en'):r.pop(k,None)
    return jsonify(serial({'ronda':ronda,'productos':registros,'equipo':equipo(local) if perfil_tiene_capacidad(perfil, 'asignar_conteos') else [],
                           'puestos':puestos_conteo() if ronda.get('por_puesto') else []}))


def cantidad(valor):
    try: n=Decimal(str(valor))
    except (InvalidOperation,ValueError): raise BadRequest('Cantidad inválida')
    if not n.is_finite() or n<0 or n>Decimal('999999999.999') or n!=n.quantize(Decimal('.001')):
        raise BadRequest('Ingresa una cantidad no negativa con hasta tres decimales')
    return n


@operativo_bp.put('/conteos/<int:identidad>/productos/<int:producto>')
@requiere_permiso('conteo_fisico','editar')
def editar_conteo(identidad,producto):
    local,usuario,perfil=contexto()
    d=datos_json()
    accion=d.get('accion')
    if not isinstance(accion,str):raise BadRequest('Acción inválida')
    permiso={'asignar':'configurar','revisar':'revisar','justificar':'revisar','contar':'editar'}.get(accion)
    if not permiso: raise BadRequest('Acción inválida')
    if not db.session.execute(select(func.public.auth_permiso_accion(usuario, perfil, 'conteo_fisico', permiso)),{'perfil':perfil}).scalar(): raise Forbidden('No tienes permiso para esta acción')
    try:
        # Serializa revisión/finalización de una ronda; evita corregir después de cerrarla.
        db.session.execute(select(func.public.inv_operativo_editar_conteo_2(bindparam('id'), bindparam('local'))),dict(id=identidad,local=local))
        ronda=ronda_local(local,identidad)
        rows=filas(select(func.public.inv_operativo_editar_conteo_3(bindparam('id'), bindparam('producto')).table_valued(
        'id_ronda', 'id_producto', 'asignado_a', 'teorico', 'contado', 'corregido',
        'contado_por', 'contado_en', 'estado', 'observacion', 'revisado_por', 'revisado_en',
        'justificacion', 'justificado_por', 'justificado_en', 'version', 'puesto_asignado',
        'puesto_nombre', 'contado_perfil', 'contado_puesto', 'contado_perfil_nombre',
        'contado_puesto_nombre'
    )),dict(id=identidad,producto=producto))
        if not rows: raise NotFound('Producto no encontrado en el conteo')
        old=rows[0]
        if type(d.get('version')) is not int or d['version']!=old['version']:raise Conflict('El registro cambió. Actualiza antes de guardar.')
        if ronda['cerrado_en'] and accion!='justificar':raise Conflict('La ronda ya está finalizada')
        valores={}
        if accion=='asignar':
            if not perfil_tiene_capacidad(perfil, 'asignar_conteos'):raise Forbidden('Solo el gerente asigna conteos')
            if old['estado']!='PENDIENTE':raise Conflict('No reasignes un producto que ya tiene un conteo')
            if ronda.get('por_puesto'):
                asignado=d.get('id_puesto_laboral')
                puestos={p['id_puesto_laboral']:p['nombre'] for p in puestos_conteo()}
                if type(asignado) is not int or asignado not in puestos:raise BadRequest('Selecciona un puesto válido')
                valores={'puesto_asignado':asignado,'puesto_nombre':puestos[asignado]}
            else:
                asignado=d.get('id_usuario')
                if asignado is not None and (type(asignado) is not int or asignado not in {u['id_usuario'] for u in equipo(local)}):raise BadRequest('Usuario no disponible en este local')
                valores={'asignado_a':asignado}
        elif accion=='contar':
            puesto=puesto_actual(usuario,perfil) if ronda.get('por_puesto') else None
            if perfil_tiene_capacidad(perfil, 'contar_por_puesto') and (old.get('puesto_asignado')!=puesto if ronda.get('por_puesto') else old['asignado_a']!=usuario):raise Forbidden('Solo puedes contar los productos de tu puesto activo')
            if old['estado']=='REVISADO':raise Conflict('El conteo ya fue revisado')
            if ronda.get('por_puesto') and old['estado']=='HECHO':raise Conflict('Ya se entregó este conteo; un responsable debe revisarlo')
            if perfil_tiene_capacidad(perfil, 'gestionar_inventario') and (old['estado']=='HECHO' or old['contado_por'] not in (None,usuario)):
                raise Conflict('Conserva el conteo original: espera a que esté Hecho y usa Revisar para corregirlo con una observación')
            estado=d.get('estado')
            if estado not in ('EN_PROCESO','HECHO'):raise BadRequest('Selecciona En proceso o Hecho')
            valores={'contado':cantidad(d.get('cantidad')),'contado_por':usuario,'estado':estado}
            if puestos_instalados():
                nombre_perfil=db.session.execute(select(func.public.inv_operativo_editar_conteo_4(bindparam('id'))),{'id':perfil}).scalar()
                nombre_puesto=db.session.execute(select(func.public.inv_operativo_editar_conteo_5(bindparam('id'))),{'id':puesto}).scalar() if puesto else None
                valores.update(contado_perfil=perfil,contado_puesto=puesto,contado_perfil_nombre=nombre_perfil,contado_puesto_nombre=nombre_puesto)
        elif accion=='revisar':
            if not perfil_tiene_capacidad(perfil, 'gestionar_inventario'):raise Forbidden('Solo gerente o supervisor revisa')
            if old['estado'] not in ('HECHO','REVISADO'):raise Conflict('El miembro debe marcar el conteo como Hecho')
            observacion=d.get('observacion','')
            if not isinstance(observacion,str) or len(observacion)>2000:raise BadRequest('Observación inválida')
            nuevo=cantidad(d.get('cantidad'))
            if nuevo!=old['contado'] and not observacion.strip():raise BadRequest('Indica la observación de la corrección, por ejemplo: mal conteo')
            valores={'corregido':nuevo,'estado':'REVISADO','observacion':observacion.strip(),'revisado_por':usuario,
                     'justificacion':'','justificado_por':None,'justificado_en':None}
        else:
            if not perfil_tiene_capacidad(perfil, 'gestionar_inventario') or old['estado']!='REVISADO':raise Forbidden('Primero debe estar revisado por un responsable')
            justificacion=d.get('justificacion','')
            if not isinstance(justificacion,str) or not 1<=len(justificacion.strip())<=2000:raise BadRequest('Escribe una justificación de hasta 2000 caracteres')
            valores={'justificacion':justificacion.strip(),'justificado_por':usuario}
        nuevo=filas(select(func.public.inv_operativo_actualizar_conteo(
            bindparam('id'), bindparam('producto'), bindparam('cambios'), bindparam('accion')
        ).table_valued(*columnas_conteo())),
                    dict(cambios=json.dumps(valores, default=str), accion=accion, id=identidad, producto=producto))[0]
        db.session.execute(select(func.public.inv_operativo_editar_conteo_7(bindparam('id'), bindparam('producto'), bindparam('usuario'), bindparam('accion'), bindparam('anterior'), bindparam('nuevo'))),
            dict(id=identidad,producto=producto,usuario=usuario,accion=accion,anterior=json.dumps(serial(old)),nuevo=json.dumps(serial(nuevo))))
        auditar(accion.upper(),identidad,f'Conteo {identidad}, producto {producto}')
        db.session.commit();return jsonify(mensaje='Guardado. El stock teórico no se modifica.')
    except Exception:db.session.rollback();raise


@operativo_bp.post('/conteos/<int:identidad>/finalizar')
@requiere_permiso('conteo_fisico','cerrar')
def finalizar_conteo(identidad):
    local,usuario,_=contexto('gestionar_inventario')
    datos=datos_json()
    try:
        db.session.execute(select(func.public.inv_operativo_finalizar_conteo_1(bindparam('id'), bindparam('local'))),dict(id=identidad,local=local))
        ronda=ronda_local(local,identidad)
        if ronda['cerrado_en']:return jsonify(mensaje='La ronda ya está finalizada')
        if datos.get('aceptar_entregados') is True:
            registros=filas(select(func.public.inv_operativo_finalizar_conteo_2(bindparam('id')).table_valued(
        'id_ronda', 'id_producto', 'asignado_a', 'teorico', 'contado', 'corregido',
        'contado_por', 'contado_en', 'estado', 'observacion', 'revisado_por', 'revisado_en',
        'justificacion', 'justificado_por', 'justificado_en', 'version', 'puesto_asignado',
        'puesto_nombre', 'contado_perfil', 'contado_puesto', 'contado_perfil_nombre',
        'contado_puesto_nombre'
    )),{'id':identidad})
            versiones=datos.get('versiones')
            esperadas={str(r['id_producto']):r['version'] for r in registros}
            if not isinstance(versiones,dict) or versiones!=esperadas:
                raise Conflict('El conteo cambió. Actualiza y revisa los cambios antes de cerrar.')
            if not registros or any(r['estado'] not in ('HECHO','REVISADO') for r in registros):
                raise Conflict('Todavía hay productos pendientes de entregar por el equipo')
            cambios=datos.get('correcciones',{})
            if not isinstance(cambios,dict) or any(k not in esperadas for k in cambios):
                raise BadRequest('Correcciones inválidas para esta ronda')
            if cambios and not db.session.execute(select(func.public.inv_operativo_finalizar_conteo_3(bindparam('perfil'))),{'perfil':get_jwt()['id_perfil']}).scalar():
                raise Forbidden('No tienes permiso para corregir esta revisión')
            validados={}
            for clave,cambio in cambios.items():
                if not isinstance(cambio,dict) or set(cambio)!={'cantidad','observacion'}:
                    raise BadRequest('Solo puedes corregir cantidad y observación')
                nota=cambio['observacion']
                if not isinstance(nota,str) or len(nota)>2000:raise BadRequest('Observación inválida')
                validados[clave]=(cantidad(cambio['cantidad']),nota.strip())
            for old in registros:
                cambio=validados.get(str(old['id_producto']))
                if old['estado']=='REVISADO' and cambio is None:continue
                valor,nota=cambio if cambio is not None else (old['contado'],old['observacion'])
                nuevo=filas(select(func.public.inv_operativo_finalizar_conteo_4(cast(bindparam('valor'), Numeric), bindparam('nota'), bindparam('usuario'), bindparam('id'), bindparam('producto')).table_valued(*columnas_conteo())),
                    dict(id=identidad,producto=old['id_producto'],usuario=usuario,valor=valor,nota=nota))[0]
                db.session.execute(select(func.public.inv_operativo_finalizar_conteo_5(bindparam('id'), bindparam('producto'), bindparam('usuario'), bindparam('anterior'), bindparam('nuevo'))),
                    dict(id=identidad,producto=old['id_producto'],usuario=usuario,
                         anterior=json.dumps(serial(old)),nuevo=json.dumps(serial(nuevo))))
        if db.session.execute(select(func.public.inv_operativo_finalizar_conteo_6(bindparam('id'))),{'id':identidad}).scalar():
            raise Conflict('Revisa todos los productos antes de finalizar')
        db.session.execute(select(func.public.inv_operativo_finalizar_conteo_7(bindparam('id'))),{'id':identidad})
        auditar('FINALIZAR_CONTEO',identidad,'Finalizó la revisión del conteo físico sin ajustar stock')
        db.session.commit();return jsonify(mensaje='Conteo finalizado')
    except Exception:db.session.rollback();raise


@operativo_bp.get('/diferencias')
@requiere_permiso('conteo_fisico','revisar')
def diferencias():
    local,_,_=contexto('gestionar_inventario');desde,hasta=rango()
    try:top=int(request.args.get('top','10'))
    except ValueError:raise BadRequest('Top inválido')
    if top not in (5,10,15,20):raise BadRequest('Elige top 5, 10, 15 o 20')
    datos=filas(select(func.public.inv_operativo_diferencias(bindparam('local'), bindparam('desde'), bindparam('hasta'), bindparam('top')).table_valued(
        'id_ronda', 'id_producto', 'asignado_a', 'teorico', 'contado', 'corregido',
        'contado_por', 'contado_en', 'estado', 'observacion', 'revisado_por', 'revisado_en',
        'justificacion', 'justificado_por', 'justificado_en', 'version', 'puesto_asignado',
        'puesto_nombre', 'contado_perfil', 'contado_puesto', 'contado_perfil_nombre',
        'contado_puesto_nombre', 'nombre', 'unidad', 'ronda', 'creado_en', 'diferencia'
    )),
        dict(local=local,desde=desde,hasta=hasta,top=top))
    return jsonify(productos=serial(datos))


@operativo_bp.get('/conteos/<int:identidad>/historial')
@requiere_permiso('conteo_fisico','revisar')
def historial(identidad):
    local,_,_=contexto('gestionar_inventario');ronda_local(local,identidad)
    return jsonify(historial=serial(filas(select(func.public.inv_operativo_historial(bindparam('id')).table_valued(
        'id_historial', 'id_ronda', 'id_producto', 'id_usuario', 'accion', 'anterior', 'nuevo',
        'creado_en', 'usuario', 'producto'
    )),{'id':identidad})))
