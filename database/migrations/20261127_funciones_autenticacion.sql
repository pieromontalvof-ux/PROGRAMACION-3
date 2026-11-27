BEGIN;

CREATE OR REPLACE FUNCTION public.auth_buscar_usuario(p_correo text, p_clave text)
RETURNS TABLE (id_usuario integer, dni varchar, nombres varchar, apellido_paterno varchar, apellido_materno varchar, celular varchar, correo_electronico varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT
            u.id_usuario,
            u.dni,
            u.nombres,
            u.apellido_paterno,
            u.apellido_materno,
            u.celular,
            u.correo_electronico
        FROM usuario u
        WHERE LOWER(u.correo_electronico) = LOWER(p_correo)
          AND u.clave = crypt(p_clave, u.clave)
          AND u.estado_registro = 1
        LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.auth_buscar_usuario_por_id(p_id_usuario integer)
RETURNS TABLE (id_usuario integer, dni varchar, nombres varchar, apellido_paterno varchar, apellido_materno varchar, celular varchar, correo_electronico varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT
            u.id_usuario,
            u.dni,
            u.nombres,
            u.apellido_paterno,
            u.apellido_materno,
            u.celular,
            u.correo_electronico
        FROM usuario u
        WHERE u.id_usuario = p_id_usuario
          AND u.estado_registro = 1
        LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.auth_listar_perfiles_usuario(p_id_usuario integer)
RETURNS TABLE (id_perfil integer, nombre varchar, descripcion varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT
            p.id_perfil,
            p.nombre,
            p.descripcion
        FROM usuario_perfiles up
        INNER JOIN perfiles p
            ON p.id_perfil = up.id_perfil
           AND p.estado_registro = 1
        WHERE up.id_usuario = p_id_usuario
          AND up.estado_registro = 1
        ORDER BY p.id_perfil
$$;

CREATE OR REPLACE FUNCTION public.auth_obtener_perfil_usuario(p_id_usuario integer, p_id_perfil integer)
RETURNS TABLE (id_perfil integer, nombre varchar, descripcion varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT
            p.id_perfil,
            p.nombre,
            p.descripcion
        FROM usuario_perfiles up
        INNER JOIN perfiles p
            ON p.id_perfil = up.id_perfil
           AND p.estado_registro = 1
        WHERE up.id_usuario = p_id_usuario
          AND up.id_perfil = p_id_perfil
          AND up.estado_registro = 1
        LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.auth_usuario_tiene_perfil(p_id_usuario integer, p_id_perfil integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT EXISTS (
            SELECT 1
            FROM usuario u
            INNER JOIN usuario_perfiles up
                ON up.id_usuario = u.id_usuario
               AND up.estado_registro = 1
            INNER JOIN perfiles p
                ON p.id_perfil = up.id_perfil
               AND p.estado_registro = 1
            WHERE u.id_usuario = p_id_usuario
              AND up.id_perfil = p_id_perfil
              AND u.estado_registro = 1
        )
$$;

CREATE OR REPLACE FUNCTION public.auth_listar_puestos_usuario(p_id_usuario integer)
RETURNS TABLE (id_puesto_laboral integer, nombre varchar, descripcion varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT
            pl.id_puesto_laboral,
            pl.nombre,
            pl.descripcion
        FROM usuario_puestos_laborales upl
        INNER JOIN puesto_laboral pl
            ON pl.id_puesto_laboral = upl.id_puesto_laboral
           AND pl.estado_registro = 1
        WHERE upl.id_usuario = p_id_usuario
          AND upl.estado_registro = 1
        ORDER BY pl.nombre
$$;

CREATE OR REPLACE FUNCTION public.auth_obtener_puesto_usuario(p_id_usuario integer, p_id_puesto_laboral integer)
RETURNS TABLE (id_puesto_laboral integer, nombre varchar, descripcion varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT
            pl.id_puesto_laboral,
            pl.nombre,
            pl.descripcion
        FROM usuario_puestos_laborales upl
        INNER JOIN puesto_laboral pl
            ON pl.id_puesto_laboral = upl.id_puesto_laboral
           AND pl.estado_registro = 1
        WHERE upl.id_usuario = p_id_usuario
          AND upl.id_puesto_laboral = p_id_puesto_laboral
          AND upl.estado_registro = 1
        LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.auth_obtener_menu(p_id_perfil integer)
RETURNS TABLE (id_opcion_menu integer, codigo varchar, nombre varchar, url_menu varchar, descripcion varchar, id_padre integer, icono varchar, tipo_opcion varchar, es_configurable boolean, puede_consultar boolean, puede_crear boolean, puede_editar boolean, puede_revisar boolean, puede_cerrar boolean, puede_desactivar boolean, puede_reactivar boolean, puede_eliminar boolean, puede_configurar boolean, orden smallint)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
        SELECT
            om.id_opcion_menu,
            om.codigo,
            om.nombre,
            om.url_menu,
            om.descripcion,
            om.id_padre,
            om.icono,
            om.tipo_opcion,
            om.es_configurable,
            pom.puede_consultar,
            pom.puede_crear,
            pom.puede_editar,
            pom.puede_revisar,
            pom.puede_cerrar,
            pom.puede_desactivar,
            pom.puede_reactivar,
            pom.puede_eliminar,
            pom.puede_configurar,
            pom.orden
        FROM perfil_opcion_menu pom
        INNER JOIN opcion_menu om
            ON om.id_opcion_menu = pom.id_opcion_menu
        WHERE pom.id_perfil = p_id_perfil
          AND pom.estado_registro = 1
            AND public.menu_disponible_para_perfil(p_id_perfil, om.id_opcion_menu)
          AND om.estado_registro = 1
          -- Las opciones de salsa ya se configuran desde Recetas.
          AND COALESCE(RTRIM(om.url_menu, '/'), '') <> '/home/grupos-salsa'
        ORDER BY
            COALESCE(
                om.id_padre,
                om.id_opcion_menu
            ),
            om.id_padre NULLS FIRST,
            pom.orden
$$;

CREATE OR REPLACE FUNCTION public.auth_permiso_usuario(p_usuario integer, p_perfil integer, p_opcion integer, p_campo text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
                SELECT EXISTS (
                    SELECT 1
                    FROM usuario u
                    INNER JOIN usuario_perfiles up
                        ON up.id_usuario = u.id_usuario
                       AND up.estado_registro = 1
                    INNER JOIN perfiles p
                        ON p.id_perfil = up.id_perfil
                       AND p.estado_registro = 1
                    INNER JOIN perfil_opcion_menu pom
                        ON pom.id_perfil = p.id_perfil
                       AND pom.estado_registro = 1
                    INNER JOIN opcion_menu om
                        ON om.id_opcion_menu = pom.id_opcion_menu
                       AND om.estado_registro = 1
                    WHERE u.id_usuario = p_usuario
                      AND u.estado_registro = 1
                      AND p.id_perfil = p_perfil
                      AND pom.id_opcion_menu = p_opcion
                      AND CASE p_campo
                          WHEN 'puede_consultar' THEN pom.puede_consultar
                          WHEN 'puede_crear' THEN pom.puede_crear
                          WHEN 'puede_editar' THEN pom.puede_editar
                          WHEN 'puede_revisar' THEN pom.puede_revisar
                          WHEN 'puede_cerrar' THEN pom.puede_cerrar
                          WHEN 'puede_desactivar' THEN pom.puede_desactivar
                          WHEN 'puede_reactivar' THEN pom.puede_reactivar
                          WHEN 'puede_eliminar' THEN pom.puede_eliminar
                          WHEN 'puede_configurar' THEN pom.puede_configurar
                          ELSE false
                      END
                )
$$;

COMMIT;
