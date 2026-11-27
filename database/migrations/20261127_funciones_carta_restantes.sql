BEGIN;

CREATE OR REPLACE FUNCTION public.carta_menajes_detallados()
RETURNS TABLE (id_menaje integer,nombre varchar,activo boolean,capacidad numeric,unidad_capacidad varchar,diametro_cm numeric,altura_cm numeric,largo_cm numeric,ancho_cm numeric,origen_medidas varchar,total_presentaciones bigint,presentaciones_activas bigint,presentaciones_inactivas bigint,total_items bigint,items jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT
            m.id_menaje,
            m.nombre,
            m.activo,
            md.capacidad,md.unidad_capacidad,md.diametro_cm,md.altura_cm,md.largo_cm,md.ancho_cm,md.origen_medidas,

            COUNT(pv.id_presentacion_venta)
                AS total_presentaciones,

            COUNT(pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = TRUE)
                AS presentaciones_activas,

            COUNT(pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = FALSE)
                AS presentaciones_inactivas,

            COUNT(DISTINCT pv.id_item_carta)
                AS total_items,

            COALESCE(
                JSONB_AGG(DISTINCT ic.nombre)
                    FILTER (
                        WHERE ic.id_item_carta IS NOT NULL
                    ),
                '[]'::JSONB
            ) AS items

        FROM menaje AS m
        LEFT JOIN menaje_medida md ON md.id_menaje=m.id_menaje

        LEFT JOIN presentacion_venta AS pv
            ON pv.id_menaje = m.id_menaje

        LEFT JOIN item_carta AS ic
            ON ic.id_item_carta = pv.id_item_carta

        GROUP BY
            m.id_menaje,
            md.id_menaje,
            m.nombre,
            m.activo

        ORDER BY m.nombre ASC
$$;

CREATE OR REPLACE FUNCTION public.carta_presentaciones_detalladas()
RETURNS TABLE (id_presentacion_venta integer,id_item_carta integer,codigo_item varchar,item varchar,tipo varchar,id_categoria_carta integer,categoria varchar,id_menaje integer,menaje varchar,contenido numeric,unidad varchar,precio numeric,activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT
            pv.id_presentacion_venta,
            pv.id_item_carta,
            ic.codigo AS codigo_item,
            ic.nombre AS item,
            ic.tipo,
            ic.id_categoria_carta,
            cc.nombre AS categoria,
            pv.id_menaje,
            m.nombre AS menaje,
            pv.contenido,
            pv.unidad,
            pv.precio,
            pv.activo
        FROM presentacion_venta AS pv
        INNER JOIN item_carta AS ic
            ON ic.id_item_carta = pv.id_item_carta
        INNER JOIN categoria_carta AS cc
            ON cc.id_categoria_carta =
                ic.id_categoria_carta
        INNER JOIN menaje AS m
            ON m.id_menaje = pv.id_menaje
        ORDER BY
            cc.nombre ASC,
            ic.nombre ASC,
            pv.contenido ASC,
            pv.precio ASC
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_bloquear()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    LOCK TABLE menaje IN SHARE ROW EXCLUSIVE MODE
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_tiene_presentaciones(p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS(SELECT 1 FROM presentacion_venta WHERE id_menaje=p_id)
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_nombre_existe(p_nombre text, p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS(SELECT 1 FROM menaje WHERE lower(trim(nombre))=lower(p_nombre) AND id_menaje<>p_id)
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_crear(p_nombre text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    INSERT INTO menaje(nombre,activo) VALUES (p_nombre,true) RETURNING id_menaje
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_editar(p_nombre text, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE menaje SET nombre=p_nombre WHERE id_menaje=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_guardar_medidas(p_id integer, p_capacidad numeric, p_unidad_capacidad text, p_diametro_cm numeric, p_altura_cm numeric, p_largo_cm numeric, p_ancho_cm numeric, p_origen text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    INSERT INTO menaje_medida(id_menaje,capacidad,unidad_capacidad,diametro_cm,altura_cm,largo_cm,ancho_cm,origen_medidas)
                VALUES(p_id,p_capacidad,p_unidad_capacidad,p_diametro_cm,p_altura_cm,p_largo_cm,p_ancho_cm,p_origen)
                ON CONFLICT(id_menaje) DO UPDATE SET capacidad=EXCLUDED.capacidad,
                unidad_capacidad=EXCLUDED.unidad_capacidad,diametro_cm=EXCLUDED.diametro_cm,altura_cm=EXCLUDED.altura_cm,
                largo_cm=EXCLUDED.largo_cm,ancho_cm=EXCLUDED.ancho_cm,origen_medidas=EXCLUDED.origen_medidas
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_estado(p_activo boolean, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE menaje SET activo=p_activo WHERE id_menaje=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_borrar_medidas(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    DELETE FROM menaje_medida WHERE id_menaje=p_id
$$;

CREATE OR REPLACE FUNCTION public.carta_admin_menaje_eliminar(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    DELETE FROM menaje WHERE id_menaje=p_id
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.perfiles'::regclass
                   AND attname='administra_catalogos_carta' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN administra_catalogos_carta boolean NOT NULL DEFAULT false;
        UPDATE public.perfiles SET administra_catalogos_carta=true WHERE id_perfil=1;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.carta_admin_perfil_autorizado(p_perfil integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (SELECT FROM public.perfiles p WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.administra_catalogos_carta)
$$;

COMMIT;
