ALTER TABLE public.integracion_consulta
    ADD COLUMN IF NOT EXISTS url varchar(2048),
    ADD COLUMN IF NOT EXISTS tipo varchar(15),
    ADD COLUMN IF NOT EXISTS id_local integer,
    ADD COLUMN IF NOT EXISTS estado varchar(15),
    ADD COLUMN IF NOT EXISTS intentos integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS ejecutar_en timestamptz,
    ADD COLUMN IF NOT EXISTS mensaje text,
    ADD COLUMN IF NOT EXISTS errores jsonb,
    ADD COLUMN IF NOT EXISTS cursor text;

ALTER TABLE public.integracion_solicitud
    ADD COLUMN IF NOT EXISTS consulta_id varchar(36) REFERENCES public.integracion_consulta(id);

CREATE INDEX IF NOT EXISTS ix_integracion_consulta_cola
    ON public.integracion_consulta (ejecutar_en, id) WHERE estado IN ('EN_COLA', 'REINTENTO');
CREATE INDEX IF NOT EXISTS ix_integracion_solicitud_consulta
    ON public.integracion_solicitud (consulta_id) WHERE consulta_id IS NOT NULL;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT UPDATE ON public.integracion_consulta TO multi;
    END IF;
END
$$;
