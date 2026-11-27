BEGIN;

CREATE OR REPLACE FUNCTION public.carta_admin_categoria(p_id integer)
RETURNS TABLE (id_categoria_carta integer,nombre varchar,prefijo varchar,siguiente_numero integer,activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT * FROM categoria_carta WHERE id_categoria_carta=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_articulos(p_id integer)
RETURNS TABLE (id_item_carta integer,codigo varchar,id_categoria_carta integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT id_item_carta, codigo, id_categoria_carta FROM item_carta WHERE id_categoria_carta=p_id ORDER BY id_item_carta
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_categoria_duplicada(p_id integer, p_nombre text, p_prefijo text)
RETURNS SETOF integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT 1 FROM categoria_carta WHERE id_categoria_carta<>p_id AND (lower(trim(nombre))=lower(p_nombre) OR upper(prefijo)=p_prefijo)
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_siguiente_numero(p_patron text)
RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT coalesce(max(split_part(codigo, '-', 2)::bigint),0)+1 FROM item_carta WHERE codigo ~ p_patron
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_crear_categoria(p_nombre text, p_prefijo text, p_numero integer)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    INSERT INTO categoria_carta(nombre,prefijo,siguiente_numero,activo) VALUES (p_nombre,p_prefijo,p_numero,true) RETURNING id_categoria_carta
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_editar_categoria(p_nombre text, p_prefijo text, p_numero integer, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE categoria_carta SET nombre=p_nombre, prefijo=p_prefijo, siguiente_numero=p_numero WHERE id_categoria_carta=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_categoria_activa(p_id integer)
RETURNS SETOF integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT 1 FROM categoria_carta WHERE id_categoria_carta=p_id AND activo
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_reasignar_articulos(p_destino integer, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE item_carta SET id_categoria_carta=p_destino WHERE id_categoria_carta=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_estado_categoria(p_activo boolean, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE categoria_carta SET activo=p_activo WHERE id_categoria_carta=p_id
$$;

COMMIT;
