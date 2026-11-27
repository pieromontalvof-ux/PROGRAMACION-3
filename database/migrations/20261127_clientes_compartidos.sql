BEGIN;

-- Primero se comprueba la unicidad en toda la base. Si otra instalacion contiene
-- documentos duplicados, se revierte la migracion y se conservan todas sus filas.
CREATE UNIQUE INDEX IF NOT EXISTS uq_cliente_comercial_documento_global
    ON public.cliente_comercial (tipo_documento, upper(btrim(numero_documento)))
    WHERE nullif(btrim(numero_documento), '') IS NOT NULL;

DROP INDEX IF EXISTS public.uq_cliente_comercial_documento_local;
CREATE INDEX IF NOT EXISTS ix_cliente_comercial_nombre
    ON public.cliente_comercial (nombre, id_cliente);

COMMENT ON TABLE public.cliente_comercial IS 'Directorio compartido por todas las sedes.';
COMMENT ON COLUMN public.cliente_comercial.id_local IS 'Sede de origen del alta. El cliente puede usarse en todos los locales.';

CREATE OR REPLACE FUNCTION public.clientes_buscar(
    p_local integer, p_q text, p_patron text, p_limite integer, p_offset integer
)
RETURNS TABLE (
    id_cliente uuid, tipo_persona varchar, tipo_documento varchar, numero_documento varchar,
    nombre varchar, direccion varchar, email varchar, telefono varchar
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT c.id_cliente, c.tipo_persona, c.tipo_documento, c.numero_documento,
           c.nombre, c.direccion, c.email, c.telefono
    FROM public.cliente_comercial c
    WHERE p_q = '' OR upper(btrim(c.numero_documento)) = upper(p_q)
       OR c.nombre ILIKE p_patron ESCAPE chr(92)
    ORDER BY c.nombre, c.id_cliente
    LIMIT p_limite OFFSET p_offset
$$;

CREATE OR REPLACE FUNCTION public.clientes_obtener(p_local integer, p_id text)
RETURNS TABLE (
    id_cliente uuid, tipo_persona varchar, tipo_documento varchar, numero_documento varchar,
    nombre varchar, direccion varchar, email varchar, telefono varchar
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT c.id_cliente, c.tipo_persona, c.tipo_documento, c.numero_documento,
           c.nombre, c.direccion, c.email, c.telefono
    FROM public.cliente_comercial c
    WHERE c.id_cliente = p_id::uuid
$$;

CREATE OR REPLACE FUNCTION public.clientes_actualizar_contacto(
    p_local integer, p_id text, p_email text, p_telefono text
)
RETURNS TABLE (id_cliente uuid, email varchar, telefono varchar)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE public.cliente_comercial AS c
    SET email = p_email, telefono = p_telefono
    WHERE c.id_cliente = p_id::uuid
    RETURNING c.id_cliente, c.email, c.telefono
$$;

COMMIT;
