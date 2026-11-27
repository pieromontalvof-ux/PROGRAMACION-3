ALTER TABLE public.integracion_clave
    DROP CONSTRAINT IF EXISTS integracion_clave_permiso_check;
ALTER TABLE public.integracion_clave
    ADD CONSTRAINT integracion_clave_permiso_check
    CHECK (permiso IN ('clientes', 'proveedores', 'ambos', 'leer_clientes'));

CREATE TABLE IF NOT EXISTS public.integracion_lectura_cuota (
    id_clave varchar(36) PRIMARY KEY REFERENCES public.integracion_clave(id) ON DELETE CASCADE,
    ventana timestamptz NOT NULL,
    solicitudes integer NOT NULL
);

CREATE OR REPLACE FUNCTION public.integracion_consumir_lectura(p_clave varchar)
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
            OR (q.ventana = EXCLUDED.ventana AND q.solicitudes < 60)
        RETURNING 1
    )
    SELECT EXISTS (SELECT 1 FROM cuota)
$$;

CREATE OR REPLACE FUNCTION public.integracion_leer_clientes(p_cursor uuid, p_limite integer)
RETURNS TABLE (
    id_cliente uuid, nombre varchar, tipo_persona varchar, tipo_documento varchar,
    numero_documento varchar, email varchar, telefono varchar, direccion varchar
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT c.id_cliente, c.nombre, c.tipo_persona, c.tipo_documento,
           c.numero_documento, c.email, c.telefono, c.direccion
    FROM public.cliente_comercial c
    WHERE p_cursor IS NULL OR c.id_cliente > p_cursor
    ORDER BY c.id_cliente
    LIMIT p_limite
$$;

REVOKE EXECUTE ON FUNCTION public.integracion_consumir_lectura(varchar), public.integracion_leer_clientes(uuid, integer) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT, INSERT, UPDATE ON public.integracion_lectura_cuota TO multi;
        GRANT EXECUTE ON FUNCTION public.integracion_consumir_lectura(varchar),
            public.integracion_leer_clientes(uuid, integer) TO multi;
    END IF;
END
$$;
