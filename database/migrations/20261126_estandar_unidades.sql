BEGIN;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute
                   WHERE attrelid = 'public.unidad_medida'::regclass
                     AND attname = 'estandar' AND NOT attisdropped) THEN
        ALTER TABLE public.unidad_medida ADD COLUMN estandar text;
        UPDATE public.unidad_medida
        SET estandar = CASE WHEN codigo_unece IS NULL THEN 'LOCAL' ELSE 'UNECE Rec. 20' END;
    END IF;
END $$;
COMMIT;
