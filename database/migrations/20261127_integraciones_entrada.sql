CREATE TABLE IF NOT EXISTS public.integracion_solicitud (
    id varchar(36) PRIMARY KEY,
    id_local integer NOT NULL REFERENCES public.local(id_local),
    origen varchar(120) NOT NULL,
    tipo varchar(15) NOT NULL CHECK (tipo IN ('clientes', 'proveedores')),
    clave varchar(128) NOT NULL,
    datos jsonb NOT NULL,
    estado varchar(15) NOT NULL CHECK (estado IN ('PENDIENTE', 'AGREGADO', 'DESCARTADO', 'ERROR')),
    recibido_en timestamptz NOT NULL DEFAULT now(),
    revisado_en timestamptz,
    revisado_por integer REFERENCES public.usuario(id_usuario),
    id_registro varchar(36),
    mensaje text,
    UNIQUE (id_local, origen, tipo, clave)
);
ALTER TABLE public.integracion_solicitud ADD COLUMN IF NOT EXISTS eventos jsonb NOT NULL DEFAULT '[]'::jsonb;
CREATE INDEX IF NOT EXISTS ix_integracion_solicitud_estado ON public.integracion_solicitud (estado, recibido_en DESC, id DESC);
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT, INSERT, UPDATE ON public.integracion_solicitud TO multi;
    END IF;
END
$$;
