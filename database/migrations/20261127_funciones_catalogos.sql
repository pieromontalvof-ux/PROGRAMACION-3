BEGIN;

CREATE OR REPLACE FUNCTION public.catalogo_unidades()
RETURNS TABLE (codigo varchar, nombre varchar, simbolo varchar, dimension varchar, codigo_unece varchar, codigo_base varchar, factor_a_base numeric, simbolo_plural text, estandar text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT u.codigo,u.nombre,u.simbolo,u.dimension,u.codigo_unece,u.codigo_base,u.factor_a_base,u.simbolo_plural,u.estandar FROM public.unidad_medida u ORDER BY u.orden_catalogo,u.codigo
$$;

CREATE OR REPLACE FUNCTION public.catalogo_unidades_alias()
RETURNS TABLE (alias text, codigo varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT a.alias,a.codigo FROM public.unidad_medida_alias a
$$;

CREATE OR REPLACE FUNCTION public.catalogo_unidades_contextos()
RETURNS TABLE (contexto text, codigo_base varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT c.contexto,c.codigo_base FROM public.unidad_medida_contexto c
$$;

CREATE OR REPLACE FUNCTION public.catalogo_capacidad_menaje()
RETURNS TABLE (codigo varchar, nombre text, factor numeric, visible boolean, alias text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT u.codigo,u.nombre,u.factor,u.visible,u.alias FROM public.menaje_unidad_capacidad u ORDER BY u.orden,u.codigo
$$;

CREATE OR REPLACE FUNCTION public.catalogo_motivos_movimiento()
RETURNS TABLE (valor varchar, etiqueta text, tipo_movimiento varchar, requiere_local boolean, requiere_proveedor boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT m.codigo,m.etiqueta,m.tipo_movimiento,m.requiere_local,m.requiere_proveedor FROM public.movimiento_motivo m WHERE m.activo AND m.registrable ORDER BY m.orden,m.codigo
$$;

CREATE OR REPLACE FUNCTION public.configuracion_motivo_movimiento(p_codigo text)
RETURNS TABLE (tipo_movimiento varchar, requiere_local boolean, requiere_proveedor boolean, registrable boolean, motivo_recepcion varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT m.tipo_movimiento,m.requiere_local,m.requiere_proveedor,m.registrable,m.motivo_recepcion FROM public.movimiento_motivo m WHERE m.codigo=p_codigo AND m.activo
$$;

CREATE OR REPLACE FUNCTION public.catalogo_motivos_recepcion()
RETURNS TABLE (codigo text, etiqueta text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT r.codigo,r.etiqueta FROM public.recepcion_motivo_correccion r WHERE r.activo ORDER BY r.orden,r.codigo
$$;

COMMIT;
