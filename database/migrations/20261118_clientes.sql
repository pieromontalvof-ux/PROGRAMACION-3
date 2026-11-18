BEGIN;
CREATE TABLE IF NOT EXISTS public.cliente_comercial (
    id_cliente uuid PRIMARY KEY,
    id_local integer NOT NULL REFERENCES public.local(id_local),
    tipo_persona varchar(8) NOT NULL DEFAULT 'NATURAL' CHECK (tipo_persona IN ('NATURAL','JURIDICA')),
    tipo_documento varchar(9) CHECK (tipo_documento IN ('DNI','RUC','CE','PASAPORTE')),
    numero_documento varchar(30),
    nombre varchar(200) NOT NULL CHECK (btrim(nombre) <> ''),
    direccion varchar(300),
    email varchar(200),
    telefono varchar(40),
    creado_en timestamptz NOT NULL DEFAULT now(),
    CHECK (numero_documento IS NULL OR tipo_documento IS NOT NULL),
    CHECK (tipo_persona <> 'JURIDICA' OR tipo_documento IS NULL OR tipo_documento = 'RUC')
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_cliente_comercial_documento_local
    ON public.cliente_comercial(id_local,tipo_documento,numero_documento)
    WHERE numero_documento IS NOT NULL AND numero_documento <> '';
CREATE INDEX IF NOT EXISTS ix_cliente_comercial_local_nombre ON public.cliente_comercial(id_local,nombre);
COMMENT ON TABLE public.cliente_comercial IS 'Clientes del restaurante, registrados manualmente por local; sin validacion externa de identidad.';
ALTER TABLE salon_cobro ADD COLUMN IF NOT EXISTS id_cliente UUID REFERENCES cliente_comercial(id_cliente);
COMMIT;
