BEGIN;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.perfiles'::regclass
                   AND attname = 'acceso_todos_locales' AND NOT attisdropped) THEN
        ALTER TABLE public.perfiles ADD COLUMN acceso_todos_locales boolean NOT NULL DEFAULT false;
        -- Conservar la excepcion del administrador de las instalaciones existentes.
        UPDATE public.perfiles SET acceso_todos_locales = true WHERE id_perfil = 1;
    END IF;
END $$;
COMMIT;
