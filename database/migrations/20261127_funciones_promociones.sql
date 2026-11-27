BEGIN;

CREATE OR REPLACE FUNCTION public.promo_reposiciones_instaladas()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.promocion_reposicion') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.promo_formulario()
RETURNS TABLE (id_presentacion_venta integer, codigo text, nombre text, contenido numeric, unidad text, menaje text, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pv.id_presentacion_venta, ic.codigo, ic.nombre,
        pv.contenido, pv.unidad, m.nombre AS menaje, (pv.activo AND ic.activo) AS activo
        FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
        JOIN menaje m USING(id_menaje) ORDER BY ic.nombre,pv.contenido
$$;

CREATE OR REPLACE FUNCTION public.promo_bloquear_catalogo()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
LOCK TABLE promocion IN SHARE ROW EXCLUSIVE MODE
$$;

CREATE OR REPLACE FUNCTION public.promo_bloquear_promocion(p_id integer)
RETURNS TABLE (id_promocion integer, codigo text, nombre text, precio numeric, hora_inicio time without time zone, hora_fin time without time zone, activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_promocion, codigo, nombre, precio, hora_inicio, hora_fin, activo FROM promocion WHERE id_promocion=p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.promo_grupos_previos(p_id integer)
RETURNS TABLE (id_promocion_grupo integer, id_promocion integer, cantidad_elegir smallint, permite_repetir boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_promocion_grupo, id_promocion, cantidad_elegir, permite_repetir FROM promocion_grupo WHERE id_promocion=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_opciones_previas(p_id integer)
RETURNS TABLE (id_promocion_opcion integer, id_promocion_grupo integer, id_presentacion_venta integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT o.id_promocion_opcion, o.id_promocion_grupo, o.id_presentacion_venta FROM promocion_opcion o JOIN promocion_grupo g USING(id_promocion_grupo) WHERE g.id_promocion=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_reposiciones_previas(p_id integer)
RETURNS TABLE (id_promocion integer, id_presentacion_venta integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_promocion, id_presentacion_venta FROM promocion_reposicion WHERE id_promocion=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_nombre_existe(p_nombre text, p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM promocion WHERE lower(trim(nombre))=lower(p_nombre) AND id_promocion<>p_id)
$$;

CREATE OR REPLACE FUNCTION public.promo_bloquear_presentacion(p_id integer)
RETURNS TABLE (activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pv.activo AND ic.activo AS activo FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta) WHERE pv.id_presentacion_venta=p_id FOR SHARE OF pv,ic
$$;

CREATE OR REPLACE FUNCTION public.promo_actualizar(p_nombre text, p_precio numeric, p_inicio time without time zone, p_fin time without time zone, p_activo boolean, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE promocion SET nombre=p_nombre,precio=p_precio,hora_inicio=p_inicio,hora_fin=p_fin,activo=p_activo WHERE id_promocion=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_siguiente_codigo()
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 'P-' || lpad(numero, greatest(3, length(numero)), '0')
FROM (
    SELECT (coalesce(max(substring(codigo FROM 3)::bigint), 0) + 1)::text AS numero
    FROM promocion WHERE codigo ~ '^P-[0-9]+$'
) siguiente
$$;

CREATE OR REPLACE FUNCTION public.promo_crear(p_codigo text, p_nombre text, p_precio numeric, p_inicio time without time zone, p_fin time without time zone, p_activo boolean)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO promocion(codigo,nombre,precio,hora_inicio,hora_fin,activo) VALUES (p_codigo,p_nombre,p_precio,p_inicio,p_fin,p_activo) RETURNING id_promocion
$$;

CREATE OR REPLACE FUNCTION public.promo_eliminar_opciones(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM promocion_opcion WHERE id_promocion_grupo=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_eliminar_grupo(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM promocion_grupo WHERE id_promocion_grupo=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_crear_grupo(p_promo integer, p_elegir integer, p_repetir boolean)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO promocion_grupo(id_promocion,cantidad_elegir,permite_repetir) VALUES (p_promo,p_elegir,p_repetir) RETURNING id_promocion_grupo
$$;

CREATE OR REPLACE FUNCTION public.promo_actualizar_grupo(p_elegir integer, p_repetir boolean, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE promocion_grupo SET cantidad_elegir=p_elegir,permite_repetir=p_repetir WHERE id_promocion_grupo=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_quitar_opciones(p_id integer, p_opciones integer[])
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM promocion_opcion WHERE id_promocion_grupo=p_id AND NOT (id_presentacion_venta=ANY(p_opciones))
$$;

CREATE OR REPLACE FUNCTION public.promo_crear_opcion(p_grupo integer, p_pid integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO promocion_opcion(id_promocion_grupo,id_presentacion_venta) VALUES (p_grupo,p_pid) ON CONFLICT (id_promocion_grupo,id_presentacion_venta) DO NOTHING
$$;

CREATE OR REPLACE FUNCTION public.promo_eliminar_reposiciones(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM promocion_reposicion WHERE id_promocion=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_crear_reposicion(p_promo integer, p_pid integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO promocion_reposicion(id_promocion,id_presentacion_venta) VALUES (p_promo,p_pid)
$$;

CREATE OR REPLACE FUNCTION public.promo_buscar(p_id integer)
RETURNS TABLE (id_promocion integer, codigo text, nombre text, precio numeric, hora_inicio time without time zone, hora_fin time without time zone, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_promocion, codigo, nombre, precio, hora_inicio, hora_fin, activo FROM promocion WHERE id_promocion=p_id
$$;

CREATE OR REPLACE FUNCTION public.promo_listar()
RETURNS TABLE (id_promocion integer, codigo text, nombre text, precio numeric, hora_inicio time without time zone, hora_fin time without time zone, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    id_promocion,
    codigo,
    nombre,
    precio,
    hora_inicio,
    hora_fin,
    activo
FROM promocion
ORDER BY
    activo DESC,
    codigo ASC
$$;

CREATE OR REPLACE FUNCTION public.promo_listar_grupos()
RETURNS TABLE (id_promocion_grupo integer, id_promocion integer, cantidad_elegir smallint, permite_repetir boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    id_promocion_grupo,
    id_promocion,
    cantidad_elegir,
    permite_repetir
FROM promocion_grupo
ORDER BY
    id_promocion,
    id_promocion_grupo
$$;

CREATE OR REPLACE FUNCTION public.promo_listar_opciones()
RETURNS TABLE (id_promocion_opcion integer, id_promocion_grupo integer, id_presentacion_venta integer, id_item_carta integer, codigo_item text, item_carta text, tipo text, id_categoria_carta integer, categoria_carta text, contenido numeric, unidad text, precio_individual numeric, presentacion_activa boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    po.id_promocion_opcion,
    po.id_promocion_grupo,
    po.id_presentacion_venta,

    pv.id_item_carta,
    ic.codigo AS codigo_item,
    ic.nombre AS item_carta,
    ic.tipo,

    cc.id_categoria_carta,
    cc.nombre AS categoria_carta,

    pv.contenido,
    pv.unidad,
    pv.precio AS precio_individual,
    pv.activo AS presentacion_activa

FROM promocion_opcion AS po

INNER JOIN presentacion_venta AS pv
    ON pv.id_presentacion_venta =
        po.id_presentacion_venta

INNER JOIN item_carta AS ic
    ON ic.id_item_carta =
        pv.id_item_carta

INNER JOIN categoria_carta AS cc
    ON cc.id_categoria_carta =
        ic.id_categoria_carta

ORDER BY
    po.id_promocion_grupo,
    ic.nombre ASC
$$;

CREATE OR REPLACE FUNCTION public.promo_listar_reposiciones()
RETURNS TABLE (id_promocion integer, id_presentacion_venta integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_promocion,id_presentacion_venta
FROM promocion_reposicion
ORDER BY id_promocion,id_presentacion_venta
$$;

COMMIT;
