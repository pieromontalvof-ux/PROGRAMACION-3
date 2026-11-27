ALTER TABLE public.integracion_solicitud DROP CONSTRAINT IF EXISTS integracion_solicitud_estado_check;
ALTER TABLE public.integracion_solicitud ADD CONSTRAINT integracion_solicitud_estado_check
    CHECK (estado IN ('PENDIENTE', 'AGREGADO', 'ACTUALIZADO', 'YA_REGISTRADO', 'DESCARTADO', 'ERROR'));

CREATE OR REPLACE FUNCTION public.clientes_por_documento(p_tipo text, p_numero text)
RETURNS TABLE (id_cliente uuid, tipo_persona varchar, tipo_documento varchar, numero_documento varchar,
               nombre varchar, direccion varchar, email varchar, telefono varchar)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT c.id_cliente, c.tipo_persona, c.tipo_documento, c.numero_documento,
           c.nombre, c.direccion, c.email, c.telefono
    FROM public.cliente_comercial c
    WHERE c.tipo_documento = p_tipo AND upper(btrim(c.numero_documento)) = upper(btrim(p_numero))
      AND nullif(btrim(c.numero_documento), '') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.clientes_bloquear_integracion(p_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT true FROM public.cliente_comercial WHERE id_cliente = p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.clientes_actualizar_integracion(p_id uuid, p_datos jsonb)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE public.cliente_comercial c
    SET nombre = p_datos->>'nombre', tipo_persona = p_datos->>'tipo_persona',
        tipo_documento = p_datos->>'tipo_documento', numero_documento = p_datos->>'numero_documento',
        direccion = p_datos->>'direccion', email = p_datos->>'email', telefono = p_datos->>'telefono'
    WHERE c.id_cliente = p_id
    RETURNING c.id_cliente
$$;

REVOKE EXECUTE ON FUNCTION public.clientes_por_documento(text,text),
    public.clientes_bloquear_integracion(uuid), public.clientes_actualizar_integracion(uuid,jsonb) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT UPDATE (tipo_persona, tipo_documento, numero_documento) ON public.cliente_comercial TO multi;
        GRANT EXECUTE ON FUNCTION public.clientes_por_documento(text,text),
            public.clientes_bloquear_integracion(uuid), public.clientes_actualizar_integracion(uuid,jsonb) TO multi;
    END IF;
END
$$;
