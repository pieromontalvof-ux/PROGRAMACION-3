BEGIN;

ALTER TABLE public.integracion_clave
    ADD COLUMN IF NOT EXISTS id varchar(36),
    ADD COLUMN IF NOT EXISTS nombre varchar(80) NOT NULL DEFAULT 'Clave anterior',
    ADD COLUMN IF NOT EXISTS origen varchar(120) NOT NULL DEFAULT 'API de entrada',
    ADD COLUMN IF NOT EXISTS revocado_en timestamptz,
    ADD COLUMN IF NOT EXISTS revocado_por integer REFERENCES public.usuario(id_usuario);

UPDATE public.integracion_clave SET id = gen_random_uuid()::text WHERE id IS NULL;
ALTER TABLE public.integracion_clave ALTER COLUMN id SET NOT NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT FROM pg_constraint
        WHERE conrelid = 'public.integracion_clave'::regclass AND contype = 'p'
          AND pg_get_constraintdef(oid) = 'PRIMARY KEY (id_local)'
    ) THEN
        ALTER TABLE public.integracion_clave DROP CONSTRAINT integracion_clave_pkey;
        ALTER TABLE public.integracion_clave ADD PRIMARY KEY (id);
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS ix_integracion_clave_local_creacion
    ON public.integracion_clave (id_local, creado_en DESC, id);

COMMIT;
