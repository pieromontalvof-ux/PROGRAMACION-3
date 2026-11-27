BEGIN;

CREATE OR REPLACE FUNCTION public.mov_productos_activos()
RETURNS TABLE (id_producto integer, codigo text, nombre text, unidad text, id_categoria integer, categoria text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    p.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    p.id_categoria,
    cp.nombre AS categoria
FROM producto p
JOIN categoria_producto cp
    ON cp.id_categoria = p.id_categoria
WHERE p.activo = TRUE
  AND cp.activo = TRUE
ORDER BY cp.nombre, p.nombre
$$;

CREATE OR REPLACE FUNCTION public.mov_proveedores_activos()
RETURNS TABLE (id_proveedor integer, nombre text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_proveedor, nombre
FROM proveedor
WHERE activo = TRUE
ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.mov_producto_activo(p_id_producto integer)
RETURNS TABLE (id_producto integer, codigo text, nombre text, unidad text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto, codigo, nombre, unidad
FROM producto
WHERE id_producto = p_id_producto
  AND activo = TRUE
$$;

CREATE OR REPLACE FUNCTION public.mov_proveedor_activo(p_id_proveedor integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
    SELECT 1
    FROM proveedor
    WHERE id_proveedor = p_id_proveedor
      AND activo = TRUE
)
$$;

CREATE OR REPLACE FUNCTION public.mov_bloquear_codigo()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock(
    hashtext('movimiento_inventario_codigo')
)
$$;

CREATE OR REPLACE FUNCTION public.mov_siguiente_numero()
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT COALESCE(
    MAX(
        CASE
            WHEN codigo ~ '^MI-[0-9]+$'
            THEN SUBSTRING(
                codigo FROM 4
            )::INTEGER
            ELSE 0
        END
    ),
    0
) + 1
FROM movimiento_inventario
$$;

CREATE OR REPLACE FUNCTION public.mov_crear_cabecera(p_id_local_actual integer, p_codigo text, p_tipo_movimiento text, p_motivo_movimiento text, p_fecha_movimiento date, p_id_usuario integer, p_local_relacionado text, p_id_proveedor integer, p_observacion text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO movimiento_inventario (
    id_local,
    codigo,
    tipo_movimiento,
    motivo_movimiento,
    fecha_movimiento,
    usuario_registro,
    local_relacionado,
    id_proveedor,
    observacion
)
VALUES (
    p_id_local_actual,
    p_codigo,
    p_tipo_movimiento,
    p_motivo_movimiento,
    p_fecha_movimiento,
    p_id_usuario,
    p_local_relacionado,
    p_id_proveedor,
    p_observacion
)
RETURNING id_movimiento_inventario
$$;

CREATE OR REPLACE FUNCTION public.mov_crear_detalle(p_id_movimiento integer, p_id_producto integer, p_cantidad numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO movimiento_inventario_detalle (
    id_movimiento_inventario,
    id_producto,
    cantidad
)
VALUES (
    p_id_movimiento,
    p_id_producto,
    p_cantidad
)
$$;

CREATE OR REPLACE FUNCTION public.mov_buscar_cabecera(p_id_local_actual integer, p_id_movimiento integer)
RETURNS TABLE (id_movimiento_inventario integer, codigo text, tipo_movimiento text, motivo_movimiento text, fecha_movimiento date, local_relacionado text, id_proveedor integer, proveedor text, observacion text, registrado_por text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    mi.id_movimiento_inventario,
    mi.codigo,
    mi.tipo_movimiento,
    mi.motivo_movimiento,
    mi.fecha_movimiento,
    mi.local_relacionado,
    mi.id_proveedor,
    pr.nombre AS proveedor,
    mi.observacion,
    CONCAT_WS(
        ' ',
        u.nombres,
        u.apellido_paterno,
        u.apellido_materno
    ) AS registrado_por
FROM (SELECT * FROM movimiento_inventario WHERE id_local=p_id_local_actual) mi
JOIN usuario u
    ON u.id_usuario = mi.usuario_registro
LEFT JOIN proveedor pr
    ON pr.id_proveedor = mi.id_proveedor
WHERE mi.id_movimiento_inventario = p_id_movimiento
$$;

CREATE OR REPLACE FUNCTION public.mov_listar_detalles(p_id_movimiento integer)
RETURNS TABLE (id_producto integer, codigo text, nombre text, unidad text, cantidad numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    p.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    mid.cantidad
FROM movimiento_inventario_detalle mid
JOIN producto p
    ON p.id_producto = mid.id_producto
WHERE mid.id_movimiento_inventario = p_id_movimiento
ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.mov_locales_destino(p_id_local_actual integer)
RETURNS TABLE (id_local integer, nombre text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_local,nombre FROM local WHERE estado_registro=1 AND id_local<>p_id_local_actual ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.mov_seguimiento_instalado()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.movimiento_seguimiento') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.mov_destino_bloqueado(p_id integer)
RETURNS TABLE (id_local integer, nombre text)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_local,nombre FROM local WHERE id_local=p_id AND estado_registro=1 FOR SHARE
$$;

CREATE OR REPLACE FUNCTION public.mov_registrar_salida(p_id integer, p_destino integer, p_estado text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO movimiento_seguimiento (id_movimiento, id_local_destino, estado) VALUES (p_id,p_destino,p_estado)
$$;

CREATE OR REPLACE FUNCTION public.mov_listar_seguimiento(p_local integer)
RETURNS TABLE (id integer, codigo text, fecha date, id_local integer, id_local_destino integer, estado text, motivo text, origen text, destino text, proveedor text, observacion text, registrado_por text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT m.id_movimiento_inventario AS id, m.codigo,m.fecha_movimiento AS fecha,
  m.id_local,s.id_local_destino,s.estado,m.motivo_movimiento AS motivo,
  o.nombre AS origen,d.nombre AS destino,p.nombre AS proveedor,m.observacion,
  concat_ws(' ',u.nombres,u.apellido_paterno) AS registrado_por
FROM movimiento_seguimiento s JOIN movimiento_inventario m ON m.id_movimiento_inventario=s.id_movimiento
JOIN local o ON o.id_local=m.id_local LEFT JOIN local d ON d.id_local=s.id_local_destino
LEFT JOIN proveedor p ON p.id_proveedor=m.id_proveedor JOIN usuario u ON u.id_usuario=m.usuario_registro
WHERE m.id_local=p_local OR s.id_local_destino=p_local ORDER BY m.id_movimiento_inventario DESC
$$;

CREATE OR REPLACE FUNCTION public.mov_detalles_seguimiento(p_id integer)
RETURNS TABLE (id_producto integer, codigo text, nombre text, unidad text, cantidad numeric, recibido numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,d.cantidad,
  COALESCE((SELECT sum(rd.cantidad) FROM movimiento_reintegro r
    JOIN movimiento_inventario_detalle rd ON rd.id_movimiento_inventario=r.id_movimiento
    WHERE r.id_salida=p_id AND rd.id_producto=d.id_producto),0) AS recibido
FROM movimiento_inventario_detalle d JOIN producto p USING(id_producto)
WHERE d.id_movimiento_inventario=p_id ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.mov_recepciones(p_id integer)
RETURNS TABLE (codigo text, guia_proveedor text, fecha text, nombre text, unidad text, cantidad double precision)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT m.codigo,r.guia_proveedor,m.fecha_movimiento::text AS fecha,
    p.nombre,p.unidad,d.cantidad::float AS cantidad
FROM movimiento_reintegro r JOIN movimiento_inventario m ON m.id_movimiento_inventario=r.id_movimiento
JOIN movimiento_inventario_detalle d ON d.id_movimiento_inventario=m.id_movimiento_inventario
JOIN producto p USING(id_producto) WHERE r.id_salida=p_id ORDER BY r.id_movimiento,p.nombre
$$;

CREATE OR REPLACE FUNCTION public.mov_salida_bloqueada(p_id integer, p_local integer)
RETURNS TABLE (id_local integer, id_proveedor integer, codigo text, id_local_destino integer, estado text, motivo_recepcion text)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT m.id_local,m.id_proveedor,m.codigo,s.id_local_destino,s.estado,motivo.motivo_recepcion FROM movimiento_seguimiento s
JOIN movimiento_inventario m ON m.id_movimiento_inventario=s.id_movimiento
LEFT JOIN public.movimiento_motivo motivo ON motivo.codigo=m.motivo_movimiento
WHERE s.id_movimiento=p_id AND (m.id_local=p_local OR s.id_local_destino=p_local)
FOR UPDATE OF s
$$;

CREATE OR REPLACE FUNCTION public.mov_guia_registrada(p_id integer, p_guia text)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 1 FROM movimiento_reintegro WHERE id_salida=p_id AND guia_proveedor=p_guia
$$;

CREATE OR REPLACE FUNCTION public.mov_cantidades(p_id integer)
RETURNS TABLE (id_producto integer, cantidad numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto,cantidad FROM movimiento_inventario_detalle WHERE id_movimiento_inventario=p_id
$$;

CREATE OR REPLACE FUNCTION public.mov_cantidades_recibidas(p_id integer)
RETURNS TABLE (id_producto integer, cantidad numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT d.id_producto,sum(d.cantidad) FROM movimiento_reintegro r
            JOIN movimiento_inventario_detalle d ON d.id_movimiento_inventario=r.id_movimiento
            WHERE r.id_salida=p_id GROUP BY d.id_producto
$$;

CREATE OR REPLACE FUNCTION public.mov_registrar_reintegro(p_id integer, p_salida integer, p_guia text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO movimiento_reintegro(id_movimiento,id_salida,guia_proveedor) VALUES (p_id,p_salida,p_guia)
$$;

CREATE OR REPLACE FUNCTION public.mov_actualizar_seguimiento(p_estado text, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE movimiento_seguimiento SET estado=p_estado WHERE id_movimiento=p_id
$$;

COMMIT;
