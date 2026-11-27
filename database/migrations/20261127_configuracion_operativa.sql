BEGIN;

CREATE TABLE IF NOT EXISTS public.configuracion_operativa (
    unica boolean PRIMARY KEY DEFAULT true CHECK (unica),
    hora_limite_borrador time NOT NULL,
    distribucion_salon jsonb NOT NULL CHECK (jsonb_typeof(distribucion_salon) = 'array')
);

INSERT INTO public.configuracion_operativa (hora_limite_borrador, distribucion_salon)
VALUES (TIME '09:00', $distribucion$[
        {"codigo": "BARRA", "tipo": "barra", "x": 15, "y": 3, "ancho": 70, "alto": 12},
        {"codigo": "B01", "tipo": "puesto", "x": 20, "y": 18, "ancho": 7, "alto": 8},
        {"codigo": "B02", "tipo": "puesto", "x": 33, "y": 18, "ancho": 7, "alto": 8},
        {"codigo": "B03", "tipo": "puesto", "x": 46, "y": 18, "ancho": 7, "alto": 8},
        {"codigo": "B04", "tipo": "puesto", "x": 59, "y": 18, "ancho": 7, "alto": 8},
        {"codigo": "B05", "tipo": "puesto", "x": 72, "y": 18, "ancho": 7, "alto": 8},
        {"codigo": "M01", "tipo": "mesa", "x": 8, "y": 33, "ancho": 14, "alto": 14},
        {"codigo": "M02", "tipo": "mesa", "x": 31, "y": 33, "ancho": 14, "alto": 14},
        {"codigo": "M03", "tipo": "mesa", "x": 54, "y": 33, "ancho": 14, "alto": 14},
        {"codigo": "M04", "tipo": "mesa", "x": 77, "y": 33, "ancho": 14, "alto": 14},
        {"codigo": "M05", "tipo": "mesa", "x": 8, "y": 55, "ancho": 14, "alto": 14},
        {"codigo": "M06", "tipo": "mesa", "x": 31, "y": 55, "ancho": 14, "alto": 14},
        {"codigo": "M07", "tipo": "mesa", "x": 54, "y": 55, "ancho": 14, "alto": 14},
        {"codigo": "M08", "tipo": "mesa", "x": 77, "y": 55, "ancho": 14, "alto": 14},
        {"codigo": "M09", "tipo": "mesa", "x": 8, "y": 77, "ancho": 14, "alto": 14},
        {"codigo": "M10", "tipo": "mesa", "x": 31, "y": 77, "ancho": 14, "alto": 14}
    ]$distribucion$::jsonb)
ON CONFLICT (unica) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.proveedor_campo_comercial (
    campo text PRIMARY KEY,
    longitud_maxima integer NOT NULL CHECK (longitud_maxima > 0)
);

INSERT INTO public.proveedor_campo_comercial (campo, longitud_maxima)
VALUES ('ruc', 11), ('razon_social', 200), ('nombre_comercial', 200),
       ('direccion', 250), ('telefono', 40), ('email', 200), ('contacto', 200)
ON CONFLICT (campo) DO NOTHING;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT ON public.configuracion_operativa, public.proveedor_campo_comercial TO multi;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.hora_limite_borrador_inventario()
RETURNS time
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT hora_limite_borrador FROM public.configuracion_operativa
$$;

CREATE OR REPLACE FUNCTION public.salon_distribucion_predeterminada()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT distribucion_salon FROM public.configuracion_operativa
$$;

CREATE OR REPLACE FUNCTION public.proveedor_limites_comerciales()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT jsonb_object_agg(campo, longitud_maxima) FROM public.proveedor_campo_comercial
$$;

COMMIT;
