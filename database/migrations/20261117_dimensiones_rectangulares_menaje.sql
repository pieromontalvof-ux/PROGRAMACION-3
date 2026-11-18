ALTER TABLE public.menaje_medida
    ADD COLUMN IF NOT EXISTS largo_cm numeric(10,3),
    ADD COLUMN IF NOT EXISTS ancho_cm numeric(10,3),
    ADD COLUMN IF NOT EXISTS origen_medidas varchar(16);
ALTER TABLE public.menaje_medida DROP CONSTRAINT IF EXISTS ck_menaje_rectangular;
ALTER TABLE public.menaje_medida ADD CONSTRAINT ck_menaje_rectangular CHECK (
    (largo_cm IS NULL OR (largo_cm>0 AND largo_cm<=10000))
    AND (ancho_cm IS NULL OR (ancho_cm>0 AND ancho_cm<=10000))
    AND (origen_medidas IS NULL OR origen_medidas IN ('DEMO','REGISTRADO'))
);
