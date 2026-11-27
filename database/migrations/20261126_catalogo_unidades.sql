BEGIN;

ALTER TABLE public.unidad_medida ADD COLUMN IF NOT EXISTS orden_catalogo integer NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.unidad_medida'::regclass
                   AND attname = 'simbolo_plural' AND NOT attisdropped) THEN
        ALTER TABLE public.unidad_medida ADD COLUMN simbolo_plural text;
        UPDATE public.unidad_medida SET simbolo_plural = 'unidades' WHERE codigo = 'C62';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.unidad_medida_alias (
    alias text PRIMARY KEY,
    codigo varchar(10) NOT NULL REFERENCES public.unidad_medida(codigo)
);

CREATE TABLE IF NOT EXISTS public.unidad_medida_contexto (
    contexto text NOT NULL,
    codigo_base varchar(10) NOT NULL REFERENCES public.unidad_medida(codigo),
    PRIMARY KEY (contexto, codigo_base)
);

-- Initial configuration for existing installations. On restart, preserve edits.
DO $$
BEGIN
    IF to_regclass('public.unidad_medida_catalogo_inicializado') IS NULL THEN
        UPDATE public.unidad_medida AS unidad
        SET orden_catalogo = inicial.orden
        FROM (VALUES ('KGM',1), ('GRM',2), ('LTR',3), ('MLT',4),
                     ('C62',5), ('PORCION',6)) AS inicial(codigo, orden)
        WHERE unidad.codigo = inicial.codigo AND unidad.orden_catalogo = 0;

        INSERT INTO public.unidad_medida_alias (alias, codigo)
        SELECT alternativo.alias, alternativo.codigo
        FROM (VALUES ('Kg','KGM'), ('UNI','C62'), ('PORCIÓN','PORCION'),
            ('ml','MLT'), ('l','LTR')) AS alternativo(alias, codigo)
        JOIN public.unidad_medida USING (codigo)
        ON CONFLICT DO NOTHING;

        INSERT INTO public.unidad_medida_contexto (contexto, codigo_base)
        SELECT permiso.contexto, permiso.codigo_base
        FROM (VALUES ('producto','KGM'), ('producto','LTR'), ('producto','C62'),
            ('subproducto','KGM'), ('subproducto','LTR'), ('subproducto','PORCION'),
            ('presentacion','KGM'), ('presentacion','LTR'), ('presentacion','C62'),
            ('presentacion','PORCION')) AS permiso(contexto, codigo_base)
        JOIN public.unidad_medida ON unidad_medida.codigo = permiso.codigo_base
        ON CONFLICT DO NOTHING;

        CREATE VIEW public.unidad_medida_catalogo_inicializado AS SELECT true AS inicializado;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.validar_unidad_medida_contexto()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.unidad_medida_contexto
        WHERE contexto = TG_ARGV[0] AND codigo_base = NEW.unidad
    ) THEN
        RAISE EXCEPTION 'Unidad % invalida para %', NEW.unidad, TG_ARGV[0]
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DO $$
DECLARE regla record;
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT ON public.unidad_medida_alias, public.unidad_medida_contexto TO multi;
    END IF;

    FOR regla IN SELECT * FROM (VALUES
        ('producto', 'ck_producto_unidad', 'producto'),
        ('subproducto', 'ck_subproducto_unidad', 'subproducto'),
        ('presentacion_venta', 'ck_presentacion_venta_unidad', 'presentacion'),
        ('subproducto_detalle', 'ck_subproducto_detalle_unidad', 'producto'),
        ('receta_detalle', 'ck_receta_detalle_unidad', 'presentacion'),
        ('grupo_salsa_opcion', 'grupo_salsa_opcion_unidad_check', 'producto')
    ) AS reglas(tabla, restriccion, contexto)
    LOOP
        IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.' || regla.tabla)
                   AND conname = regla.restriccion) THEN
            EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', regla.tabla, regla.restriccion);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = to_regclass('public.' || regla.tabla)
                       AND tgname = 'tr_validar_unidad_contexto') THEN
            EXECUTE format(
                'CREATE TRIGGER tr_validar_unidad_contexto BEFORE INSERT OR UPDATE OF unidad ON public.%I
                FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_medida_contexto(%L)', regla.tabla, regla.contexto);
        END IF;
    END LOOP;
END $$;

COMMIT;
