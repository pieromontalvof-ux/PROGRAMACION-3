BEGIN;

CREATE OR REPLACE FUNCTION public.clientes_actualizar_contacto(
    p_local integer, p_id text, p_email text, p_telefono text
)
RETURNS TABLE (id_cliente uuid, email varchar, telefono varchar)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE public.cliente_comercial AS c
    SET email = p_email, telefono = p_telefono
    WHERE c.id_local = p_local AND c.id_cliente = p_id::uuid
    RETURNING c.id_cliente, c.email, c.telefono
$$;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT UPDATE (email, telefono) ON public.cliente_comercial TO multi;
    END IF;
END
$$;

COMMIT;
