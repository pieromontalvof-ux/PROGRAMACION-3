BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.perfiles'::regclass
                   AND attname='requiere_puesto_activo' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN requiere_puesto_activo boolean NOT NULL DEFAULT false;
        UPDATE public.perfiles SET requiere_puesto_activo=true WHERE id_perfil=4;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.perfiles'::regclass
                   AND attname='puede_cambiar_local' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN puede_cambiar_local boolean NOT NULL DEFAULT false;
        UPDATE public.perfiles SET puede_cambiar_local=true WHERE id_perfil IN (2,3,4);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.auth_perfil_requiere_puesto(p_perfil integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (
        SELECT FROM public.perfiles p
        WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.requiere_puesto_activo
    )
$$;

CREATE OR REPLACE FUNCTION public.auth_perfil_puede_cambiar_local(p_perfil integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (
        SELECT FROM public.perfiles p
        WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.puede_cambiar_local
    )
$$;

COMMIT;
