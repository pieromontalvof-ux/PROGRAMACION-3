BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.perfiles'::regclass
                   AND attname='accede_directorio_clientes' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN accede_directorio_clientes boolean NOT NULL DEFAULT false;
        UPDATE public.perfiles SET accede_directorio_clientes=true WHERE id_perfil IN (1,2,3);
    END IF;
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.perfiles'::regclass
                   AND attname='accede_clientes_salon' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN accede_clientes_salon boolean NOT NULL DEFAULT false;
        UPDATE public.perfiles SET accede_clientes_salon=true WHERE id_perfil IN (2,3);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.clientes_perfil_autorizado(p_perfil integer, p_salon boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (
        SELECT FROM public.perfiles p WHERE p.id_perfil=p_perfil AND p.estado_registro=1
        AND CASE WHEN p_salon THEN p.accede_clientes_salon ELSE p.accede_directorio_clientes END
    )
$$;

CREATE OR REPLACE FUNCTION public.clientes_directorio_disponible()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT to_regclass('public.cliente_comercial') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.clientes_buscar(
    p_local integer, p_q text, p_patron text, p_limite integer, p_offset integer
)
RETURNS TABLE (
    id_cliente uuid, tipo_persona varchar, tipo_documento varchar, numero_documento varchar,
    nombre varchar, direccion varchar, email varchar, telefono varchar
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT c.id_cliente,c.tipo_persona,c.tipo_documento,c.numero_documento,
           c.nombre,c.direccion,c.email,c.telefono
    FROM public.cliente_comercial c
    WHERE c.id_local=p_local AND (p_q='' OR c.numero_documento=p_q OR c.nombre ILIKE p_patron ESCAPE chr(92))
    ORDER BY c.nombre,c.id_cliente LIMIT p_limite OFFSET p_offset
$$;

CREATE OR REPLACE FUNCTION public.clientes_obtener(p_local integer, p_id text)
RETURNS TABLE (
    id_cliente uuid, tipo_persona varchar, tipo_documento varchar, numero_documento varchar,
    nombre varchar, direccion varchar, email varchar, telefono varchar
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT c.id_cliente,c.tipo_persona,c.tipo_documento,c.numero_documento,
           c.nombre,c.direccion,c.email,c.telefono
    FROM public.cliente_comercial c WHERE c.id_local=p_local AND c.id_cliente=p_id::uuid
$$;

CREATE OR REPLACE FUNCTION public.clientes_crear(
    p_id text, p_local integer, p_persona text, p_documento text, p_numero text,
    p_nombre text, p_direccion text, p_email text, p_telefono text
)
RETURNS void LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    INSERT INTO public.cliente_comercial
        (id_cliente,id_local,tipo_persona,tipo_documento,numero_documento,nombre,direccion,email,telefono)
    VALUES (p_id::uuid,p_local,p_persona,p_documento,p_numero,p_nombre,p_direccion,p_email,p_telefono)
$$;

COMMIT;
