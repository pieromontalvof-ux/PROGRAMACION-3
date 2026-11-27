BEGIN;

CREATE OR REPLACE FUNCTION public.facturacion_instalado()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.fact_api_operacion') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.facturacion_bloquear_fuente(p_key text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock(hashtext(p_key))
$$;

CREATE OR REPLACE FUNCTION public.facturacion_operacion_previa(p_origin text, p_source bigint)
RETURNS TABLE (id_operacion uuid, id_local integer, origen text, id_origen bigint, version integer, payload jsonb, payload_hash character, estado text, intentos integer, disponible_en timestamp with time zone, lease_hasta timestamp with time zone, lease_token uuid, ultimo_http integer, ultimo_error text, creado_en timestamp with time zone, actualizado_en timestamp with time zone, max_intentos integer, obsoleto boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT o.id_operacion, o.id_local, o.origen, o.id_origen, o.version, o.payload, o.payload_hash, o.estado,
    o.intentos, o.disponible_en, o.lease_hasta, o.lease_token, o.ultimo_http, o.ultimo_error, o.creado_en,
    o.actualizado_en, o.max_intentos, o.obsoleto
FROM fact_api_operacion o
        WHERE origen=p_origin AND id_origen=p_source ORDER BY version DESC LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.facturacion_obsoletar_fuente(p_origin text, p_source bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_operacion SET obsoleto=true,
        estado=CASE WHEN estado='COMPLETADO' THEN estado ELSE 'BLOQUEADO' END,
        lease_token=NULL,lease_hasta=NULL,actualizado_en=now(),
        ultimo_error='Existe una versión más reciente de la fuente'
        WHERE origen=p_origin AND id_origen=p_source
$$;

CREATE OR REPLACE FUNCTION public.facturacion_cerrar_intentos_fuente(p_origin text, p_source bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_intento i SET fin=now(),resultado='FUENTE_MODIFICADA'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.origen=p_origin AND o.id_origen=p_source AND o.obsoleto
$$;

CREATE OR REPLACE FUNCTION public.facturacion_encolar(p_id uuid, p_local integer, p_origin text, p_source bigint, p_version integer, p_payload text, p_hash text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO fact_api_operacion
        (id_operacion,id_local,origen,id_origen,version,payload,payload_hash)
        VALUES(p_id,p_local,p_origin,p_source,p_version,CAST(p_payload AS jsonb),p_hash)
$$;

CREATE OR REPLACE FUNCTION public.facturacion_reclamar(p_token text)
RETURNS TABLE (id_operacion uuid, id_local integer, origen text, id_origen bigint, version integer, payload jsonb, payload_hash character, estado text, intentos integer, disponible_en timestamp with time zone, lease_hasta timestamp with time zone, lease_token uuid, ultimo_http integer, ultimo_error text, creado_en timestamp with time zone, actualizado_en timestamp with time zone, max_intentos integer, obsoleto boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
WITH job AS (
        SELECT id_operacion FROM fact_api_operacion
        WHERE NOT obsoleto AND intentos<max_intentos AND ((estado IN ('PENDIENTE','REINTENTO') AND disponible_en<=now())
          OR (estado='PROCESANDO' AND lease_hasta<now()))
          AND NOT EXISTS(SELECT 1 FROM fact_api_circuito WHERE abierto_hasta>now())
        ORDER BY creado_en FOR UPDATE SKIP LOCKED LIMIT 1
    ) UPDATE fact_api_operacion o SET estado='PROCESANDO',intentos=intentos+1,
        lease_hasta=now()+interval '3 minutes',lease_token=CAST(p_token AS uuid),actualizado_en=now()
        FROM job WHERE o.id_operacion=job.id_operacion RETURNING o.id_operacion, o.id_local, o.origen, o.id_origen, o.version, o.payload, o.payload_hash, o.estado,
    o.intentos, o.disponible_en, o.lease_hasta, o.lease_token, o.ultimo_http, o.ultimo_error, o.creado_en,
    o.actualizado_en, o.max_intentos, o.obsoleto
$$;

CREATE OR REPLACE FUNCTION public.facturacion_revisar_agotadas()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_operacion SET estado='REVISION',lease_token=NULL,
        ultimo_error='Intentos agotados; conciliar con el mismo identificador',actualizado_en=now()
        WHERE estado='PROCESANDO' AND lease_hasta<now() AND intentos>=max_intentos
$$;

CREATE OR REPLACE FUNCTION public.facturacion_cerrar_intentos_agotados()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_intento i SET fin=now(),resultado='LEASE_VENCIDO'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.estado='REVISION' AND o.intentos>=o.max_intentos
$$;

CREATE OR REPLACE FUNCTION public.facturacion_cerrar_intentos_operacion(p_id uuid)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_intento SET fin=now(),resultado='LEASE_VENCIDO'
            WHERE id_operacion=p_id AND fin IS NULL
$$;

CREATE OR REPLACE FUNCTION public.facturacion_abrir_intento(p_id uuid, p_number integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO fact_api_intento(id_operacion,numero)
            VALUES(p_id,p_number)
$$;

CREATE OR REPLACE FUNCTION public.facturacion_bloquear_procesada(p_id uuid, p_lease uuid)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_operacion FROM fact_api_operacion
        WHERE id_operacion=p_id AND lease_token=p_lease AND estado='PROCESANDO' FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.facturacion_guardar_documento(p_id uuid, p_local integer, p_external uuid, p_numero text, p_subtotal numeric, p_igv numeric, p_total numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO fact_api_documento
            (id_documento,id_operacion,id_local,id_externo,numero,estado,subtotal,igv,total)
            VALUES(p_id,p_id,p_local,p_external,p_numero,'DEMO_GENERADO',p_subtotal,p_igv,p_total)
            ON CONFLICT(id_operacion) DO NOTHING
$$;

CREATE OR REPLACE FUNCTION public.facturacion_guardar_archivo(p_file uuid, p_id uuid, p_format text, p_path text, p_hash text, p_size integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO fact_api_archivo
                (id_archivo,id_documento,formato,ruta,sha256,bytes)
                VALUES(p_file,p_id,p_format,p_path,p_hash,p_size) ON CONFLICT(id_documento,formato) DO NOTHING
$$;

CREATE OR REPLACE FUNCTION public.facturacion_finalizar_operacion(p_state text, p_status integer, p_error text, p_delay numeric, p_id uuid)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_operacion SET estado=p_state,ultimo_http=p_status,
        ultimo_error=p_error,disponible_en=now()+make_interval(secs=>CAST(p_delay AS double precision)),
        lease_hasta=NULL,lease_token=NULL,actualizado_en=now() WHERE id_operacion=p_id
$$;

CREATE OR REPLACE FUNCTION public.facturacion_finalizar_intento(p_duration numeric, p_status integer, p_state text, p_id uuid, p_number integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_intento SET fin=now(),duracion_ms=p_duration,
        http_status=p_status,resultado=p_state WHERE id_operacion=p_id AND numero=p_number
$$;

CREATE OR REPLACE FUNCTION public.facturacion_registrar_fallo()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_circuito SET fallos=fallos+1,
            abierto_hasta=CASE WHEN fallos>=2 THEN now()+interval '30 seconds' ELSE abierto_hasta END WHERE id=1
$$;

CREATE OR REPLACE FUNCTION public.facturacion_reiniciar_circuito()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_circuito SET fallos=0,abierto_hasta=NULL WHERE id=1
$$;

CREATE OR REPLACE FUNCTION public.facturacion_configuracion_activa(p_local integer)
RETURNS TABLE (id_local integer, activo boolean, ambiente text, empresa jsonb, serie_factura character varying, serie_boleta character varying, tasa_igv numeric, creado_en timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.id_local, c.activo, c.ambiente, c.empresa, c.serie_factura, c.serie_boleta, c.tasa_igv, c.creado_en
FROM fact_api_config c WHERE id_local=p_local AND activo
$$;

CREATE OR REPLACE FUNCTION public.facturacion_bloquear_venta(p_id bigint, p_local integer)
RETURNS TABLE (id_cobro bigint, id_local integer, id_usuario integer, mesa character varying, clave uuid, solicitud_hash character varying, tipo character varying, metodo character varying, documento character varying, cliente character varying, total numeric, comprobante jsonb, id_movimiento integer, creado_en timestamp with time zone, id_jornada bigint, id_cliente uuid)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.id_cobro, c.id_local, c.id_usuario, c.mesa, c.clave, c.solicitud_hash, c.tipo, c.metodo, c.documento,
    c.cliente, c.total, c.comprobante, c.id_movimiento, c.creado_en, c.id_jornada, c.id_cliente
FROM salon_cobro c WHERE id_cobro=p_id AND id_local=p_local FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.facturacion_bloquear_compra(p_id integer, p_local integer)
RETURNS TABLE (id_factura_recepcion integer, id_orden_compra integer, id_proveedor integer, numero_factura character varying, fecha_recepcion date, usuario_recepcion integer, datos_factura jsonb, entregas jsonb, id_local integer, codigo_orden character varying)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT f.id_factura_recepcion, f.id_orden_compra, f.id_proveedor, f.numero_factura, f.fecha_recepcion,
    f.usuario_recepcion, f.datos_factura, f.entregas, o.id_local,o.codigo AS codigo_orden
            FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
            WHERE f.id_factura_recepcion=p_id AND o.id_local=p_local FOR UPDATE OF f
$$;

CREATE OR REPLACE FUNCTION public.facturacion_obsoletar_venta(p_id bigint, p_local integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_operacion SET obsoleto=true,
        estado=CASE WHEN estado='COMPLETADO' THEN estado ELSE 'BLOQUEADO' END,
        lease_token=NULL,lease_hasta=NULL,ultimo_error='Venta interna anulada; documento histórico',
        actualizado_en=now() WHERE origen='VENTA' AND id_origen=p_id AND id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.facturacion_cerrar_intentos_venta(p_id bigint, p_local integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_intento i SET fin=now(),resultado='FUENTE_ANULADA'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.origen='VENTA' AND o.id_origen=p_id AND o.id_local=p_local AND o.obsoleto
$$;

CREATE OR REPLACE FUNCTION public.facturacion_estado_fuente(p_local integer, p_origin text, p_source bigint)
RETURNS TABLE (id_operacion uuid, version integer, estado text, intentos integer, ultimo_error text, obsoleto boolean, creado_en timestamp with time zone, actualizado_en timestamp with time zone, id_documento uuid, numero text, estado_documento text, archivos jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT o.id_operacion,o.version,o.estado,o.intentos,o.ultimo_error,o.obsoleto,
        o.creado_en,o.actualizado_en,d.id_documento,d.numero,d.estado AS estado_documento,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id_archivo,'formato',a.formato))
            FROM fact_api_archivo a WHERE a.id_documento=d.id_documento),'[]'::jsonb) AS archivos
        FROM fact_api_operacion o LEFT JOIN fact_api_documento d USING(id_operacion)
        WHERE o.id_local=p_local AND o.origen=p_origin AND o.id_origen=p_source ORDER BY o.version DESC
$$;

CREATE OR REPLACE FUNCTION public.facturacion_local_configurado(p_local integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT activo FROM fact_api_config WHERE id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.facturacion_originales_compra(p_local integer, p_source integer)
RETURNS TABLE (id_adjunto uuid, formato text, creado_en timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_adjunto,formato,creado_en FROM fact_api_adjunto
            WHERE id_local=p_local AND id_factura_recepcion=p_source ORDER BY creado_en
$$;

CREATE OR REPLACE FUNCTION public.facturacion_compra_disponible(p_id integer, p_local integer)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 1 FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
        WHERE f.id_factura_recepcion=p_id AND o.id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.facturacion_original_por_local(p_id uuid, p_local integer)
RETURNS TABLE (id_adjunto uuid, id_local integer, id_factura_recepcion integer, formato text, ruta text, sha256 character, bytes integer, creado_en timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT a.id_adjunto, a.id_local, a.id_factura_recepcion, a.formato, a.ruta, a.sha256, a.bytes, a.creado_en
FROM fact_api_adjunto a WHERE id_adjunto=p_id AND id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.facturacion_reencolar(p_id uuid, p_local integer)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_operacion SET estado='PENDIENTE',max_intentos=intentos+6,
        disponible_en=now(),lease_token=NULL,lease_hasta=NULL,actualizado_en=now()
        WHERE id_operacion=p_id AND id_local=p_local AND NOT obsoleto AND estado IN ('REVISION','BLOQUEADO','REINTENTO','RECHAZADO')
        RETURNING id_operacion
$$;

CREATE OR REPLACE FUNCTION public.facturacion_actualizar_intentos(p_id uuid)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_operacion SET intentos=(SELECT COALESCE(max(numero),0)
            FROM fact_api_intento WHERE id_operacion=p_id) WHERE id_operacion=p_id
$$;

CREATE OR REPLACE FUNCTION public.facturacion_archivo_por_local(p_id uuid, p_local integer)
RETURNS TABLE (id_archivo uuid, id_documento uuid, formato text, ruta text, sha256 character, bytes integer, creado_en timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT a.id_archivo, a.id_documento, a.formato, a.ruta, a.sha256, a.bytes, a.creado_en
FROM fact_api_archivo a JOIN fact_api_documento d USING(id_documento)
        WHERE a.id_archivo=p_id AND d.id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.facturacion_metricas_local(p_local integer)
RETURNS TABLE (operaciones bigint, completadas bigint, pendientes bigint, requieren_revision bigint, espera_max_segundos numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT count(*) AS operaciones,
        count(*) FILTER(WHERE estado='COMPLETADO') AS completadas,
        count(*) FILTER(WHERE estado IN ('PENDIENTE','PROCESANDO','REINTENTO')) AS pendientes,
        count(*) FILTER(WHERE estado IN ('REVISION','BLOQUEADO','RECHAZADO')) AS requieren_revision,
        extract(epoch FROM now()-min(creado_en) FILTER(WHERE estado IN ('PENDIENTE','REINTENTO'))) AS espera_max_segundos
        FROM fact_api_operacion WHERE id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.facturacion_metricas_intentos(p_local integer)
RETURNS TABLE (intentos bigint, errores bigint, p95_ms double precision)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT count(*) AS intentos,
        count(*) FILTER(WHERE http_status>=400) AS errores,
        percentile_cont(.95) WITHIN GROUP(ORDER BY duracion_ms) AS p95_ms
        FROM fact_api_intento i JOIN fact_api_operacion o USING(id_operacion)
        WHERE o.id_local=p_local AND i.inicio>now()-interval '24 hours'
$$;

CREATE OR REPLACE FUNCTION public.facturacion_escalado_instalado()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.fact_api_escalado') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.facturacion_obtener_escalado()
RETURNS TABLE (id integer, supervisor uuid, pid integer, minimo integer, maximo integer, activos integer, objetivo integer, listos integer, ocupados integer, espera_segundos numeric, pausado boolean, workers jsonb, actualizado_en timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT e.id, e.supervisor, e.pid, e.minimo, e.maximo, e.activos, e.objetivo, e.listos, e.ocupados,
    e.espera_segundos, e.pausado, e.workers, e.actualizado_en
FROM fact_api_escalado e WHERE id=1
$$;

CREATE OR REPLACE FUNCTION public.facturacion_guardar_adjunto(p_id uuid, p_local integer, p_source integer, p_kind text, p_path text, p_hash text, p_size integer)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO fact_api_adjunto
        (id_adjunto,id_local,id_factura_recepcion,formato,ruta,sha256,bytes)
        VALUES(p_id,p_local,p_source,p_kind,p_path,p_hash,p_size)
        ON CONFLICT(id_local,id_factura_recepcion,sha256) DO UPDATE SET sha256=EXCLUDED.sha256
        RETURNING id_adjunto
$$;

CREATE OR REPLACE FUNCTION public.facturacion_estadisticas_cola()
RETURNS TABLE (ready bigint, busy bigint, oldest numeric, blocked boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
        count(*) FILTER(WHERE (estado IN ('PENDIENTE','REINTENTO') AND disponible_en<=now())
            OR (estado='PROCESANDO' AND lease_hasta<now())) AS ready,
        count(*) FILTER(WHERE estado='PROCESANDO' AND lease_hasta>=now()) AS busy,
        COALESCE(extract(epoch FROM now()-min(disponible_en) FILTER(WHERE estado IN ('PENDIENTE','REINTENTO')
            AND disponible_en<=now())),0) AS oldest,
        EXISTS(SELECT 1 FROM fact_api_circuito WHERE abierto_hasta>now()) AS blocked
        FROM fact_api_operacion WHERE NOT obsoleto AND (intentos<max_intentos
            OR (estado='PROCESANDO' AND lease_hasta>=now()))
$$;

CREATE OR REPLACE FUNCTION public.facturacion_salud_transporte()
RETURNS TABLE (total bigint, bad bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT count(*) AS total,
        count(*) FILTER(WHERE http_status=429 OR http_status>=500) AS bad
        FROM fact_api_intento WHERE inicio>now()-interval '60 seconds' AND fin IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.facturacion_adquirir_liderazgo(p_group integer, p_identity integer)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_try_advisory_lock(p_group,p_identity)
$$;

CREATE OR REPLACE FUNCTION public.facturacion_liberar_liderazgo(p_group integer, p_identity integer)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_unlock(p_group,p_identity)
$$;

CREATE OR REPLACE FUNCTION public.facturacion_adquirir_slot(p_group integer, p_slot integer)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_try_advisory_lock(p_group,p_slot)
$$;

CREATE OR REPLACE FUNCTION public.facturacion_pid_conexion()
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_backend_pid()
$$;

CREATE OR REPLACE FUNCTION public.facturacion_es_supervisor(p_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM fact_api_escalado
        WHERE id=1 AND supervisor=p_id AND actualizado_en>now()-interval '20 seconds')
$$;

CREATE OR REPLACE FUNCTION public.facturacion_actualizar_supervisor(p_id uuid, p_pid integer, p_minimum integer, p_maximum integer, p_active integer, p_desired integer, p_ready integer, p_busy integer, p_oldest numeric, p_paused boolean, p_workers text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO fact_api_escalado
            (id,supervisor,pid,minimo,maximo,activos,objetivo,listos,ocupados,espera_segundos,pausado,workers,actualizado_en)
            VALUES(1,p_id,p_pid,p_minimum,p_maximum,p_active,p_desired,p_ready,p_busy,p_oldest,p_paused,CAST(p_workers AS jsonb),now())
            ON CONFLICT(id) DO UPDATE SET supervisor=EXCLUDED.supervisor,pid=EXCLUDED.pid,
            minimo=EXCLUDED.minimo,maximo=EXCLUDED.maximo,activos=EXCLUDED.activos,objetivo=EXCLUDED.objetivo,
            listos=EXCLUDED.listos,ocupados=EXCLUDED.ocupados,espera_segundos=EXCLUDED.espera_segundos,
            pausado=EXCLUDED.pausado,workers=EXCLUDED.workers,actualizado_en=now()
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.perfiles'::regclass
                   AND attname='ve_escalado_fact_api' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN ve_escalado_fact_api boolean NOT NULL DEFAULT false;
        UPDATE public.perfiles SET ve_escalado_fact_api=true WHERE id_perfil=1;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.facturacion_perfil_ve_escalado(p_perfil integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (SELECT FROM public.perfiles p
        WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.ve_escalado_fact_api)
$$;

CREATE OR REPLACE FUNCTION public.facturacion_retirar_supervisor(p_id uuid)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_escalado SET activos=0,objetivo=0,workers='[]',
                    actualizado_en=now() WHERE supervisor=p_id
$$;

CREATE OR REPLACE FUNCTION public.facturacion_fuentes_ejemplo()
RETURNS TABLE (origin text,id_local integer,source bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 'VENTA' AS origin,id_local,max(id_cobro) AS source
                FROM salon_cobro WHERE NOT(comprobante ? 'anulacion') GROUP BY id_local
                UNION ALL SELECT 'COMPRA',o.id_local,max(f.id_factura_recepcion)
                FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
                WHERE datos_factura IS NOT NULL GROUP BY o.id_local
$$;

CREATE OR REPLACE FUNCTION public.facturacion_conteo_estados()
RETURNS TABLE (id_local integer,origen text,estado text,cantidad bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_local,origen,estado,count(*) AS cantidad FROM fact_api_operacion GROUP BY id_local,origen,estado ORDER BY 1,2
$$;

CREATE OR REPLACE FUNCTION public.facturacion_ventas_completadas_pdf()
RETURNS SETOF public.fact_api_operacion
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT o.* FROM fact_api_operacion o
            JOIN fact_api_documento d USING(id_operacion)
            WHERE o.origen='VENTA' AND o.estado='COMPLETADO' AND NOT o.obsoleto
            ORDER BY o.creado_en
$$;

CREATE OR REPLACE FUNCTION public.facturacion_bloquear_pdf_actualizable(p_id uuid)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_operacion FROM fact_api_operacion
                WHERE id_operacion=p_id AND estado='COMPLETADO' AND NOT obsoleto FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.facturacion_actualizar_pdf(p_path text, p_hash text, p_size integer, p_id uuid, p_format text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE fact_api_archivo SET ruta=p_path,sha256=p_hash,bytes=p_size
                    WHERE id_documento=p_id AND formato=p_format
$$;

COMMIT;
