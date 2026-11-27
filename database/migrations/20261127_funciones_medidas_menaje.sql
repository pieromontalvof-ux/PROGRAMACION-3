BEGIN;

CREATE OR REPLACE FUNCTION public.carta_medidas_menaje(p_id integer)
RETURNS TABLE (
    id_menaje integer, nombre varchar, activo boolean, capacidad numeric,
    unidad_capacidad varchar, diametro_cm numeric, altura_cm numeric,
    largo_cm numeric, ancho_cm numeric, origen_medidas varchar
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT m.id_menaje, m.nombre, m.activo, d.capacidad, d.unidad_capacidad,
           d.diametro_cm, d.altura_cm, d.largo_cm, d.ancho_cm, d.origen_medidas
    FROM public.menaje m
    LEFT JOIN public.menaje_medida d USING (id_menaje)
    WHERE p_id IS NULL OR m.id_menaje = p_id
    ORDER BY m.nombre
$$;

CREATE OR REPLACE FUNCTION public.carta_bloquear_menaje(p_id integer, p_edicion boolean)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
BEGIN
    IF p_edicion THEN
        PERFORM 1 FROM public.menaje m WHERE m.id_menaje = p_id FOR UPDATE;
    ELSE
        PERFORM 1 FROM public.menaje m WHERE m.id_menaje = p_id FOR SHARE;
    END IF;
    RETURN FOUND;
END;
$$;

COMMIT;
