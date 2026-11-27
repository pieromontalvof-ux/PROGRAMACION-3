BEGIN;

CREATE OR REPLACE FUNCTION public.catalogos_stock_local_asignado(p_usuario integer, p_local integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
                    SELECT 1 FROM usuario_local ul
                    JOIN local l ON l.id_local = ul.id_local
                    WHERE ul.id_usuario = p_usuario AND ul.id_local = p_local
                      AND ul.estado_registro = 1 AND l.estado_registro = 1
                )
$$;

CREATE OR REPLACE FUNCTION public.catalogos_stock_limites(p_local integer)
RETURNS TABLE (id_producto integer,codigo varchar,nombre varchar,categoria varchar,unidad varchar,stock_minimo numeric,stock_maximo numeric,activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto, p.codigo, p.nombre, c.nombre AS categoria,
               p.unidad, COALESCE(sl.stock_minimo, 0) AS stock_minimo,
               sl.stock_maximo, p.activo
        FROM producto p
        JOIN categoria_producto c ON c.id_categoria = p.id_categoria
        LEFT JOIN producto_stock_local sl
          ON sl.id_producto = p.id_producto AND sl.id_local = p_local
        ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.catalogos_stock_limites_bloqueados(p_local integer, p_id integer)
RETURNS TABLE (id_producto integer,codigo varchar,stock_minimo numeric,stock_maximo numeric)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto, p.codigo, COALESCE(sl.stock_minimo, 0) AS stock_minimo,
                   sl.stock_maximo
            FROM producto p
            LEFT JOIN producto_stock_local sl
              ON sl.id_producto = p.id_producto AND sl.id_local = p_local
            WHERE p.id_producto = p_id FOR UPDATE OF p
$$;

CREATE OR REPLACE FUNCTION public.catalogos_stock_guardar_limites(p_id integer, p_local integer, p_minimo numeric, p_maximo numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO producto_stock_local (id_producto, id_local, stock_minimo, stock_maximo)
            VALUES (p_id, p_local, p_minimo, p_maximo)
            ON CONFLICT (id_producto, id_local) DO UPDATE
            SET stock_minimo = EXCLUDED.stock_minimo, stock_maximo = EXCLUDED.stock_maximo
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.perfiles'::regclass
                   AND attname='administra_limites_stock' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN administra_limites_stock boolean NOT NULL DEFAULT false;
        UPDATE public.perfiles SET administra_limites_stock=true WHERE id_perfil=2;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogos_stock_perfil_autorizado(p_perfil integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (SELECT FROM public.perfiles p
      WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.administra_limites_stock)
$$;

COMMIT;
