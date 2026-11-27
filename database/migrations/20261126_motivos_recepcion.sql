BEGIN;

DO $$
BEGIN
    IF to_regclass('public.recepcion_motivo_correccion') IS NULL THEN
        CREATE TABLE public.recepcion_motivo_correccion (
            codigo text PRIMARY KEY CHECK (codigo <> '' AND codigo = upper(btrim(codigo))),
            etiqueta text NOT NULL,
            orden integer NOT NULL DEFAULT 0,
            activo boolean NOT NULL DEFAULT true
        );
        INSERT INTO public.recepcion_motivo_correccion (codigo, etiqueta, orden) VALUES
            ('ERROR_DIGITACION', 'Error de digitación', 1),
            ('MAL_CONTADO', 'Mal contado', 2),
            ('PRODUCTO_DANADO', 'Producto dañado', 3),
            ('PRODUCTO_RECHAZADO', 'Producto rechazado', 4),
            ('ERROR_FACTURA', 'Error en factura', 5),
            ('OTRO', 'Otro', 6);
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
            GRANT SELECT ON public.recepcion_motivo_correccion TO multi;
        END IF;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid = 'public.recepcion_motivo_correccion'::regclass
                     AND conname = 'ck_recepcion_motivo_codigo_longitud') THEN
        ALTER TABLE public.recepcion_motivo_correccion
            ADD CONSTRAINT ck_recepcion_motivo_codigo_longitud CHECK (char_length(codigo) <= 100);
    END IF;
END $$;

COMMIT;
