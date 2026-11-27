CREATE OR REPLACE FUNCTION public.clientes_actualizar_datos(
    p_id uuid, p_nombre varchar, p_email varchar, p_telefono varchar,
    p_direccion varchar, p_actualiza_direccion boolean
)
RETURNS TABLE (id_cliente uuid, nombre varchar, email varchar, telefono varchar, direccion varchar)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE public.cliente_comercial AS c
    SET nombre = coalesce(p_nombre, c.nombre), email = p_email, telefono = p_telefono,
        direccion = CASE WHEN p_actualiza_direccion THEN p_direccion ELSE c.direccion END
    WHERE c.id_cliente = p_id
    RETURNING c.id_cliente, c.nombre, c.email, c.telefono, c.direccion
$$;

REVOKE EXECUTE ON FUNCTION public.clientes_actualizar_datos(uuid,varchar,varchar,varchar,varchar,boolean) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT UPDATE (nombre) ON public.cliente_comercial TO multi;
        GRANT EXECUTE ON FUNCTION public.clientes_actualizar_datos(uuid,varchar,varchar,varchar,varchar,boolean) TO multi;
    END IF;
END
$$;
