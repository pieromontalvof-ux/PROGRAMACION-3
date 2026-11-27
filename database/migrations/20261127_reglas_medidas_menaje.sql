BEGIN;

DO $$
BEGIN
    IF to_regclass('public.menaje_regla_medida') IS NULL THEN
        CREATE TABLE public.menaje_regla_medida (
            campo text PRIMARY KEY,
            etiqueta text NOT NULL,
            maximo numeric NOT NULL CHECK (maximo > 0 AND maximo < 'Infinity'::numeric),
            decimales smallint NOT NULL CHECK (decimales BETWEEN 0 AND 12)
        );
        INSERT INTO public.menaje_regla_medida VALUES
          ('capacidad','Capacidad',1000000,3), ('diametro_cm','Diámetro',10000,3),
          ('altura_cm','Altura',10000,3), ('largo_cm','Largo',10000,3), ('ancho_cm','Ancho',10000,3);
        ALTER TABLE public.menaje_medida
            ALTER COLUMN capacidad TYPE numeric,
            ALTER COLUMN diametro_cm TYPE numeric,
            ALTER COLUMN altura_cm TYPE numeric,
            ALTER COLUMN largo_cm TYPE numeric,
            ALTER COLUMN ancho_cm TYPE numeric,
            DROP CONSTRAINT IF EXISTS ck_menaje_medidas,
            DROP CONSTRAINT IF EXISTS ck_menaje_rectangular,
            ADD CONSTRAINT ck_menaje_medidas CHECK ((capacidad IS NULL) = (unidad_capacidad IS NULL)),
            ADD CONSTRAINT ck_menaje_rectangular CHECK (origen_medidas IN ('DEMO','REGISTRADO'));
        IF EXISTS (SELECT FROM pg_roles WHERE rolname='multi') THEN
            GRANT SELECT ON public.menaje_regla_medida TO multi;
        END IF;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.carta_reglas_medidas_menaje()
RETURNS TABLE (campo text, etiqueta text, maximo numeric, decimales smallint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT r.campo, r.etiqueta, r.maximo, r.decimales FROM public.menaje_regla_medida r
$$;

CREATE OR REPLACE FUNCTION public.carta_validar_medidas_menaje()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DECLARE
    campo_medida text;
    valor numeric;
    regla public.menaje_regla_medida%ROWTYPE;
BEGIN
    FOREACH campo_medida IN ARRAY ARRAY['capacidad','diametro_cm','altura_cm','largo_cm','ancho_cm'] LOOP
        valor := (to_jsonb(NEW)->>campo_medida)::numeric;
        IF valor IS NULL THEN CONTINUE; END IF;
        IF TG_OP='UPDATE' AND valor IS NOT DISTINCT FROM (to_jsonb(OLD)->>campo_medida)::numeric
            AND (campo_medida <> 'capacidad' OR NEW.unidad_capacidad IS NOT DISTINCT FROM OLD.unidad_capacidad)
        THEN CONTINUE; END IF;
        SELECT r.* INTO regla FROM public.menaje_regla_medida r WHERE r.campo=campo_medida;
        IF NOT FOUND OR valor <= 0 OR valor > regla.maximo OR valor <> round(valor, regla.decimales) THEN
            RAISE EXCEPTION 'Medida de menaje fuera de la regla configurada: %', campo_medida
                USING ERRCODE='check_violation';
        END IF;
    END LOOP;
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS tr_carta_validar_medidas_menaje ON public.menaje_medida;
CREATE TRIGGER tr_carta_validar_medidas_menaje
BEFORE INSERT OR UPDATE ON public.menaje_medida
FOR EACH ROW EXECUTE FUNCTION public.carta_validar_medidas_menaje();

COMMIT;
