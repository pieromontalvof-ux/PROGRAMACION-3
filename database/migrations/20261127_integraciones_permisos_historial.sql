ALTER TABLE public.integracion_clave
    ADD COLUMN IF NOT EXISTS permiso varchar(15) NOT NULL DEFAULT 'ambos'
        CHECK (permiso IN ('clientes', 'proveedores', 'ambos')),
    ADD COLUMN IF NOT EXISTS vence_en timestamptz;

CREATE TABLE IF NOT EXISTS public.integracion_consulta (
    id varchar(36) PRIMARY KEY,
    host varchar(253) NOT NULL,
    usuario integer NOT NULL REFERENCES public.usuario(id_usuario),
    fecha timestamptz NOT NULL DEFAULT now(),
    codigo integer NOT NULL,
    resumen jsonb
);

CREATE INDEX IF NOT EXISTS ix_integracion_consulta_fecha
    ON public.integracion_consulta (fecha DESC, id DESC);

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT, INSERT ON public.integracion_consulta TO multi;
    END IF;
END
$$;
