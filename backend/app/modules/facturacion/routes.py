"""Store-scoped status and private document downloads; no upstream token exposed."""
import hashlib
from pathlib import Path
from flask import Blueprint, jsonify, request, send_file
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict, NotFound
from app.core.extensions import db
from app.modules.clientes.routes import acceso
from .service import enqueue_source
from .repository import installed
from .worker import storage_root

fact_api_bp=Blueprint('fact_api',__name__)
salon_fact_api_bp=Blueprint('salon_fact_api',__name__)


def validate_origin(origin):
    if origin not in ('VENTA','COMPRA'):raise NotFound('Origen no disponible.')


@fact_api_bp.get('/<origin>/<int:source>')
@acceso
def status(local,origin,source):
    validate_origin(origin)
    if not installed():return jsonify(disponible=False,operaciones=[])
    rows=db.session.execute(text('''SELECT o.id_operacion,o.version,o.estado,o.intentos,o.ultimo_error,o.obsoleto,
        o.creado_en,o.actualizado_en,d.id_documento,d.numero,d.estado AS estado_documento,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id_archivo,'formato',a.formato))
            FROM fact_api_archivo a WHERE a.id_documento=d.id_documento),'[]'::jsonb) AS archivos
        FROM fact_api_operacion o LEFT JOIN fact_api_documento d USING(id_operacion)
        WHERE o.id_local=:local AND o.origen=:origin AND o.id_origen=:source ORDER BY o.version DESC'''),
        {'local':local,'origin':origin,'source':source}).mappings().all()
    configured=db.session.execute(text('SELECT activo FROM fact_api_config WHERE id_local=:local'),{'local':local}).scalar()
    attachments=[]
    if origin=='COMPRA':
        attachments=[dict(r) for r in db.session.execute(text('''SELECT id_adjunto,formato,creado_en FROM fact_api_adjunto
            WHERE id_local=:local AND id_factura_recepcion=:source ORDER BY creado_en'''),{'local':local,'source':source}).mappings()]
    return jsonify(disponible=bool(configured),modo='DEMO',operaciones=[dict(r) for r in rows],originales=attachments)


@fact_api_bp.post('/COMPRA/<int:source>/originales')
@acceso
def upload_original(local,source):
    request.max_content_length=6*1024*1024
    from .attachments import save_original
    available=db.session.execute(text('''SELECT 1 FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
        WHERE f.id_factura_recepcion=:id AND o.id_local=:local'''),{'id':source,'local':local}).scalar()
    if not available:raise NotFound('Factura no encontrada en este local.')
    file=request.files.get('archivo')
    kind=request.form.get('formato','')
    if not file:raise BadRequest('Adjunta el original del proveedor.')
    try:
        identity=save_original(local,source,file.read(5*1024*1024+1),kind)
        db.session.commit()
        return jsonify(id_adjunto=identity),201
    except ValueError as error:
        db.session.rollback();raise BadRequest(str(error)) from None
    except Exception:
        db.session.rollback();raise


@fact_api_bp.get('/originales/<uuid:identity>')
@acceso
def download_original(local,identity):
    row=db.session.execute(text('SELECT * FROM fact_api_adjunto WHERE id_adjunto=:id AND id_local=:local'),
                           {'id':str(identity),'local':local}).mappings().first()
    if not row:raise NotFound('Original no encontrado en este local.')
    path=(storage_root()/row['ruta']).resolve()
    if not path.is_relative_to(storage_root()) or not path.is_file():raise NotFound('Original no disponible.')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:raise Conflict('Integridad del original no válida.')
    return send_file(path,as_attachment=True,download_name=f"original_{identity}.{row['formato'].lower()}",
                     mimetype='application/pdf' if row['formato']=='PDF' else 'application/xml')


@fact_api_bp.post('/<origin>/<int:source>')
@acceso
def enqueue(local,origin,source):
    validate_origin(origin)
    try:
        identity=enqueue_source(origin,source,local)
        if not identity:raise Conflict('Sin configuración o detalle comercial para generar documento.')
        db.session.commit()
        return jsonify(id_operacion=identity,modo='DEMO'),202
    except ValueError as error:
        db.session.rollback();raise BadRequest(str(error)) from None
    except Exception:
        db.session.rollback();raise


@fact_api_bp.post('/operaciones/<uuid:identity>/reintentar')
@acceso
def retry(local,identity):
    row=db.session.execute(text('''UPDATE fact_api_operacion SET estado='PENDIENTE',max_intentos=intentos+6,
        disponible_en=now(),lease_token=NULL,lease_hasta=NULL,actualizado_en=now()
        WHERE id_operacion=:id AND id_local=:local AND NOT obsoleto AND estado IN ('REVISION','BLOQUEADO','REINTENTO','RECHAZADO')
        RETURNING id_operacion'''),{'id':str(identity),'local':local}).scalar()
    # Keep monotonic attempt numbers; never delete historical attempts.
    if row:
        db.session.execute(text('''UPDATE fact_api_operacion SET intentos=(SELECT COALESCE(max(numero),0)
            FROM fact_api_intento WHERE id_operacion=:id) WHERE id_operacion=:id'''),{'id':str(identity)})
    db.session.commit()
    if not row:raise Conflict('Operación no disponible para reintentar en este local.')
    return jsonify(id_operacion=str(row)),202


@fact_api_bp.get('/archivos/<uuid:identity>')
@acceso
def download(local,identity):
    row=db.session.execute(text('''SELECT a.* FROM fact_api_archivo a JOIN fact_api_documento d USING(id_documento)
        WHERE a.id_archivo=:id AND d.id_local=:local'''),{'id':str(identity),'local':local}).mappings().first()
    if not row:raise NotFound('Archivo no encontrado en este local.')
    path=(storage_root()/row['ruta']).resolve()
    if not path.is_relative_to(storage_root()) or not path.is_file():raise NotFound('Archivo no disponible.')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:
        raise Conflict('La integridad del archivo no coincide. Revisa el respaldo.')
    response=send_file(path,mimetype='application/pdf',as_attachment=True,download_name=f"{row['id_documento']}_{row['formato']}.pdf")
    response.headers['Cache-Control']='private, no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    return response


@fact_api_bp.get('/metricas')
@acceso
def metrics(local):
    row=db.session.execute(text('''SELECT count(*) AS operaciones,
        count(*) FILTER(WHERE estado='COMPLETADO') AS completadas,
        count(*) FILTER(WHERE estado IN ('PENDIENTE','PROCESANDO','REINTENTO')) AS pendientes,
        count(*) FILTER(WHERE estado IN ('REVISION','BLOQUEADO','RECHAZADO')) AS requieren_revision,
        extract(epoch FROM now()-min(creado_en) FILTER(WHERE estado IN ('PENDIENTE','REINTENTO'))) AS espera_max_segundos
        FROM fact_api_operacion WHERE id_local=:local'''),{'local':local}).mappings().one()
    attempts=db.session.execute(text('''SELECT count(*) AS intentos,
        count(*) FILTER(WHERE http_status>=400) AS errores,
        percentile_cont(.95) WITHIN GROUP(ORDER BY duracion_ms) AS p95_ms
        FROM fact_api_intento i JOIN fact_api_operacion o USING(id_operacion)
        WHERE o.id_local=:local AND i.inicio>now()-interval '24 hours' '''),{'local':local}).mappings().one()
    from flask_jwt_extended import get_jwt
    scaling=None
    if get_jwt().get('id_perfil')==1 and db.session.execute(text("SELECT to_regclass('public.fact_api_escalado') IS NOT NULL")).scalar() is True:
        state=db.session.execute(text('SELECT * FROM fact_api_escalado WHERE id=1')).mappings().first()
        scaling=dict(state) if state else None
    return jsonify(**dict(row),ultimas_24_horas=dict(attempts),escalado=scaling)


for rule,func,methods in [('/<origin>/<int:source>',status,['GET']),('/<origin>/<int:source>',enqueue,['POST']),
    ('/archivos/<uuid:identity>',download,['GET']),('/metricas',metrics,['GET']),
    ('/operaciones/<uuid:identity>/reintentar',retry,['POST'])]:
    salon_fact_api_bp.add_url_rule('/fact-api'+rule,view_func=func,methods=methods)


@fact_api_bp.after_request
@salon_fact_api_bp.after_request
def private_response(response):
    response.headers['Cache-Control']='private, no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    return response
