BEGIN;

CREATE OR REPLACE FUNCTION public.carta_editor_categorias()
RETURNS TABLE (id_categoria_carta integer,nombre varchar,activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT id_categoria_carta, nombre, activo FROM categoria_carta ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_articulos()
RETURNS TABLE (id_item_carta integer,codigo varchar,nombre varchar,id_categoria_carta integer,tipo varchar,activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT id_item_carta, codigo, nombre, id_categoria_carta, tipo, activo FROM item_carta ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_bloquear_categorias()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    LOCK TABLE categoria_carta IN SHARE ROW EXCLUSIVE MODE
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_bloquear_articulos()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    LOCK TABLE item_carta IN SHARE ROW EXCLUSIVE MODE
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_bloquear_presentacion(p_id integer)
RETURNS TABLE (id_presentacion_venta integer,id_item_carta integer,id_menaje integer,contenido numeric,unidad varchar,precio numeric,activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT * FROM presentacion_venta WHERE id_presentacion_venta=p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_bloquear_articulo(p_id integer)
RETURNS TABLE (id_item_carta integer,codigo varchar,nombre varchar,id_categoria_carta integer,tipo varchar,activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT * FROM item_carta WHERE id_item_carta=p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_categoria_activa(p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS(SELECT 1 FROM categoria_carta WHERE id_categoria_carta=p_id AND activo)
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_articulo_nombre_existe(p_nombre text, p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS(SELECT 1 FROM item_carta WHERE lower(trim(nombre))=lower(p_nombre) AND id_item_carta<>p_id)
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_articulo_receta_multiple(p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS(SELECT 1 FROM receta r JOIN presentacion_venta pv USING(id_presentacion_venta)
            WHERE pv.id_item_carta=p_id AND (SELECT count(*) FROM receta_detalle d WHERE d.id_receta=r.id_receta)<>1)
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_reservar_codigo(p_id integer)
RETURNS TABLE (prefijo varchar,numero integer)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE categoria_carta SET siguiente_numero=siguiente_numero+1 WHERE id_categoria_carta=p_id AND activo RETURNING prefijo,siguiente_numero-1 AS numero
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_crear_articulo(p_codigo text, p_nombre text, p_categoria integer, p_tipo text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    INSERT INTO item_carta(codigo,nombre,id_categoria_carta,tipo,activo) VALUES (p_codigo,p_nombre,p_categoria,p_tipo,true) RETURNING id_item_carta
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_editar_articulo(p_nombre text, p_tipo text, p_categoria integer, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE item_carta SET nombre=p_nombre,tipo=p_tipo,id_categoria_carta=p_categoria WHERE id_item_carta=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_editar_presentacion(p_menaje integer, p_contenido numeric, p_unidad text, p_precio numeric, p_activo boolean, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE presentacion_venta SET id_menaje=p_menaje,contenido=p_contenido,unidad=p_unidad,precio=p_precio,activo=p_activo WHERE id_presentacion_venta=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_crear_presentacion(p_item integer, p_menaje integer, p_contenido numeric, p_unidad text, p_precio numeric, p_activo boolean)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    INSERT INTO presentacion_venta(id_item_carta,id_menaje,contenido,unidad,precio,activo) VALUES (p_item,p_menaje,p_contenido,p_unidad,p_precio,p_activo) RETURNING id_presentacion_venta
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_leer_articulo(p_id integer)
RETURNS TABLE (id_item_carta integer,codigo varchar,nombre varchar,id_categoria_carta integer,tipo varchar,activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT * FROM item_carta WHERE id_item_carta=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_leer_presentacion(p_id integer)
RETURNS TABLE (id_presentacion_venta integer,id_item_carta integer,id_menaje integer,contenido numeric,unidad varchar,precio numeric,activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT * FROM presentacion_venta WHERE id_presentacion_venta=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_editor_tipos()
RETURNS text[]
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT ARRAY(
        SELECT coincidencia[1]
        FROM pg_constraint c
        CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([^'']+)''::character varying', 'g') AS coincidencia
        WHERE c.conname = 'ck_item_carta_tipo' AND c.conrelid = 'public.item_carta'::regclass
    )
$$;

COMMIT;
