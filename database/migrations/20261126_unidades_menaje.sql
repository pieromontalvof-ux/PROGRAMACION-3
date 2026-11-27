BEGIN;
DO $$
BEGIN
    IF to_regclass('public.menaje_unidad_capacidad') IS NULL THEN
        CREATE TABLE public.menaje_unidad_capacidad (
            codigo varchar(16) PRIMARY KEY,
            nombre text NOT NULL,
            factor numeric NOT NULL CHECK (factor > 0),
            visible boolean NOT NULL DEFAULT true,
            orden integer NOT NULL DEFAULT 0,
            alias text
        );
        INSERT INTO public.menaje_unidad_capacidad VALUES
            ('MLT','mL',1,true,1,'ML'),
            ('LTR','L',1000,true,2,'L'),
            ('FLOZ_US','Onzas líquidas (oz)',29.5735295625,true,3,NULL),
            ('FLOZ_UK','fl oz (imperiales)',28.4130625,false,4,NULL);
        ALTER TABLE public.menaje_medida DROP CONSTRAINT IF EXISTS ck_menaje_medidas;
        ALTER TABLE public.menaje_medida
          ADD CONSTRAINT fk_menaje_unidad_capacidad FOREIGN KEY (unidad_capacidad)
            REFERENCES public.menaje_unidad_capacidad(codigo),
          ADD CONSTRAINT ck_menaje_medidas CHECK (
            ((capacidad IS NULL AND unidad_capacidad IS NULL) OR
             (capacidad IS NOT NULL AND capacidad > 0 AND capacidad <= 1000000 AND unidad_capacidad IS NOT NULL))
            AND (diametro_cm IS NULL OR (diametro_cm > 0 AND diametro_cm <= 10000))
            AND (altura_cm IS NULL OR (altura_cm > 0 AND altura_cm <= 10000)));
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
            GRANT SELECT ON public.menaje_unidad_capacidad TO multi;
        END IF;
    END IF;
END $$;
COMMIT;
