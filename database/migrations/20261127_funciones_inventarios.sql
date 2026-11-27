BEGIN;

-- Las consultas por puesto se usan cuando esa migraci?n est? instalada.
SET LOCAL check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.inv_operativo_bloqueo(p_clave text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock(hashtext(p_clave))
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_ventas(p_separar boolean, p_local integer, p_jornada bigint, p_desde date, p_hasta date, p_todas boolean, p_horas integer[])
RETURNS TABLE (id_presentacion integer, nombre text, hora integer, cantidad numeric, total numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT (linea->>'id_presentacion')::integer AS id_presentacion,
        linea->>'nombre' AS nombre,
        CASE WHEN p_separar THEN extract(hour FROM c.creado_en AT TIME ZONE 'America/Lima')::int ELSE NULL END AS hora,
        sum((linea->>'cantidad')::numeric) AS cantidad,
        sum((linea->>'cantidad')::numeric*(linea->>'precio')::numeric) AS total
        FROM salon_cobro c LEFT JOIN inventario_jornada j USING(id_jornada)
        CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') linea
        WHERE c.comprobante->'anulacion' IS NULL AND c.id_local=p_local AND
        ((CAST(p_jornada AS bigint) IS NOT NULL AND c.id_jornada=p_jornada) OR
         (CAST(p_jornada AS bigint) IS NULL AND coalesce(j.fecha,(c.creado_en AT TIME ZONE 'America/Lima')::date) BETWEEN p_desde AND p_hasta))
        AND (p_todas OR extract(hour FROM c.creado_en AT TIME ZONE 'America/Lima')::int=ANY(p_horas))
        GROUP BY 1,2,3 ORDER BY cantidad DESC,total DESC,nombre,hora
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_reporte_1(p_id bigint)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, unidad character varying, inicial numeric, entradas numeric, salidas numeric, final numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,
        coalesce(i.cantidad,0) AS inicial,
        coalesce(e.entradas,0) AS entradas,coalesce(e.salidas,0) AS salidas,
        coalesce(i.cantidad,0)+coalesce(e.entradas,0)-coalesce(e.salidas,0) AS final
        FROM producto p LEFT JOIN inventario_jornada_inicio i ON i.id_producto=p.id_producto AND i.id_jornada=p_id
        LEFT JOIN (SELECT id_producto,sum(greatest(cantidad,0)) entradas,sum(greatest(-cantidad,0)) salidas
          FROM inventario_evento WHERE id_jornada=p_id GROUP BY id_producto) e ON e.id_producto=p.id_producto
        WHERE i.id_producto IS NOT NULL OR e.id_producto IS NOT NULL OR p.activo ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_reporte_2(p_id bigint)
RETURNS TABLE (id_producto integer, motivo character varying, etiqueta text, entradas numeric, salidas numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT e.id_producto,e.motivo,
        coalesce(m.etiqueta, initcap(replace(e.motivo, '_', ' '))) etiqueta,
        sum(greatest(e.cantidad,0)) entradas,sum(greatest(-e.cantidad,0)) salidas
        FROM inventario_evento e LEFT JOIN public.movimiento_motivo m ON m.codigo=e.motivo
        WHERE e.id_jornada=p_id GROUP BY e.id_producto,e.motivo,m.etiqueta ORDER BY e.motivo
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_dias(p_local integer)
RETURNS TABLE (id_jornada bigint, fecha date, abierto_en timestamp with time zone, cerrado_en timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_jornada,fecha,abierto_en,cerrado_en FROM inventario_jornada
        WHERE id_local=p_local ORDER BY fecha DESC LIMIT 366
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_abrir(p_local integer, p_usuario integer)
RETURNS bigint
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT inventario_abrir_jornada(p_local,p_usuario)
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_jornada_local(p_id bigint, p_local integer)
RETURNS TABLE (id_jornada bigint, id_local integer, fecha date, abierto_en timestamp with time zone, cerrado_en timestamp with time zone, abierto_por integer, cerrado_por integer, reporte jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT * FROM inventario_jornada WHERE id_jornada=p_id AND id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_cerrar_1()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
LOCK TABLE salon_pedido IN SHARE MODE
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_cerrar_2(p_local integer)
RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT count(*) FROM salon_pedido_actual p WHERE p.id_local=p_local
            AND EXISTS(SELECT 1 FROM salon_pedido_linea l WHERE l.id_pedido=p.id_pedido
            AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea))
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_cerrar_3(p_usuario integer, p_reporte text, p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE inventario_jornada SET cerrado_en=clock_timestamp(),cerrado_por=p_usuario,
            reporte=CAST(p_reporte AS jsonb) WHERE id_jornada=p_id
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_demanda()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_cobro') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_plan_semanal()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_cobro') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_equipo(p_local integer)
RETURNS TABLE (id_usuario integer, nombre text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) nombre
        FROM usuario u JOIN usuario_local ul USING(id_usuario) WHERE ul.id_local=p_local AND ul.estado_registro=1
        AND u.estado_registro=1 AND EXISTS(SELECT 1 FROM usuario_perfiles up JOIN perfiles p USING(id_perfil)
        WHERE up.id_usuario=u.id_usuario AND public.perfil_tiene_capacidad(up.id_perfil, 'operar_tienda') AND up.estado_registro=1 AND p.estado_registro=1)
        ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_puestos_instalados()
RETURNS regclass
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.inventario_asignacion_puesto')
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_puestos_conteo()
RETURNS TABLE (id_puesto_laboral integer, nombre character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_puesto_laboral,nombre FROM puesto_laboral WHERE estado_registro=1
        AND lower(trim(nombre)) IN ('cocina','bartender','mesero') ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_asignaciones(p_local integer)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, categoria character varying, id_puesto_laboral integer, puesto character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto,p.codigo,p.nombre,
        cp.nombre categoria,a.id_puesto_laboral,pl.nombre puesto
        FROM producto p JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN inventario_asignacion_puesto a ON a.id_producto=p.id_producto AND a.id_local=p_local
        LEFT JOIN puesto_laboral pl ON pl.id_puesto_laboral=a.id_puesto_laboral
        WHERE p.activo ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_guardar_asignaciones_1(p_ids integer[])
RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT count(*) FROM producto WHERE activo AND id_producto=ANY(p_ids)
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_guardar_asignaciones_2(p_local integer, p_ids integer[])
RETURNS TABLE (id_local integer, id_producto integer, id_puesto_laboral integer, actualizado_por integer, actualizado_en timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT * FROM inventario_asignacion_puesto WHERE id_local=p_local AND id_producto=ANY(p_ids)
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_guardar_asignaciones_3(p_local integer, p_ids integer[])
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM inventario_asignacion_puesto WHERE id_local=p_local AND id_producto=ANY(p_ids)
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_guardar_asignaciones_4(p_local integer, p_puesto integer, p_usuario integer, p_ids integer[])
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO inventario_asignacion_puesto(id_local,id_producto,id_puesto_laboral,actualizado_por)
                SELECT p_local,p.id_producto,p_puesto,p_usuario FROM producto p WHERE p.id_producto=ANY(p_ids)
                ON CONFLICT(id_local,id_producto) DO UPDATE SET id_puesto_laboral=excluded.id_puesto_laboral,
                actualizado_por=excluded.actualizado_por,actualizado_en=clock_timestamp()
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_rondas(p_local integer, p_gestor boolean, p_usuario integer)
RETURNS TABLE (id_ronda bigint, id_local integer, nombre character varying, creado_por integer, creado_en timestamp with time zone, cerrado_en timestamp with time zone, por_puesto boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT r.id_ronda,
    r.id_local,
    r.nombre,
    r.creado_por,
    r.creado_en,
    r.cerrado_en,
    COALESCE((to_jsonb(r)->>'por_puesto')::boolean, false) FROM inventario_ronda r WHERE id_local=p_local
        AND (p_gestor OR EXISTS(SELECT 1 FROM inventario_conteo c WHERE c.id_ronda=r.id_ronda AND c.asignado_a=p_usuario))
        ORDER BY creado_en DESC LIMIT 200
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_rondas_puestos(p_local integer, p_gestor boolean, p_puesto integer, p_usuario integer)
RETURNS TABLE (id_ronda bigint, id_local integer, nombre character varying, creado_por integer, creado_en timestamp with time zone, cerrado_en timestamp with time zone, por_puesto boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT r.* FROM inventario_ronda r WHERE id_local=p_local
        AND (p_gestor OR EXISTS(SELECT 1 FROM inventario_conteo c WHERE c.id_ronda=r.id_ronda AND ((r.por_puesto AND c.puesto_asignado=p_puesto) OR (NOT r.por_puesto AND c.asignado_a=p_usuario))))
        ORDER BY creado_en DESC LIMIT 200
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_crear_ronda_1(p_local integer)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 1 FROM inventario_asignacion_puesto a
                JOIN producto p USING(id_producto) JOIN puesto_laboral pl USING(id_puesto_laboral)
                WHERE a.id_local=p_local AND p.activo AND pl.estado_registro=1 LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_crear_ronda_2(p_local integer)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 1 FROM inventario_ronda WHERE id_local=p_local AND cerrado_en IS NULL
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_crear_ronda_3(p_local integer, p_nombre text, p_usuario integer)
RETURNS bigint
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO inventario_ronda(id_local,nombre,creado_por)
            VALUES(p_local,p_nombre,p_usuario) RETURNING id_ronda
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_crear_ronda_4(p_id bigint, p_local integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO inventario_conteo(id_ronda,id_producto,teorico)
            SELECT p_id,s.id_producto,s.stock_actual FROM inventario_stock_teorico s JOIN producto p USING(id_producto)
            WHERE s.id_local=p_local AND p.activo
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_crear_ronda_5(p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE inventario_ronda SET por_puesto=true WHERE id_ronda=p_id
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_crear_ronda_6(p_id bigint, p_local integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE inventario_conteo c SET puesto_asignado=a.id_puesto_laboral,puesto_nombre=p.nombre
                FROM inventario_asignacion_puesto a JOIN puesto_laboral p USING(id_puesto_laboral)
                WHERE c.id_ronda=p_id AND c.id_producto=a.id_producto AND a.id_local=p_local AND p.estado_registro=1
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_ronda_local(p_id bigint, p_local integer)
RETURNS TABLE (id_ronda bigint, id_local integer, nombre character varying, creado_por integer, creado_en timestamp with time zone, cerrado_en timestamp with time zone, por_puesto boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT r.id_ronda,
    r.id_local,
    r.nombre,
    r.creado_por,
    r.creado_en,
    r.cerrado_en,
    COALESCE((to_jsonb(r)->>'por_puesto')::boolean, false) FROM inventario_ronda r WHERE id_ronda=p_id AND id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_detalle_conteo(p_id bigint, p_gestor boolean, p_usuario integer)
RETURNS TABLE (id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text, nombre character varying, codigo character varying, unidad character varying, categoria character varying, asignado_nombre text, contado_nombre text, diferencia numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text,p.nombre,p.codigo,p.unidad,cp.nombre AS categoria,
        concat_ws(' ',u.nombres,u.apellido_paterno) AS asignado_nombre,
        concat_ws(' ',contador.nombres,contador.apellido_paterno) AS contado_nombre,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia
        FROM inventario_conteo c JOIN producto p USING(id_producto) JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN usuario contador ON contador.id_usuario=c.contado_por
        LEFT JOIN usuario u ON u.id_usuario=c.asignado_a WHERE c.id_ronda=p_id
        AND (p_gestor OR c.asignado_a=p_usuario) ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_detalle_conteo_puestos(p_id bigint, p_gestor boolean, p_puesto integer)
RETURNS TABLE (id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text, nombre character varying, codigo character varying, unidad character varying, categoria character varying, asignado_nombre text, contado_nombre text, diferencia numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.*,p.nombre,p.codigo,p.unidad,cp.nombre AS categoria,
        concat_ws(' ',u.nombres,u.apellido_paterno) AS asignado_nombre,
        concat_ws(' ',contador.nombres,contador.apellido_paterno) AS contado_nombre,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia
        FROM inventario_conteo c JOIN producto p USING(id_producto) JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN usuario contador ON contador.id_usuario=c.contado_por
        LEFT JOIN usuario u ON u.id_usuario=c.asignado_a WHERE c.id_ronda=p_id
        AND (p_gestor OR c.puesto_asignado=p_puesto) ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_editar_conteo_2(p_id bigint, p_local integer)
RETURNS bigint
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_ronda FROM inventario_ronda WHERE id_ronda=p_id AND id_local=p_local FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_editar_conteo_3(p_id bigint, p_producto integer)
RETURNS TABLE (id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text FROM inventario_conteo c WHERE id_ronda=p_id AND id_producto=p_producto FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_editar_conteo_4(p_id bigint)
RETURNS character varying
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT nombre FROM perfiles WHERE id_perfil=p_id
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_editar_conteo_5(p_id bigint)
RETURNS character varying
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT nombre FROM puesto_laboral WHERE id_puesto_laboral=p_id
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_editar_conteo_7(p_id bigint, p_producto integer, p_usuario integer, p_accion text, p_anterior text, p_nuevo text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo)
            VALUES(p_id,p_producto,p_usuario,p_accion,CAST(p_anterior AS jsonb),CAST(p_nuevo AS jsonb))
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_finalizar_conteo_1(p_id bigint, p_local integer)
RETURNS bigint
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_ronda FROM inventario_ronda WHERE id_ronda=p_id AND id_local=p_local FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_finalizar_conteo_2(p_id bigint)
RETURNS TABLE (id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text FROM inventario_conteo c WHERE id_ronda=p_id ORDER BY id_producto FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_finalizar_conteo_3(p_perfil integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT puede_revisar FROM perfil_opcion_menu
                WHERE id_perfil=p_perfil AND id_opcion_menu=public.permiso_opcion_recurso('conteo_fisico') AND estado_registro=1
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_finalizar_conteo_4(p_valor numeric, p_nota text, p_usuario integer, p_id bigint, p_producto integer)
RETURNS SETOF public.inventario_conteo
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE inventario_conteo SET corregido=p_valor,observacion=p_nota,estado='REVISADO',
                    justificacion='',justificado_por=NULL,justificado_en=NULL,
                    revisado_por=p_usuario,revisado_en=clock_timestamp(),version=version+1
                    WHERE id_ronda=p_id AND id_producto=p_producto RETURNING *
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_finalizar_conteo_5(p_id bigint, p_producto integer, p_usuario integer, p_anterior text, p_nuevo text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo)
                    VALUES(p_id,p_producto,p_usuario,'revisar',CAST(p_anterior AS jsonb),CAST(p_nuevo AS jsonb))
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_finalizar_conteo_6(p_id bigint)
RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT count(*) FROM inventario_conteo WHERE id_ronda=p_id AND estado<>'REVISADO'
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_finalizar_conteo_7(p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE inventario_ronda SET cerrado_en=clock_timestamp() WHERE id_ronda=p_id
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_diferencias(p_local integer, p_desde date, p_hasta date, p_top integer)
RETURNS TABLE (id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text, nombre character varying, unidad character varying, ronda character varying, creado_en timestamp with time zone, diferencia numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text,p.nombre,p.unidad,r.nombre AS ronda,r.creado_en,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia FROM inventario_conteo c
        JOIN inventario_ronda r USING(id_ronda) JOIN producto p USING(id_producto)
        WHERE r.id_local=p_local AND (r.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        AND c.estado='REVISADO' AND coalesce(c.corregido,c.contado)<>c.teorico
        ORDER BY abs(coalesce(c.corregido,c.contado)-c.teorico) DESC,r.creado_en DESC,p.nombre LIMIT p_top
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_historial(p_id bigint)
RETURNS TABLE (id_historial bigint, id_ronda bigint, id_producto integer, id_usuario integer, accion character varying, anterior jsonb, nuevo jsonb, creado_en timestamp with time zone, usuario text, producto character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT h.*,concat_ws(' ',u.nombres,u.apellido_paterno) usuario,p.nombre producto
        FROM inventario_conteo_historial h JOIN usuario u USING(id_usuario) JOIN producto p USING(id_producto)
        WHERE h.id_ronda=p_id ORDER BY h.id_historial DESC LIMIT 1000
$$;

CREATE OR REPLACE FUNCTION public.inv_operativo_actualizar_conteo(p_ronda bigint, p_producto integer, p_cambios text, p_accion text)
RETURNS SETOF public.inventario_conteo
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DECLARE
    campos text;
    fecha text;
    cambios jsonb := p_cambios::jsonb;
BEGIN
    IF EXISTS (
        SELECT FROM jsonb_object_keys(cambios) AS clave(nombre)
        WHERE nombre NOT IN ('puesto_asignado','puesto_nombre','asignado_a','contado','contado_por',
            'estado','contado_perfil','contado_puesto','contado_perfil_nombre','contado_puesto_nombre',
            'corregido','observacion','revisado_por','justificacion','justificado_por','justificado_en')
    ) THEN
        RAISE EXCEPTION 'Campo de conteo no autorizado';
    END IF;
    SELECT string_agg(format('%1$I=(jsonb_populate_record(c,$3)).%1$I',nombre), ',')
      INTO campos FROM jsonb_object_keys(cambios) AS clave(nombre);
    fecha := CASE p_accion WHEN 'contar' THEN 'contado_en' WHEN 'revisar' THEN 'revisado_en'
                          WHEN 'justificar' THEN 'justificado_en' END;
    IF fecha IS NOT NULL THEN campos := campos || format(',%I=clock_timestamp()',fecha); END IF;
    RETURN QUERY EXECUTE 'UPDATE public.inventario_conteo c SET ' || campos ||
        ',version=c.version+1 WHERE c.id_ronda=$1 AND c.id_producto=$2 RETURNING c.*'
        USING p_ronda,p_producto,cambios;
END;
$$;

RESET check_function_bodies;

COMMIT;
