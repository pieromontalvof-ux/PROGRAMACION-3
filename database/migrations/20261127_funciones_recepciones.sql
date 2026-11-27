BEGIN;

CREATE OR REPLACE FUNCTION public.recep_proveedor(p_id integer)
RETURNS TABLE (nombre text, datos_comerciales jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT nombre, datos_comerciales FROM proveedor WHERE id_proveedor=p_id
$$;

CREATE OR REPLACE FUNCTION public.recep_facturacion_pendiente(p_orden integer, p_proveedor integer, p_producto integer, p_id_local_actual integer)
RETURNS TABLE (nombre text, codigo text, unidad text, cantidad_solicitada numeric, facturado numeric)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.nombre, p.codigo, p.unidad, d.cantidad_solicitada,
  COALESCE((SELECT SUM(CASE WHEN f.datos_factura IS NULL THEN
    COALESCE((SELECT SUM(r.cantidad_recibida) FROM factura_recepcion_detalle r
      WHERE r.id_factura_recepcion=f.id_factura_recepcion AND r.id_producto=d.id_producto),0)
    ELSE COALESCE((SELECT SUM((j->>'cantidad_facturada')::numeric)
      FROM jsonb_array_elements(f.datos_factura->'lineas') j
      WHERE (j->>'id_producto')::int=d.id_producto),0) END)
    FROM factura_recepcion f WHERE f.id_orden_compra=d.id_orden_compra AND f.id_proveedor=p_proveedor),0) AS facturado
FROM orden_compra_detalle d JOIN orden_compra o USING(id_orden_compra)
JOIN producto p USING(id_producto)
WHERE d.id_orden_compra=p_orden AND d.id_proveedor=p_proveedor
  AND d.id_producto=p_producto AND o.id_local=p_id_local_actual
FOR UPDATE OF d
$$;

CREATE OR REPLACE FUNCTION public.recep_guardar_datos(p_id integer, p_datos text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE factura_recepcion SET datos_factura=CAST(p_datos AS jsonb) WHERE id_factura_recepcion=p_id
$$;

CREATE OR REPLACE FUNCTION public.recep_datos_factura(p_id integer)
RETURNS TABLE (datos_factura jsonb, entregas jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT datos_factura, entregas FROM factura_recepcion WHERE id_factura_recepcion=p_id
$$;

CREATE OR REPLACE FUNCTION public.recep_anotar_entrega(p_id integer, p_datos text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE factura_recepcion SET entregas=entregas || CAST(p_datos AS jsonb) WHERE id_factura_recepcion=p_id
$$;

CREATE OR REPLACE FUNCTION public.recep_pendientes(p_id_local_actual integer)
RETURNS TABLE (id_orden_compra integer, codigo_orden text, estado_orden_compra text, fecha_registro date, id_proveedor integer, proveedor text, datos_comerciales jsonb, id_producto integer, codigo_producto text, producto text, categoria text, unidad text, presentacion numeric, cantidad_solicitada numeric, cantidad_recibida numeric, cantidad_pendiente numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
WITH recibido AS (
    SELECT
        fr.id_orden_compra,
        fr.id_proveedor,
        frd.id_producto,
        SUM(frd.cantidad_recibida) AS cantidad_recibida
    FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
    JOIN factura_recepcion_detalle frd
        ON frd.id_factura_recepcion = fr.id_factura_recepcion
    GROUP BY
        fr.id_orden_compra,
        fr.id_proveedor,
        frd.id_producto
)
SELECT
    oc.id_orden_compra,
    oc.codigo AS codigo_orden,
    oc.estado_orden_compra,
    oc.fecha_registro,
    pr.id_proveedor,
    pr.nombre AS proveedor,
    pr.datos_comerciales,
    p.id_producto,
    p.codigo AS codigo_producto,
    p.nombre AS producto,
    cp.nombre AS categoria,
    p.unidad,
    p.presentacion,
    ocd.cantidad_solicitada,
    COALESCE(r.cantidad_recibida, 0) AS cantidad_recibida,
    GREATEST(
        ocd.cantidad_solicitada
        - COALESCE(r.cantidad_recibida, 0),
        0
    ) AS cantidad_pendiente
FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
JOIN orden_compra_detalle ocd
    ON ocd.id_orden_compra = oc.id_orden_compra
JOIN producto p
    ON p.id_producto = ocd.id_producto
JOIN categoria_producto cp
    ON cp.id_categoria = p.id_categoria
JOIN proveedor pr
    ON pr.id_proveedor = ocd.id_proveedor
LEFT JOIN recibido r
    ON r.id_orden_compra = oc.id_orden_compra
   AND r.id_proveedor = pr.id_proveedor
   AND r.id_producto = p.id_producto
WHERE oc.estado_orden_compra IN (
    'ENVIADA',
    'RECEPCION_PARCIAL'
)
  AND ocd.cantidad_solicitada
      > COALESCE(r.cantidad_recibida, 0)
ORDER BY
    oc.fecha_registro,
    oc.codigo,
    pr.nombre,
    p.nombre
$$;

CREATE OR REPLACE FUNCTION public.recep_bloquear_orden(p_id_orden integer, p_id_local_actual integer)
RETURNS TABLE (id_orden_compra integer, codigo text, estado_orden_compra text)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    id_orden_compra,
    codigo,
    estado_orden_compra
FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) orden_compra
WHERE id_orden_compra = p_id_orden
FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.recep_producto_pendiente(p_id_orden integer, p_id_proveedor integer, p_id_producto integer, p_id_local_actual integer)
RETURNS TABLE (id_producto integer, codigo text, nombre text, unidad text, cantidad_solicitada numeric, cantidad_recibida numeric)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    p.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    ocd.cantidad_solicitada,
    COALESCE((
        SELECT SUM(frd.cantidad_recibida)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion = fr.id_factura_recepcion
        WHERE fr.id_orden_compra = oc.id_orden_compra
          AND fr.id_proveedor = p_id_proveedor
          AND frd.id_producto = p.id_producto
    ), 0) AS cantidad_recibida
FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
JOIN orden_compra_detalle ocd
    ON ocd.id_orden_compra = oc.id_orden_compra
JOIN producto p
    ON p.id_producto = ocd.id_producto
WHERE oc.id_orden_compra = p_id_orden
  AND p.id_producto = p_id_producto
  AND ocd.id_proveedor = p_id_proveedor
FOR UPDATE OF ocd
$$;

CREATE OR REPLACE FUNCTION public.recep_factura_duplicada(p_id_proveedor integer, p_numero_factura text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
    SELECT 1
    FROM factura_recepcion
    WHERE id_proveedor = p_id_proveedor
      AND UPPER(numero_factura) = UPPER(p_numero_factura)
)
$$;

CREATE OR REPLACE FUNCTION public.recep_crear_factura(p_id_orden integer, p_id_proveedor integer, p_numero_factura text, p_fecha_recepcion date, p_id_usuario integer)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO factura_recepcion (
    id_orden_compra,
    id_proveedor,
    numero_factura,
    fecha_recepcion,
    usuario_recepcion
) VALUES (
    p_id_orden,
    p_id_proveedor,
    p_numero_factura,
    p_fecha_recepcion,
    p_id_usuario
)
RETURNING id_factura_recepcion
$$;

CREATE OR REPLACE FUNCTION public.recep_crear_detalle(p_id_factura integer, p_id_producto integer, p_cantidad numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO factura_recepcion_detalle (
    id_factura_recepcion,
    id_producto,
    cantidad_recibida
) VALUES (
    p_id_factura,
    p_id_producto,
    p_cantidad
)
$$;

CREATE OR REPLACE FUNCTION public.recep_orden_pendiente(p_id_orden integer, p_id_local_actual integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
    SELECT 1
    FROM orden_compra_detalle ocd
    JOIN producto p
        ON p.id_producto = ocd.id_producto
    WHERE ocd.id_orden_compra = p_id_orden
      AND ocd.cantidad_solicitada > COALESCE((
          SELECT SUM(frd.cantidad_recibida)
          FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
          JOIN factura_recepcion_detalle frd
              ON frd.id_factura_recepcion = fr.id_factura_recepcion
          WHERE fr.id_orden_compra = ocd.id_orden_compra
            AND fr.id_proveedor = ocd.id_proveedor
            AND frd.id_producto = ocd.id_producto
      ), 0)
)
$$;

CREATE OR REPLACE FUNCTION public.recep_actualizar_estado(p_id_orden integer, p_estado text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE orden_compra
SET estado_orden_compra = p_estado
WHERE id_orden_compra = p_id_orden
$$;

CREATE OR REPLACE FUNCTION public.recep_historial(p_id_local_actual integer, p_fecha_desde date, p_fecha_hasta date, p_id_proveedor integer)
RETURNS TABLE (id_factura_recepcion integer, id_orden_compra integer, codigo_orden text, estado_orden_compra text, total_factura text, moneda text, numero_factura text, fecha_recepcion date, id_proveedor integer, proveedor text, recibido_por text, productos_recibidos bigint, cantidad_total numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    fr.id_factura_recepcion,
    fr.id_orden_compra,
    oc.codigo AS codigo_orden,
    oc.estado_orden_compra,
    fr.datos_factura->>'total' AS total_factura,
    fr.datos_factura->>'moneda' AS moneda,
    fr.numero_factura,
    fr.fecha_recepcion,
    fr.id_proveedor,
    pr.nombre AS proveedor,
    CONCAT_WS(
        ' ',
        u.nombres,
        u.apellido_paterno,
        u.apellido_materno
    ) AS recibido_por,
    COUNT(frd.id_factura_recepcion_detalle)
        AS productos_recibidos,
    COALESCE(SUM(frd.cantidad_recibida), 0)
        AS cantidad_total
FROM factura_recepcion fr
JOIN orden_compra oc
    ON oc.id_orden_compra = fr.id_orden_compra
JOIN proveedor pr
    ON pr.id_proveedor = fr.id_proveedor
JOIN usuario u
    ON u.id_usuario = fr.usuario_recepcion
JOIN factura_recepcion_detalle frd
    ON frd.id_factura_recepcion = fr.id_factura_recepcion
WHERE oc.id_local=p_id_local_actual AND (
    CAST(p_fecha_desde AS DATE) IS NULL
    OR fr.fecha_recepcion >= CAST(p_fecha_desde AS DATE)
)
  AND (
    CAST(p_fecha_hasta AS DATE) IS NULL
    OR fr.fecha_recepcion <= CAST(p_fecha_hasta AS DATE)
  )
  AND (
    CAST(p_id_proveedor AS INTEGER) IS NULL
    OR fr.id_proveedor = CAST(p_id_proveedor AS INTEGER)
  )
GROUP BY
    fr.id_factura_recepcion,
    oc.id_orden_compra,
    pr.id_proveedor,
    u.id_usuario
ORDER BY
    fr.fecha_recepcion DESC,
    fr.id_factura_recepcion DESC
$$;

CREATE OR REPLACE FUNCTION public.recep_orden_de_factura(p_id integer)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_orden_compra FROM factura_recepcion WHERE id_factura_recepcion=p_id
$$;

CREATE OR REPLACE FUNCTION public.recep_obtener_factura(p_id_factura integer, p_id_local_actual integer)
RETURNS TABLE (id_factura_recepcion integer, id_orden_compra integer, codigo_orden text, estado_orden_compra text, id_proveedor integer, proveedor text, numero_factura text, fecha_recepcion date, recibido_por text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    fr.id_factura_recepcion,
    fr.id_orden_compra,
    oc.codigo AS codigo_orden,
    oc.estado_orden_compra,
    fr.id_proveedor,
    pr.nombre AS proveedor,
    fr.numero_factura,
    fr.fecha_recepcion,
    CONCAT_WS(
        ' ',
        u.nombres,
        u.apellido_paterno,
        u.apellido_materno
    ) AS recibido_por
FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
JOIN (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
    ON oc.id_orden_compra = fr.id_orden_compra
JOIN proveedor pr
    ON pr.id_proveedor = fr.id_proveedor
JOIN usuario u
    ON u.id_usuario = fr.usuario_recepcion
WHERE fr.id_factura_recepcion = p_id_factura
$$;

CREATE OR REPLACE FUNCTION public.recep_detalles_factura(p_id_factura integer, p_id_local_actual integer)
RETURNS TABLE (id_factura_recepcion_detalle integer, id_producto integer, codigo text, nombre text, unidad text, cantidad_recibida numeric, cantidad_solicitada numeric, recibido_otras_facturas numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    frd.id_factura_recepcion_detalle,
    frd.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    frd.cantidad_recibida,
    ocd.cantidad_solicitada,
    COALESCE((
        SELECT SUM(otra.cantidad_recibida)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) otra_fr
        JOIN factura_recepcion_detalle otra
            ON otra.id_factura_recepcion =
               otra_fr.id_factura_recepcion
        WHERE otra_fr.id_orden_compra = fr.id_orden_compra
          AND otra.id_producto = frd.id_producto
          AND otra_fr.id_factura_recepcion <>
              fr.id_factura_recepcion
    ), 0) AS recibido_otras_facturas
FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
JOIN factura_recepcion_detalle frd
    ON frd.id_factura_recepcion = fr.id_factura_recepcion
JOIN producto p
    ON p.id_producto = frd.id_producto
JOIN orden_compra_detalle ocd
    ON ocd.id_orden_compra = fr.id_orden_compra
   AND ocd.id_producto = frd.id_producto
WHERE fr.id_factura_recepcion = p_id_factura
ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.recep_factura_duplicada_excepto(p_id_proveedor integer, p_numero_factura text, p_id_factura integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
    SELECT 1
    FROM factura_recepcion
    WHERE id_proveedor = p_id_proveedor
      AND UPPER(numero_factura) = UPPER(p_numero_factura)
      AND id_factura_recepcion <> p_id_factura
)
$$;

CREATE OR REPLACE FUNCTION public.recep_actualizar_factura(p_id_factura integer, p_numero_factura text, p_fecha_recepcion date)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE factura_recepcion
SET numero_factura = p_numero_factura,
    fecha_recepcion = p_fecha_recepcion
WHERE id_factura_recepcion = p_id_factura
$$;

CREATE OR REPLACE FUNCTION public.recep_actualizar_cantidad(p_id_detalle integer, p_cantidad numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE factura_recepcion_detalle
SET cantidad_recibida = p_cantidad
WHERE id_factura_recepcion_detalle = p_id_detalle
$$;

CREATE OR REPLACE FUNCTION public.recep_crear_historial(p_id_factura integer, p_numero_anterior text, p_numero_nuevo text, p_fecha_anterior date, p_fecha_nueva date, p_id_usuario integer, p_motivo text, p_observacion text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO factura_recepcion_historial (
    id_factura_recepcion,
    numero_factura_anterior,
    numero_factura_nuevo,
    fecha_recepcion_anterior,
    fecha_recepcion_nueva,
    usuario_correccion,
    motivo_correccion,
    observacion
) VALUES (
    p_id_factura,
    p_numero_anterior,
    p_numero_nuevo,
    p_fecha_anterior,
    p_fecha_nueva,
    p_id_usuario,
    p_motivo,
    p_observacion
)
RETURNING id_factura_recepcion_historial
$$;

CREATE OR REPLACE FUNCTION public.recep_crear_historial_detalle(p_id_historial integer, p_id_producto integer, p_cantidad_anterior numeric, p_cantidad_nueva numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO factura_recepcion_detalle_historial (
    id_factura_recepcion_historial,
    id_producto,
    cantidad_anterior,
    cantidad_nueva
) VALUES (
    p_id_historial,
    p_id_producto,
    p_cantidad_anterior,
    p_cantidad_nueva
)
$$;

CREATE OR REPLACE FUNCTION public.recep_totales_orden(p_id_orden integer, p_id_local_actual integer)
RETURNS TABLE (total_solicitado numeric, total_recibido numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    COALESCE((
        SELECT SUM(cantidad_solicitada)
        FROM orden_compra_detalle
        WHERE id_orden_compra = p_id_orden
    ), 0) AS total_solicitado,
    COALESCE((
        SELECT SUM(frd.cantidad_recibida)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion =
               fr.id_factura_recepcion
        WHERE fr.id_orden_compra = p_id_orden
    ), 0) AS total_recibido
$$;

CREATE OR REPLACE FUNCTION public.recep_bloquear_factura(p_id_factura integer, p_id_local_actual integer)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT fr.id_factura_recepcion
FROM factura_recepcion fr
JOIN orden_compra oc USING (id_orden_compra)
WHERE fr.id_factura_recepcion = p_id_factura AND oc.id_local = p_id_local_actual
FOR UPDATE OF fr
$$;

COMMIT;
