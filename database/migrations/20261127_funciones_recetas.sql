BEGIN;

CREATE OR REPLACE FUNCTION public.receta_presentacion_bloqueada(p_id integer)
RETURNS TABLE (id_presentacion_venta integer, id_item_carta integer, id_menaje integer, contenido numeric, unidad text, precio numeric, activo boolean, tipo text)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pv.id_presentacion_venta, pv.id_item_carta, pv.id_menaje, pv.contenido, pv.unidad, pv.precio, pv.activo, ic.tipo FROM presentacion_venta pv
JOIN item_carta ic USING(id_item_carta)
WHERE pv.id_presentacion_venta=p_id FOR UPDATE OF ic, pv
$$;

CREATE OR REPLACE FUNCTION public.receta_presentacion_ocupada(p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM receta WHERE id_presentacion_venta=p_id)
$$;

CREATE OR REPLACE FUNCTION public.receta_actualizar(p_instrucciones text, p_activo boolean, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE receta SET instrucciones=p_instrucciones,activo=p_activo WHERE id_receta=p_id
$$;

CREATE OR REPLACE FUNCTION public.receta_crear(p_presentacion integer, p_instrucciones text, p_activo boolean)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO receta(id_presentacion_venta,instrucciones,activo)
VALUES (p_presentacion,p_instrucciones,p_activo) RETURNING id_receta
$$;

CREATE OR REPLACE FUNCTION public.receta_definicion_check(p_nombre text)
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conname = p_nombre AND connamespace = 'public'::regnamespace
$$;

CREATE OR REPLACE FUNCTION public.receta_categorias()
RETURNS TABLE (id_categoria_carta integer, nombre text, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_categoria_carta, nombre, activo FROM categoria_carta ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.receta_items()
RETURNS TABLE (id_item_carta integer, codigo text, nombre text, id_categoria_carta integer, tipo text, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_item_carta, codigo, nombre, id_categoria_carta, tipo, activo FROM item_carta ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.receta_presentaciones_disponibles()
RETURNS TABLE (id_presentacion_venta integer, id_item_carta integer, id_menaje integer, contenido numeric, unidad text, activo boolean, id_receta integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pv.id_presentacion_venta, pv.id_item_carta, pv.id_menaje,
       pv.contenido, pv.unidad, pv.activo, r.id_receta
FROM presentacion_venta pv LEFT JOIN receta r USING (id_presentacion_venta)
WHERE r.id_receta IS NULL
ORDER BY pv.id_item_carta, pv.contenido
$$;

CREATE OR REPLACE FUNCTION public.receta_subproductos()
RETURNS TABLE (id integer, codigo text, nombre text, unidad text, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_subproducto AS id, codigo, nombre, unidad, activo FROM subproducto ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.receta_buscar_bloqueada(p_id integer)
RETURNS TABLE (id_receta integer, id_presentacion_venta integer, instrucciones text, activo boolean, id_item_carta integer, contenido numeric, unidad text, id_menaje integer, tipo text, nombre text, id_categoria_carta integer)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT r.id_receta, r.id_presentacion_venta, r.instrucciones, r.activo, pv.id_item_carta, pv.contenido, pv.unidad, pv.id_menaje,
       ic.tipo, ic.nombre, ic.id_categoria_carta
FROM receta r JOIN presentacion_venta pv USING(id_presentacion_venta)
JOIN item_carta ic USING(id_item_carta)
WHERE r.id_receta = p_id FOR UPDATE OF r, pv, ic
$$;

CREATE OR REPLACE FUNCTION public.receta_detalles(p_id integer)
RETURNS TABLE (id_receta_detalle integer, id_receta integer, tipo_componente text, id_producto integer, id_subproducto integer, cantidad numeric, unidad text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_receta_detalle, id_receta, tipo_componente, id_producto, id_subproducto, cantidad, unidad FROM receta_detalle WHERE id_receta=p_id ORDER BY id_receta_detalle
$$;

CREATE OR REPLACE FUNCTION public.receta_grupo_bloqueado(p_id integer)
RETURNS TABLE (id_grupo_salsa integer, id_presentacion_venta integer, cantidad_maxima smallint, permite_repetir boolean, activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_grupo_salsa, id_presentacion_venta, cantidad_maxima, permite_repetir, activo FROM grupo_salsa WHERE id_presentacion_venta=p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.receta_opciones_grupo(p_id integer)
RETURNS TABLE (id_grupo_salsa_opcion integer, id_grupo_salsa integer, id_producto integer, cantidad numeric, unidad text, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_grupo_salsa_opcion, id_grupo_salsa, id_producto, cantidad, unidad, activo FROM grupo_salsa_opcion WHERE id_grupo_salsa=p_id ORDER BY id_producto
$$;

CREATE OR REPLACE FUNCTION public.receta_bloquear_subproducto(p_id integer)
RETURNS TABLE (id integer, codigo text, nombre text, unidad text, activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_subproducto AS id, codigo, nombre, unidad, activo FROM subproducto WHERE id_subproducto=p_id FOR SHARE
$$;

CREATE OR REPLACE FUNCTION public.receta_bloquear_producto(p_id integer)
RETURNS TABLE (id integer, codigo text, nombre text, unidad text, activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto AS id, codigo, nombre, unidad, activo FROM producto WHERE id_producto=p_id FOR SHARE
$$;

CREATE OR REPLACE FUNCTION public.receta_eliminar_detalles(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM receta_detalle WHERE id_receta=p_id
$$;

CREATE OR REPLACE FUNCTION public.receta_crear_detalle(p_receta integer, p_tipo text, p_producto integer, p_subproducto integer, p_cantidad numeric, p_unidad text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO receta_detalle (id_receta, tipo_componente, id_producto, id_subproducto, cantidad, unidad)
VALUES (p_receta, p_tipo, p_producto, p_subproducto, p_cantidad, p_unidad)
$$;

CREATE OR REPLACE FUNCTION public.receta_desactivar_grupo(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE grupo_salsa SET activo=FALSE WHERE id_presentacion_venta=p_id
$$;

CREATE OR REPLACE FUNCTION public.receta_guardar_grupo(p_id integer, p_maximo integer, p_repetir boolean)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO grupo_salsa (id_presentacion_venta, cantidad_maxima, permite_repetir, activo)
VALUES (p_id, p_maximo, p_repetir, TRUE)
ON CONFLICT (id_presentacion_venta) DO UPDATE
SET cantidad_maxima=EXCLUDED.cantidad_maxima, permite_repetir=EXCLUDED.permite_repetir, activo=TRUE
RETURNING id_grupo_salsa
$$;

CREATE OR REPLACE FUNCTION public.receta_desactivar_opciones(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE grupo_salsa_opcion SET activo=FALSE WHERE id_grupo_salsa=p_id
$$;

CREATE OR REPLACE FUNCTION public.receta_guardar_opcion(p_grupo integer, p_producto integer, p_cantidad numeric, p_unidad text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO grupo_salsa_opcion (id_grupo_salsa,id_producto,cantidad,unidad,activo)
VALUES (p_grupo,p_producto,p_cantidad,p_unidad,TRUE)
ON CONFLICT (id_grupo_salsa,id_producto) DO UPDATE
SET cantidad=EXCLUDED.cantidad, unidad=EXCLUDED.unidad, activo=TRUE
$$;

CREATE OR REPLACE FUNCTION public.receta_listar()
RETURNS TABLE (id_receta integer, id_presentacion_venta integer, instrucciones text, activo boolean, id_item_carta integer, codigo_item text, item_carta text, tipo_item text, id_categoria_carta integer, categoria_carta text, contenido numeric, unidad_presentacion text, precio numeric, id_menaje integer, total_componentes bigint, componentes jsonb, id_grupo_salsa integer, cantidad_maxima smallint, permite_repetir boolean, grupo_salsa_activo boolean, opciones_salsa jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    r.id_receta,
    r.id_presentacion_venta,
    r.instrucciones,
    r.activo,

    ic.id_item_carta,
    ic.codigo AS codigo_item,
    ic.nombre AS item_carta,
    ic.tipo AS tipo_item,
    ic.id_categoria_carta,
    cc.nombre AS categoria_carta,

    pv.contenido,
    pv.unidad AS unidad_presentacion,
    pv.precio,
    pv.id_menaje,

    (
        SELECT COUNT(*)
        FROM receta_detalle rd_conteo
        WHERE rd_conteo.id_receta = r.id_receta
    ) AS total_componentes,

    COALESCE(
        (
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_receta_detalle', rd.id_receta_detalle,
                    'tipo_componente', rd.tipo_componente,
                    'id_producto', rd.id_producto,
                    'producto_codigo', p.codigo,
                    'producto_nombre', p.nombre,
                    'id_subproducto', rd.id_subproducto,
                    'subproducto_codigo', sp.codigo,
                    'subproducto_nombre', sp.nombre,
                    'cantidad', rd.cantidad,
                    'unidad', rd.unidad
                )
                ORDER BY
                    rd.tipo_componente,
                    COALESCE(p.nombre, sp.nombre)
            )
            FROM receta_detalle rd
            LEFT JOIN producto p
                ON p.id_producto = rd.id_producto
            LEFT JOIN subproducto sp
                ON sp.id_subproducto = rd.id_subproducto
            WHERE rd.id_receta = r.id_receta
        ),
        '[]'::JSONB
    ) AS componentes,

    gs.id_grupo_salsa,
    gs.cantidad_maxima,
    gs.permite_repetir,
    gs.activo AS grupo_salsa_activo,

    COALESCE(
        (
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_grupo_salsa_opcion', gso.id_grupo_salsa_opcion,
                    'id_producto', producto_salsa.id_producto,
                    'codigo', producto_salsa.codigo,
                    'nombre', producto_salsa.nombre,
                    'cantidad', gso.cantidad,
                    'unidad', gso.unidad,
                    'activo', gso.activo
                )
                ORDER BY producto_salsa.nombre
            )
            FROM grupo_salsa_opcion gso
            INNER JOIN producto producto_salsa
                ON producto_salsa.id_producto = gso.id_producto
            WHERE gso.id_grupo_salsa = gs.id_grupo_salsa
              AND gso.activo = TRUE
        ),
        '[]'::JSONB
    ) AS opciones_salsa

FROM receta r

INNER JOIN presentacion_venta pv
    ON pv.id_presentacion_venta = r.id_presentacion_venta

INNER JOIN item_carta ic
    ON ic.id_item_carta = pv.id_item_carta

INNER JOIN categoria_carta cc
    ON cc.id_categoria_carta = ic.id_categoria_carta

LEFT JOIN grupo_salsa gs
    ON gs.id_presentacion_venta = pv.id_presentacion_venta
   AND gs.activo = TRUE

ORDER BY ic.nombre, pv.contenido
$$;

COMMIT;
