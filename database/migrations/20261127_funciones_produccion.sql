BEGIN;

CREATE OR REPLACE FUNCTION public.produccion_listar_subproductos()
RETURNS TABLE (id_subproducto integer, codigo text, nombre text, rendimiento numeric, unidad text, activo boolean, instruccion text, total_ingredientes bigint, ingredientes jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    s.id_subproducto,
    s.codigo,
    s.nombre,
    s.rendimiento,
    s.unidad,
    s.activo,
    s.instruccion,

    COUNT(sd.id_producto)
        AS total_ingredientes,

    COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'id_producto', p.id_producto,
                'codigo', p.codigo,
                'producto', p.nombre,
                'cantidad', sd.cantidad,
                'unidad', sd.unidad,
                'activo', p.activo
            )
            ORDER BY p.nombre
        ) FILTER (
            WHERE sd.id_producto IS NOT NULL
        ),
        '[]'::JSONB
    ) AS ingredientes

FROM subproducto AS s

LEFT JOIN subproducto_detalle AS sd
    ON sd.id_subproducto = s.id_subproducto

LEFT JOIN producto AS p
    ON p.id_producto = sd.id_producto

GROUP BY
    s.id_subproducto,
    s.codigo,
    s.nombre,
    s.rendimiento,
    s.unidad,
    s.activo

ORDER BY s.nombre ASC
$$;

CREATE OR REPLACE FUNCTION public.produccion_listar_grupos_salsa()
RETURNS TABLE (id_grupo_salsa integer, id_presentacion_venta integer, cantidad_maxima smallint, activo boolean, id_item_carta integer, codigo_item text, item_carta text, categoria_carta text, contenido numeric, unidad_presentacion text, precio numeric, total_opciones bigint, opciones jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    gs.id_grupo_salsa,
    gs.id_presentacion_venta,
    gs.cantidad_maxima,
    gs.activo,

    ic.id_item_carta,
    ic.codigo AS codigo_item,
    ic.nombre AS item_carta,
    cc.nombre AS categoria_carta,

    pv.contenido,
    pv.unidad AS unidad_presentacion,
    pv.precio,

    COUNT(gso.id_grupo_salsa)
        AS total_opciones,

    COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'id_producto',
                    gso.id_producto,

                'codigo',
                    p.codigo,

                'producto',
                    CASE
                        WHEN gso.id_producto IS NULL
                            THEN 'Sin salsa'
                        ELSE p.nombre
                    END,

                'cantidad',
                    gso.cantidad,

                'unidad',
                    gso.unidad,

                'es_sin_salsa',
                    CASE
                        WHEN gso.id_producto IS NULL
                            THEN TRUE
                        ELSE FALSE
                    END
            )
            ORDER BY
                (
                    gso.id_producto IS NULL
                ),
                p.nombre
        )
        FILTER (
            WHERE gso.id_grupo_salsa IS NOT NULL
        ),
        '[]'::JSONB
    ) AS opciones

FROM grupo_salsa AS gs

INNER JOIN presentacion_venta AS pv
    ON pv.id_presentacion_venta =
        gs.id_presentacion_venta

INNER JOIN item_carta AS ic
    ON ic.id_item_carta =
        pv.id_item_carta

INNER JOIN categoria_carta AS cc
    ON cc.id_categoria_carta =
        ic.id_categoria_carta

LEFT JOIN grupo_salsa_opcion AS gso
    ON gso.id_grupo_salsa =
        gs.id_grupo_salsa

LEFT JOIN producto AS p
    ON p.id_producto =
        gso.id_producto

GROUP BY
    gs.id_grupo_salsa,
    gs.id_presentacion_venta,
    gs.cantidad_maxima,
    gs.activo,
    ic.id_item_carta,
    ic.codigo,
    ic.nombre,
    cc.nombre,
    pv.contenido,
    pv.unidad,
    pv.precio

ORDER BY ic.nombre ASC
$$;

CREATE OR REPLACE FUNCTION public.produccion_productos_formulario()
RETURNS TABLE (id integer, codigo text, nombre text, unidad text, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto AS id,codigo,nombre,unidad,activo FROM producto ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.produccion_bloquear_catalogo()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock(hashtext('subproducto_catalogo'))
$$;

CREATE OR REPLACE FUNCTION public.produccion_subproducto_bloqueado(p_id integer)
RETURNS TABLE (codigo text, unidad text, activo boolean, nombre text, rendimiento numeric, instruccion text, id_subproducto integer)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT codigo, unidad, activo, nombre, rendimiento, instruccion, id_subproducto FROM subproducto WHERE id_subproducto=p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.produccion_ingredientes(p_id integer)
RETURNS TABLE (id_producto integer, cantidad numeric, unidad text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto,cantidad,unidad FROM subproducto_detalle WHERE id_subproducto=p_id
$$;

CREATE OR REPLACE FUNCTION public.produccion_en_recetas_activas(p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM receta_detalle d JOIN receta r USING(id_receta)
WHERE d.id_subproducto=p_id AND r.activo)
$$;

CREATE OR REPLACE FUNCTION public.produccion_nombre_existe(p_nombre text, p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM subproducto
            WHERE lower(btrim(nombre))=lower(p_nombre)
              AND (p_id IS NULL OR id_subproducto<>p_id))
$$;

CREATE OR REPLACE FUNCTION public.produccion_actualizar_subproducto(p_nombre text, p_rendimiento numeric, p_instruccion text, p_activo boolean, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE subproducto SET nombre=p_nombre,rendimiento=p_rendimiento,
                instruccion=p_instruccion,activo=p_activo WHERE id_subproducto=p_id
$$;

CREATE OR REPLACE FUNCTION public.produccion_siguiente_codigo()
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 'SP-' || lpad(numero, greatest(3, length(numero)), '0')
FROM (SELECT (coalesce(max(substring(codigo FROM 4)::bigint),0)+1)::text AS numero
                FROM subproducto WHERE codigo ~ '^SP-[0-9]+$') siguiente
$$;

CREATE OR REPLACE FUNCTION public.produccion_crear_subproducto(p_codigo text, p_nombre text, p_rendimiento numeric, p_unidad text, p_instruccion text, p_activo boolean)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO subproducto(codigo,nombre,rendimiento,unidad,instruccion,activo)
                VALUES(p_codigo,p_nombre,p_rendimiento,p_unidad,p_instruccion,p_activo)
                RETURNING id_subproducto
$$;

CREATE OR REPLACE FUNCTION public.produccion_eliminar_ingredientes(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM subproducto_detalle WHERE id_subproducto=p_id
$$;

CREATE OR REPLACE FUNCTION public.produccion_crear_ingrediente(p_subproducto integer, p_producto integer, p_cantidad numeric, p_unidad text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO subproducto_detalle(id_subproducto,id_producto,cantidad,unidad)
                VALUES(p_subproducto,p_producto,p_cantidad,p_unidad)
$$;

COMMIT;
