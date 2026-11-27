DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conrelid = 'public.salon_cobro'::regclass AND conname = 'ck_salon_cobro_documento'
    ) THEN
        ALTER TABLE public.salon_cobro DROP CONSTRAINT IF EXISTS salon_cobro_check;
        ALTER TABLE public.salon_cobro ALTER COLUMN documento TYPE varchar(30);
        ALTER TABLE public.salon_cobro ADD CONSTRAINT ck_salon_cobro_documento CHECK (
            (tipo = 'BOLETA' AND documento = '' AND cliente = '') OR
            (tipo = 'BOLETA_ELECTRONICA' AND documento ~ '^[A-Za-z0-9]{1,30}$' AND length(btrim(cliente)) > 0) OR
            (tipo = 'FACTURA' AND documento ~ '^[0-9]{11}$' AND length(btrim(cliente)) > 0)
        );
    END IF;
END
$$;
