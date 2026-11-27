CREATE TABLE IF NOT EXISTS public.integracion_clave (
    id_local integer PRIMARY KEY REFERENCES public.local(id_local),
    huella varchar(64) NOT NULL UNIQUE,
    creado_por integer NOT NULL REFERENCES public.usuario(id_usuario),
    creado_en timestamptz NOT NULL DEFAULT now()
);
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT, INSERT, UPDATE ON public.integracion_clave TO multi;
    END IF;
END
$$;
