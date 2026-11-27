BEGIN;

DO $$
BEGIN
    IF to_regclass('public.permiso_accion') IS NULL THEN
        CREATE TABLE public.permiso_accion (
            accion text PRIMARY KEY,
            campo text NOT NULL
        );
        INSERT INTO public.permiso_accion (accion, campo) VALUES
            ('consultar', 'puede_consultar'),
            ('crear', 'puede_crear'),
            ('editar', 'puede_editar'),
            ('revisar', 'puede_revisar'),
            ('cerrar', 'puede_cerrar'),
            ('desactivar', 'puede_desactivar'),
            ('reactivar', 'puede_reactivar'),
            ('eliminar', 'puede_eliminar'),
            ('configurar', 'puede_configurar');
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'multi') THEN
            GRANT SELECT ON public.permiso_accion TO multi;
        END IF;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.auth_permiso_accion(
    p_usuario integer, p_perfil integer, p_opcion integer, p_accion text
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT public.menu_disponible_para_perfil(p_perfil, p_opcion) AND COALESCE((
        SELECT public.auth_permiso_usuario(p_usuario, p_perfil, p_opcion, a.campo)
        FROM public.permiso_accion a
        WHERE a.accion = p_accion
    ), false)
$$;

CREATE OR REPLACE FUNCTION public.auth_permiso_accion(
    p_usuario integer, p_perfil integer, p_recurso text, p_accion text
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT COALESCE((
        SELECT public.auth_permiso_accion(p_usuario, p_perfil, r.id_opcion_menu, p_accion)
        FROM public.permiso_recurso r
        WHERE r.recurso = p_recurso
    ), false)
$$;

COMMIT;
