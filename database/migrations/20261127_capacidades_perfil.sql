BEGIN;

CREATE TABLE IF NOT EXISTS public.perfil_capacidad (
    id_perfil integer NOT NULL REFERENCES public.perfiles(id_perfil) ON DELETE CASCADE,
    capacidad text NOT NULL,
    PRIMARY KEY (id_perfil, capacidad)
);

DO $$
BEGIN
    IF to_regclass('public.menu_requiere_perfil_operativo') IS NULL THEN
        CREATE TABLE public.menu_requiere_perfil_operativo (
            id_opcion_menu integer PRIMARY KEY REFERENCES public.opcion_menu(id_opcion_menu) ON DELETE CASCADE
        );
        INSERT INTO public.menu_requiere_perfil_operativo (id_opcion_menu)
        SELECT id_opcion_menu FROM public.opcion_menu
        WHERE id_opcion_menu IN (15,16,17,18,19,20,21,22,23,24,31,32,36,37,38);

        INSERT INTO public.perfil_capacidad (id_perfil, capacidad)
        SELECT p.id_perfil, inicial.capacidad
        FROM (VALUES
            (1, 'administrar_globalmente'),
            (2, 'operar_tienda'), (3, 'operar_tienda'), (4, 'operar_tienda'),
            (2, 'gestionar_inventario'), (3, 'gestionar_inventario'),
            (2, 'asignar_conteos'), (4, 'contar_por_puesto'),
            (2, 'supervisar_salon'), (3, 'supervisar_salon'),
            (2, 'administrar_salon'), (4, 'atender_salon')
        ) AS inicial(id_perfil, capacidad)
        JOIN public.perfiles p USING (id_perfil);
    END IF;

    IF to_regclass('public.permiso_recurso') IS NULL THEN
        CREATE TABLE public.permiso_recurso (
            recurso text PRIMARY KEY,
            id_opcion_menu integer NOT NULL REFERENCES public.opcion_menu(id_opcion_menu) ON DELETE CASCADE
        );
        INSERT INTO public.permiso_recurso (recurso, id_opcion_menu)
        SELECT inicial.recurso, m.id_opcion_menu
        FROM (VALUES
            (2, 'usuarios'),
            (4, 'productos'),
            (5, 'categorias_productos'),
            (6, 'proveedores'),
            (8, 'categorias_carta'),
            (9, 'presentaciones_venta'),
            (10, 'menajes'),
            (12, 'subproductos'),
            (13, 'grupos_salsa'),
            (14, 'promociones'),
            (15, 'stock_actual'),
            (16, 'inventario'),
            (17, 'realizar_inventario'),
            (18, 'revisar_inventarios'),
            (20, 'registrar_movimiento'),
            (22, 'crear_orden_compra'),
            (24, 'pendientes_recepcion'),
            (26, 'actividades_sistema'),
            (28, 'recetas'),
            (31, 'historial_ordenes'),
            (32, 'historial_recepciones'),
            (33, 'limites_stock'),
            (36, 'cerrar_dia'),
            (37, 'mix_ventas'),
            (38, 'conteo_fisico')
        ) AS inicial(id_opcion_menu, recurso)
        JOIN public.opcion_menu m USING (id_opcion_menu);
    END IF;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT ON public.perfil_capacidad, public.menu_requiere_perfil_operativo, public.permiso_recurso TO multi;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.perfil_tiene_capacidad(p_perfil integer, p_capacidad text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT EXISTS (
        SELECT FROM public.perfil_capacidad c JOIN public.perfiles p USING (id_perfil)
        WHERE c.id_perfil = p_perfil AND c.capacidad = p_capacidad AND p.estado_registro = 1
    )
$$;

CREATE OR REPLACE FUNCTION public.menu_disponible_para_perfil(p_perfil integer, p_opcion integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT public.perfil_tiene_capacidad(p_perfil, 'operar_tienda')
        OR NOT EXISTS (
            SELECT FROM public.menu_requiere_perfil_operativo m WHERE m.id_opcion_menu = p_opcion
        )
$$;

CREATE OR REPLACE FUNCTION public.permiso_opcion_recurso(p_recurso text)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT id_opcion_menu FROM public.permiso_recurso WHERE recurso = p_recurso
$$;

COMMIT;
