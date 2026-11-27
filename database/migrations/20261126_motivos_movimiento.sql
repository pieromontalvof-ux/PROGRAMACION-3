BEGIN;

DO $$
BEGIN
    IF to_regclass('public.movimiento_motivo') IS NULL THEN
        CREATE TABLE public.movimiento_motivo (
            codigo varchar(30) PRIMARY KEY CHECK (codigo <> '' AND codigo = upper(btrim(codigo))),
            etiqueta text NOT NULL,
            tipo_movimiento varchar(10) NOT NULL CHECK (tipo_movimiento IN ('ENTRADA', 'SALIDA')),
            requiere_local boolean NOT NULL DEFAULT false,
            requiere_proveedor boolean NOT NULL DEFAULT false,
            registrable boolean NOT NULL DEFAULT true,
            activo boolean NOT NULL DEFAULT true,
            orden integer NOT NULL DEFAULT 0,
            motivo_recepcion varchar(30) REFERENCES public.movimiento_motivo(codigo),
            CHECK (NOT (requiere_local AND requiere_proveedor)),
            CHECK (motivo_recepcion IS NULL OR (tipo_movimiento = 'SALIDA' AND
                (requiere_local OR requiere_proveedor)))
        );
        INSERT INTO public.movimiento_motivo
            (codigo, etiqueta, tipo_movimiento, requiere_local, requiere_proveedor, registrable, orden, motivo_recepcion)
        VALUES
            ('PRESTAMO_RECIBIDO', 'Préstamo recibido', 'ENTRADA', true, false, false, 1, NULL),
            ('MERMA', 'Merma', 'SALIDA', false, false, true, 2, NULL),
            ('PRESTAMO_ENTREGADO', 'Préstamo entregado', 'SALIDA', true, false, true, 3, 'PRESTAMO_RECIBIDO'),
            ('DEVOLUCION_PROVEEDOR', 'Devolución a proveedor', 'SALIDA', false, true, true, 4, 'REPOSICION_PROVEEDOR'),
            ('REPOSICION_PROVEEDOR', 'Reposición de proveedor', 'ENTRADA', false, true, false, 5, NULL),
            ('VENTA_SALON', 'Venta de salón', 'SALIDA', false, false, false, 6, NULL);
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
            GRANT SELECT ON public.movimiento_motivo TO multi;
        END IF;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.validar_movimiento_motivo()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.movimiento_motivo AS regla
        WHERE regla.codigo = NEW.motivo_movimiento
          AND regla.tipo_movimiento = NEW.tipo_movimiento
          AND regla.requiere_local = (NEW.local_relacionado IS NOT NULL)
          AND regla.requiere_proveedor = (NEW.id_proveedor IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'El motivo no coincide con el tipo, local o proveedor del movimiento'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgrelid = 'public.movimiento_inventario'::regclass
                     AND tgname = 'tr_validar_movimiento_motivo') THEN
        ALTER TABLE public.movimiento_inventario
            DROP CONSTRAINT IF EXISTS ck_movimiento_motivo,
            DROP CONSTRAINT IF EXISTS ck_movimiento_coherencia;
        CREATE TRIGGER tr_validar_movimiento_motivo
            BEFORE INSERT OR UPDATE OF motivo_movimiento, tipo_movimiento, local_relacionado, id_proveedor
            ON public.movimiento_inventario
            FOR EACH ROW EXECUTE FUNCTION public.validar_movimiento_motivo();
    END IF;
END $$;

COMMIT;
