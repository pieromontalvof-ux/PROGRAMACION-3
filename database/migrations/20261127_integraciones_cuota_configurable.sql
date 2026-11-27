CREATE OR REPLACE FUNCTION public.integracion_consumir_lectura(p_clave varchar, p_maximo integer)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    WITH cuota AS (
        INSERT INTO public.integracion_lectura_cuota AS q (id_clave, ventana, solicitudes)
        VALUES (p_clave, date_trunc('minute', statement_timestamp()), 1)
        ON CONFLICT (id_clave) DO UPDATE SET
            ventana = EXCLUDED.ventana,
            solicitudes = CASE WHEN q.ventana = EXCLUDED.ventana THEN q.solicitudes + 1 ELSE 1 END
        WHERE q.ventana < EXCLUDED.ventana
            OR (q.ventana = EXCLUDED.ventana AND q.solicitudes < p_maximo)
        RETURNING 1
    )
    SELECT EXISTS (SELECT 1 FROM cuota)
$$;

REVOKE EXECUTE ON FUNCTION public.integracion_consumir_lectura(varchar, integer) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT EXECUTE ON FUNCTION public.integracion_consumir_lectura(varchar, integer) TO multi;
    END IF;
END
$$;
