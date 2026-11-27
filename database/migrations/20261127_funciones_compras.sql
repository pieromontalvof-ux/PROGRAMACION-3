BEGIN;

CREATE OR REPLACE FUNCTION public.compras_producto_activo_existe(p_id_producto integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
                SELECT 1
                FROM producto
                WHERE id_producto = p_id_producto
                  AND activo = TRUE
            )
$$;

CREATE OR REPLACE FUNCTION public.compras_bloquear_codigo()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock(
            hashtext('orden_compra_codigo')
        )
$$;

CREATE OR REPLACE FUNCTION public.compras_siguiente_numero_orden()
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT COALESCE(MAX(
            CASE
                WHEN codigo ~ '^OC-[0-9]+$'
                THEN SUBSTRING(codigo FROM 4)::INTEGER
                ELSE 0
            END
        ), 0) + 1
        FROM orden_compra
$$;

CREATE OR REPLACE FUNCTION public.compras_crear_cabecera_orden(p_id_local_actual integer, p_codigo text, p_estado text, p_id_usuario integer, p_fecha_registro date)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO orden_compra (
                id_local,
                codigo,
                estado_orden_compra,
                usuario_registro,
                fecha_registro
            ) VALUES (
                p_id_local_actual,
                p_codigo,
                p_estado,
                p_id_usuario,
                p_fecha_registro
            )
            RETURNING id_orden_compra
$$;

CREATE OR REPLACE FUNCTION public.compras_crear_detalle_orden(p_id_producto integer, p_id_orden integer, p_cantidad numeric, p_id_local_actual integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO orden_compra_detalle (
                id_proveedor,
                id_orden_compra,
                id_producto,
                cantidad_solicitada
            ) SELECT
                (SELECT id_proveedor FROM producto WHERE id_producto=p_id_producto),
                p_id_orden,
                p_id_producto,
                p_cantidad
             WHERE EXISTS (SELECT 1 FROM public.orden_compra o WHERE o.id_orden_compra=p_id_orden AND o.id_local=p_id_local_actual)
$$;

CREATE OR REPLACE FUNCTION public.compras_listar_historial_ordenes(p_id_local_actual integer, p_fecha_desde date, p_fecha_hasta date, p_estado text)
RETURNS TABLE (id_orden_compra integer, codigo character varying, estado_orden_compra character varying, fecha_registro date, registrado_por text, total_productos bigint, productos_con_recepcion bigint, productos_completos bigint, productos_pendientes bigint, motivo_cierre character varying, fecha_modificacion timestamp without time zone, modificado_por text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
WITH recibido_por_producto AS (
            SELECT
                fr.id_orden_compra,
                frd.id_producto,
                SUM(frd.cantidad_recibida) AS cantidad_recibida
            FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
            JOIN factura_recepcion_detalle frd
                ON frd.id_factura_recepcion =
                   fr.id_factura_recepcion
            GROUP BY
                fr.id_orden_compra,
                frd.id_producto
        ),
        avance_por_orden AS (
            SELECT
                ocd.id_orden_compra,
                COUNT(*) AS total_productos,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0) > 0
                ) AS productos_con_recepcion,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0)
                          >= ocd.cantidad_solicitada
                ) AS productos_completos,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0)
                          < ocd.cantidad_solicitada
                ) AS productos_pendientes
            FROM orden_compra_detalle ocd
            LEFT JOIN recibido_por_producto rpp
                ON rpp.id_orden_compra = ocd.id_orden_compra
               AND rpp.id_producto = ocd.id_producto
            GROUP BY ocd.id_orden_compra
        )
        SELECT
            oc.id_orden_compra,
            oc.codigo,
            oc.estado_orden_compra,
            oc.fecha_registro,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS registrado_por,
            COALESCE(apo.total_productos, 0)
                AS total_productos,
            COALESCE(apo.productos_con_recepcion, 0)
                AS productos_con_recepcion,
            COALESCE(apo.productos_completos, 0)
                AS productos_completos,
            COALESCE(apo.productos_pendientes, 0)
                AS productos_pendientes,
            oc.motivo_cierre,
            oc.fecha_modificacion,
            NULLIF(BTRIM(CONCAT_WS(
                ' ',
                um.nombres,
                um.apellido_paterno,
                um.apellido_materno
            )), '') AS modificado_por
        FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
        JOIN usuario u
            ON u.id_usuario = oc.usuario_registro
        LEFT JOIN usuario um
            ON um.id_usuario = oc.usuario_modificacion
        LEFT JOIN avance_por_orden apo
            ON apo.id_orden_compra = oc.id_orden_compra
        WHERE (
            CAST(p_fecha_desde AS DATE) IS NULL
            OR oc.fecha_registro >= CAST(p_fecha_desde AS DATE)
        )
          AND (
            CAST(p_fecha_hasta AS DATE) IS NULL
            OR oc.fecha_registro <= CAST(p_fecha_hasta AS DATE)
          )
          AND (
            CAST(p_estado AS VARCHAR) IS NULL
            OR oc.estado_orden_compra = CAST(p_estado AS VARCHAR)
          )
        ORDER BY
            oc.fecha_registro DESC NULLS LAST,
            oc.id_orden_compra DESC
$$;

CREATE OR REPLACE FUNCTION public.compras_obtener_detalle_orden_historial(p_id_local_actual integer, p_id_orden integer)
RETURNS TABLE (id_orden_compra_detalle integer, id_producto integer, codigo character varying, nombre character varying, unidad character varying, id_proveedor integer, proveedor character varying, cantidad_solicitada numeric, cantidad_recibida numeric, cantidad_pendiente numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
            ocd.id_orden_compra_detalle,
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            pr.id_proveedor,
            pr.nombre AS proveedor,
            ocd.cantidad_solicitada,
            COALESCE((
                SELECT SUM(frd.cantidad_recibida)
                FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
                JOIN factura_recepcion_detalle frd
                    ON frd.id_factura_recepcion =
                       fr.id_factura_recepcion
                WHERE fr.id_orden_compra = ocd.id_orden_compra
                  AND frd.id_producto = ocd.id_producto
            ), 0) AS cantidad_recibida,
            GREATEST(
                ocd.cantidad_solicitada - COALESCE((
                    SELECT SUM(frd.cantidad_recibida)
                    FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
                    JOIN factura_recepcion_detalle frd
                        ON frd.id_factura_recepcion =
                           fr.id_factura_recepcion
                    WHERE fr.id_orden_compra = ocd.id_orden_compra
                      AND frd.id_producto = ocd.id_producto
                ), 0),
                0
            ) AS cantidad_pendiente
        FROM orden_compra_detalle ocd
        JOIN producto p
            ON p.id_producto = ocd.id_producto
        JOIN proveedor pr
            ON pr.id_proveedor = ocd.id_proveedor
        WHERE ocd.id_orden_compra = p_id_orden AND EXISTS (SELECT 1 FROM public.orden_compra o WHERE o.id_orden_compra=ocd.id_orden_compra AND o.id_local=p_id_local_actual)
        ORDER BY pr.nombre, p.nombre
$$;

CREATE OR REPLACE FUNCTION public.compras_obtener_orden_historial(p_id_local_actual integer, p_id_orden integer)
RETURNS TABLE (id_orden_compra integer, codigo character varying, estado_orden_compra character varying, fecha_registro date, motivo_cierre character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
            id_orden_compra,
            codigo,
            estado_orden_compra,
            fecha_registro,
            motivo_cierre
        FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) orden_compra
        WHERE id_orden_compra = p_id_orden
$$;

CREATE OR REPLACE FUNCTION public.compras_obtener_orden_historial_bloqueada(p_id_local_actual integer, p_id_orden integer)
RETURNS TABLE (id_orden_compra integer, codigo character varying, estado_orden_compra character varying, fecha_registro date, motivo_cierre character varying)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
            id_orden_compra,
            codigo,
            estado_orden_compra,
            fecha_registro,
            motivo_cierre
        FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) orden_compra
        WHERE id_orden_compra = p_id_orden FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.compras_obtener_total_recibido_orden(p_id_local_actual integer, p_id_orden integer)
RETURNS numeric
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT COALESCE(SUM(frd.cantidad_recibida), 0)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion = fr.id_factura_recepcion
        WHERE fr.id_orden_compra = p_id_orden
$$;

CREATE OR REPLACE FUNCTION public.compras_guardar_historial_estado_orden(p_id_orden integer, p_estado_anterior text, p_estado_nuevo text, p_motivo text, p_id_usuario integer, p_id_local_actual integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO orden_compra_estado_historial (
                id_orden_compra,
                estado_anterior,
                estado_nuevo,
                motivo,
                usuario_modificacion
            ) SELECT
                p_id_orden,
                p_estado_anterior,
                p_estado_nuevo,
                p_motivo,
                p_id_usuario
             WHERE EXISTS (SELECT 1 FROM public.orden_compra o WHERE o.id_orden_compra=p_id_orden AND o.id_local=p_id_local_actual)
$$;

CREATE OR REPLACE FUNCTION public.compras_enviar_orden_borrador(p_usuario integer, p_id integer, p_id_local_actual integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE orden_compra SET estado_orden_compra='ENVIADA',
        fecha_registro=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date,
        usuario_modificacion=p_usuario,fecha_modificacion=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')
        WHERE id_orden_compra=p_id AND estado_orden_compra='BORRADOR' AND id_local=p_id_local_actual
$$;

CREATE OR REPLACE FUNCTION public.compras_cambiar_estado_orden_historial(p_estado text, p_motivo text, p_id_usuario integer, p_id_orden integer, p_id_local_actual integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE orden_compra
            SET estado_orden_compra = p_estado,
                motivo_cierre = p_motivo,
                usuario_modificacion = p_id_usuario,
                fecha_modificacion = (
                    CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'
                )
            WHERE id_orden_compra = p_id_orden AND id_local=p_id_local_actual
$$;

CREATE OR REPLACE FUNCTION public.compras_estado_orden_valido(p_estado text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
    SELECT 1 FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([^'']+)''::character varying', 'g') AS valor
    WHERE c.conname='ck_orden_estado' AND c.conrelid='public.orden_compra'::regclass AND valor[1]=p_estado
)
$$;

COMMIT;
