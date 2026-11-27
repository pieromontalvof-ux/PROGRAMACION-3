BEGIN;

CREATE OR REPLACE FUNCTION public.clientes_actualizar_contacto(
    p_local integer, p_id text, p_email text, p_telefono text,
    p_direccion text, p_actualiza_direccion boolean
)
RETURNS TABLE (id_cliente uuid, email varchar, telefono varchar, direccion varchar)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE public.cliente_comercial AS c
    SET email = p_email, telefono = p_telefono,
        direccion = CASE WHEN p_actualiza_direccion THEN p_direccion ELSE c.direccion END
    WHERE c.id_cliente = p_id::uuid
    RETURNING c.id_cliente, c.email, c.telefono, c.direccion
$$;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT UPDATE (direccion) ON public.cliente_comercial TO multi;
    END IF;
END
$$;

COMMIT;
