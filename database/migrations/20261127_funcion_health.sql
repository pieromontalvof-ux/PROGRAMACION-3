BEGIN;

CREATE OR REPLACE FUNCTION public.health_estado_base()
RETURNS TABLE (base_datos name, usuario name, total_tablas bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT current_database(), current_user,
           (SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname='public')
$$;

COMMIT;
