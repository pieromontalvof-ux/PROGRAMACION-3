--
-- PostgreSQL database dump
--

\restrict MtWFxBWdaENJbDoI1Cx2tC5XuSaQAuYDG91Daus2eJ3aWW2EcDoaFJhCXtNsRXQ

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: auditoria_actividades(integer, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auditoria_actividades(p_limite integer, p_administrador boolean, p_id_local integer) RETURNS TABLE(id_actividad_usuario bigint, id_usuario integer, usuario text, id_perfil_utilizado integer, perfil_utilizado character varying, id_puesto_laboral integer, puesto_laboral character varying, id_local integer, local character varying, modulo character varying, accion character varying, id_registro_afectado integer, descripcion character varying, fecha_actividad timestamp without time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
SELECT
            a.id_actividad_usuario,
            a.id_usuario,
            CONCAT(u.nombres, ' ', u.apellido_paterno) AS usuario,
            a.id_perfil_utilizado,
            COALESCE(p.nombre, 'Perfil no registrado') AS perfil_utilizado,
            a.id_puesto_laboral,
            pl.nombre AS puesto_laboral,
            a.id_local,
            l.nombre AS local,
            a.modulo,
            a.accion,
            a.id_registro_afectado,
            a.descripcion,
            a.fecha_actividad
        FROM actividad_usuario a
        INNER JOIN usuario u
            ON u.id_usuario = a.id_usuario
        LEFT JOIN perfiles p
            ON p.id_perfil = a.id_perfil_utilizado
        LEFT JOIN puesto_laboral pl
            ON pl.id_puesto_laboral = a.id_puesto_laboral
        LEFT JOIN local l
            ON l.id_local = a.id_local
        WHERE a.estado_registro = 1
          AND NOT (a.modulo='AUTENTICACION' AND a.accion='CAMBIAR_PERFIL')
          AND (p_administrador OR a.id_local=p_id_local)
        ORDER BY
            a.fecha_actividad DESC,
            a.id_actividad_usuario DESC
        LIMIT p_limite
$$;


--
-- Name: auditoria_historial(integer, boolean, date, date, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auditoria_historial(p_local integer, p_globales boolean, p_desde date, p_hasta date, p_q text, p_patron text, p_offset integer) RETURNS TABLE(origen text, id bigint, id_usuario integer, id_perfil_utilizado integer, id_puesto_laboral integer, id_local integer, modulo character varying, accion character varying, id_registro_afectado integer, descripcion character varying, fecha timestamp without time zone, tabla text, antes jsonb, despues jsonb, usuario text, perfil character varying, puesto character varying, local character varying, usuario_afectado text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
WITH eventos AS (
          SELECT 'actividad' AS origen, id_actividad_usuario AS id, id_usuario,
            id_perfil_utilizado,id_puesto_laboral,id_local,modulo,accion,id_registro_afectado,
            descripcion,fecha_actividad AS fecha,NULL::text AS tabla,
            NULL::jsonb AS antes,NULL::jsonb AS despues
          FROM actividad_usuario WHERE estado_registro=1
          UNION ALL
          SELECT 'cambio',id_auditoria_cambio,id_usuario,id_perfil_utilizado,id_puesto_laboral,
            id_local,modulo,accion,id_registro_afectado,COALESCE(motivo,'Cambio registrado'),
            fecha_cambio,tabla_afectada,datos_anteriores,datos_nuevos FROM auditoria_cambio
        )
        SELECT e.*,concat_ws(' ',u.nombres,u.apellido_paterno,u.apellido_materno) AS usuario,
          p.nombre AS perfil,pl.nombre AS puesto,l.nombre AS local,
          CASE WHEN objetivo.id_usuario IS NOT NULL THEN
            concat_ws(' ',objetivo.nombres,objetivo.apellido_paterno,objetivo.apellido_materno) END AS usuario_afectado
        FROM eventos e JOIN usuario u ON u.id_usuario=e.id_usuario
        LEFT JOIN perfiles p ON p.id_perfil=e.id_perfil_utilizado
        LEFT JOIN puesto_laboral pl ON pl.id_puesto_laboral=e.id_puesto_laboral
        LEFT JOIN local l ON l.id_local=e.id_local
        LEFT JOIN usuario objetivo ON objetivo.id_usuario=e.id_registro_afectado
          AND (e.modulo='USUARIOS' OR e.tabla='usuario')
        WHERE NOT (e.modulo='AUTENTICACION' AND e.accion='CAMBIAR_PERFIL')
          AND (CAST(p_local AS integer) IS NULL OR e.id_local=p_local)
          AND (NOT p_globales OR e.id_local IS NULL)
          AND (CAST(p_desde AS date) IS NULL OR e.fecha >= CAST(p_desde AS date))
          AND (CAST(p_hasta AS date) IS NULL OR e.fecha < CAST(p_hasta AS date)+interval '1 day')
          AND (p_q='' OR concat_ws(' ',u.nombres,u.apellido_paterno,objetivo.nombres,
              objetivo.apellido_paterno,e.modulo,e.accion,e.descripcion) ILIKE p_patron)
        ORDER BY e.fecha DESC,e.origen,e.id DESC LIMIT 51 OFFSET p_offset
$$;


--
-- Name: auditoria_insertar_actividad(integer, text, text, integer, text, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auditoria_insertar_actividad(p_id_usuario integer, p_modulo text, p_accion text, p_id_registro_afectado integer, p_descripcion text, p_id_perfil_utilizado integer, p_id_puesto_laboral integer, p_id_local integer) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
INSERT INTO actividad_usuario (
            id_usuario,
            modulo,
            accion,
            id_registro_afectado,
            descripcion,
            id_perfil_utilizado,
            id_puesto_laboral,
            id_local
        ) VALUES (
            p_id_usuario,
            p_modulo,
            p_accion,
            p_id_registro_afectado,
            p_descripcion,
            p_id_perfil_utilizado,
            p_id_puesto_laboral,
            p_id_local
        )
        RETURNING id_actividad_usuario
$$;


--
-- Name: auditoria_insertar_cambio(integer, integer, integer, integer, text, text, text, integer, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auditoria_insertar_cambio(p_id_usuario integer, p_id_perfil_utilizado integer, p_id_puesto_laboral integer, p_id_local integer, p_modulo text, p_accion text, p_tabla_afectada text, p_id_registro_afectado integer, p_datos_anteriores text, p_datos_nuevos text, p_motivo text) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
INSERT INTO auditoria_cambio (
            id_usuario,
            id_perfil_utilizado,
            id_puesto_laboral,
            id_local,
            modulo,
            accion,
            tabla_afectada,
            id_registro_afectado,
            datos_anteriores,
            datos_nuevos,
            motivo
        ) VALUES (
            p_id_usuario,
            p_id_perfil_utilizado,
            p_id_puesto_laboral,
            p_id_local,
            p_modulo,
            p_accion,
            p_tabla_afectada,
            p_id_registro_afectado,
            CAST(p_datos_anteriores AS JSONB),
            CAST(p_datos_nuevos AS JSONB),
            p_motivo
        )
        RETURNING id_auditoria_cambio
$$;


--
-- Name: auditoria_locales(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auditoria_locales(p_local integer) RETURNS TABLE(id_local integer, nombre character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
SELECT l.id_local,l.nombre FROM public.local l WHERE p_local IS NULL OR l.id_local=p_local ORDER BY l.nombre
$$;


--
-- Name: auth_buscar_usuario(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_buscar_usuario(p_correo text, p_clave text) RETURNS TABLE(id_usuario integer, dni character varying, nombres character varying, apellido_paterno character varying, apellido_materno character varying, celular character varying, correo_electronico character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_buscar_usuario_por_id(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_buscar_usuario_por_id(p_id_usuario integer) RETURNS TABLE(id_usuario integer, dni character varying, nombres character varying, apellido_paterno character varying, apellido_materno character varying, celular character varying, correo_electronico character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_listar_perfiles_usuario(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_listar_perfiles_usuario(p_id_usuario integer) RETURNS TABLE(id_perfil integer, nombre character varying, descripcion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_listar_puestos_usuario(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_listar_puestos_usuario(p_id_usuario integer) RETURNS TABLE(id_puesto_laboral integer, nombre character varying, descripcion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_obtener_menu(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_obtener_menu(p_id_perfil integer) RETURNS TABLE(id_opcion_menu integer, codigo character varying, nombre character varying, url_menu character varying, descripcion character varying, id_padre integer, icono character varying, tipo_opcion character varying, es_configurable boolean, puede_consultar boolean, puede_crear boolean, puede_editar boolean, puede_revisar boolean, puede_cerrar boolean, puede_desactivar boolean, puede_reactivar boolean, puede_eliminar boolean, puede_configurar boolean, orden smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_obtener_perfil_usuario(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_obtener_perfil_usuario(p_id_usuario integer, p_id_perfil integer) RETURNS TABLE(id_perfil integer, nombre character varying, descripcion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_obtener_puesto_usuario(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_obtener_puesto_usuario(p_id_usuario integer, p_id_puesto_laboral integer) RETURNS TABLE(id_puesto_laboral integer, nombre character varying, descripcion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_perfil_puede_cambiar_local(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_perfil_puede_cambiar_local(p_perfil integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT FROM public.perfiles p
        WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.puede_cambiar_local
    )
$$;


--
-- Name: auth_perfil_requiere_puesto(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_perfil_requiere_puesto(p_perfil integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT FROM public.perfiles p
        WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.requiere_puesto_activo
    )
$$;


--
-- Name: auth_permiso_accion(integer, integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_permiso_accion(p_usuario integer, p_perfil integer, p_opcion integer, p_accion text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT public.menu_disponible_para_perfil(p_perfil, p_opcion) AND COALESCE((
        SELECT public.auth_permiso_usuario(p_usuario, p_perfil, p_opcion, a.campo)
        FROM public.permiso_accion a
        WHERE a.accion = p_accion
    ), false)
$$;


--
-- Name: auth_permiso_accion(integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_permiso_accion(p_usuario integer, p_perfil integer, p_recurso text, p_accion text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT COALESCE((
        SELECT public.auth_permiso_accion(p_usuario, p_perfil, r.id_opcion_menu, p_accion)
        FROM public.permiso_recurso r
        WHERE r.recurso = p_recurso
    ), false)
$$;


--
-- Name: auth_permiso_usuario(integer, integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_permiso_usuario(p_usuario integer, p_perfil integer, p_opcion integer, p_campo text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auth_usuario_tiene_perfil(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_usuario_tiene_perfil(p_id_usuario integer, p_id_perfil integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: carta_admin_articulos(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_articulos(p_id integer) RETURNS TABLE(id_item_carta integer, codigo character varying, id_categoria_carta integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT id_item_carta, codigo, id_categoria_carta FROM item_carta WHERE id_categoria_carta=p_id ORDER BY id_item_carta
$$;


--
-- Name: carta_admin_categoria(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_categoria(p_id integer) RETURNS TABLE(id_categoria_carta integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT * FROM categoria_carta WHERE id_categoria_carta=p_id
$$;


--
-- Name: carta_admin_categoria_activa(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_categoria_activa(p_id integer) RETURNS SETOF integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT 1 FROM categoria_carta WHERE id_categoria_carta=p_id AND activo
$$;


--
-- Name: carta_admin_categoria_duplicada(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_categoria_duplicada(p_id integer, p_nombre text, p_prefijo text) RETURNS SETOF integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT 1 FROM categoria_carta WHERE id_categoria_carta<>p_id AND (lower(trim(nombre))=lower(p_nombre) OR upper(prefijo)=p_prefijo)
$$;


--
-- Name: carta_admin_crear_categoria(text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_crear_categoria(p_nombre text, p_prefijo text, p_numero integer) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    INSERT INTO categoria_carta(nombre,prefijo,siguiente_numero,activo) VALUES (p_nombre,p_prefijo,p_numero,true) RETURNING id_categoria_carta
$$;


--
-- Name: carta_admin_editar_categoria(text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_editar_categoria(p_nombre text, p_prefijo text, p_numero integer, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE categoria_carta SET nombre=p_nombre, prefijo=p_prefijo, siguiente_numero=p_numero WHERE id_categoria_carta=p_id
$$;


--
-- Name: carta_admin_estado_categoria(boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_estado_categoria(p_activo boolean, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE categoria_carta SET activo=p_activo WHERE id_categoria_carta=p_id
$$;


--
-- Name: carta_admin_menaje_bloquear(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_bloquear() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    LOCK TABLE menaje IN SHARE ROW EXCLUSIVE MODE
$$;


--
-- Name: carta_admin_menaje_borrar_medidas(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_borrar_medidas(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    DELETE FROM menaje_medida WHERE id_menaje=p_id
$$;


--
-- Name: carta_admin_menaje_crear(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_crear(p_nombre text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    INSERT INTO menaje(nombre,activo) VALUES (p_nombre,true) RETURNING id_menaje
$$;


--
-- Name: carta_admin_menaje_editar(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_editar(p_nombre text, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE menaje SET nombre=p_nombre WHERE id_menaje=p_id
$$;


--
-- Name: carta_admin_menaje_eliminar(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_eliminar(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    DELETE FROM menaje WHERE id_menaje=p_id
$$;


--
-- Name: carta_admin_menaje_estado(boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_estado(p_activo boolean, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE menaje SET activo=p_activo WHERE id_menaje=p_id
$$;


--
-- Name: carta_admin_menaje_guardar_medidas(integer, numeric, text, numeric, numeric, numeric, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_guardar_medidas(p_id integer, p_capacidad numeric, p_unidad_capacidad text, p_diametro_cm numeric, p_altura_cm numeric, p_largo_cm numeric, p_ancho_cm numeric, p_origen text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    INSERT INTO menaje_medida(id_menaje,capacidad,unidad_capacidad,diametro_cm,altura_cm,largo_cm,ancho_cm,origen_medidas)
                VALUES(p_id,p_capacidad,p_unidad_capacidad,p_diametro_cm,p_altura_cm,p_largo_cm,p_ancho_cm,p_origen)
                ON CONFLICT(id_menaje) DO UPDATE SET capacidad=EXCLUDED.capacidad,
                unidad_capacidad=EXCLUDED.unidad_capacidad,diametro_cm=EXCLUDED.diametro_cm,altura_cm=EXCLUDED.altura_cm,
                largo_cm=EXCLUDED.largo_cm,ancho_cm=EXCLUDED.ancho_cm,origen_medidas=EXCLUDED.origen_medidas
$$;


--
-- Name: carta_admin_menaje_nombre_existe(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_nombre_existe(p_nombre text, p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS(SELECT 1 FROM menaje WHERE lower(trim(nombre))=lower(p_nombre) AND id_menaje<>p_id)
$$;


--
-- Name: carta_admin_menaje_tiene_presentaciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_menaje_tiene_presentaciones(p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS(SELECT 1 FROM presentacion_venta WHERE id_menaje=p_id)
$$;


--
-- Name: carta_admin_perfil_autorizado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_perfil_autorizado(p_perfil integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (SELECT FROM public.perfiles p WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.administra_catalogos_carta)
$$;


--
-- Name: carta_admin_reasignar_articulos(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_reasignar_articulos(p_destino integer, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE item_carta SET id_categoria_carta=p_destino WHERE id_categoria_carta=p_id
$$;


--
-- Name: carta_admin_siguiente_numero(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_admin_siguiente_numero(p_patron text) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT coalesce(max(split_part(codigo, '-', 2)::bigint),0)+1 FROM item_carta WHERE codigo ~ p_patron
$$;


--
-- Name: carta_bloquear_menaje(integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_bloquear_menaje(p_id integer, p_edicion boolean) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    IF p_edicion THEN
        PERFORM 1 FROM public.menaje m WHERE m.id_menaje = p_id FOR UPDATE;
    ELSE
        PERFORM 1 FROM public.menaje m WHERE m.id_menaje = p_id FOR SHARE;
    END IF;
    RETURN FOUND;
END;
$$;


--
-- Name: carta_categorias_detalladas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_categorias_detalladas() RETURNS TABLE(id_categoria_carta integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean, total_items bigint, items_activos bigint, items_inactivos bigint, total_presentaciones bigint, presentaciones_activas bigint, presentaciones_inactivas bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            cc.id_categoria_carta,
            cc.nombre,
            cc.prefijo,
            cc.siguiente_numero,
            cc.activo,

            COUNT(DISTINCT ic.id_item_carta)
                AS total_items,

            COUNT(DISTINCT ic.id_item_carta)
                FILTER (WHERE ic.activo = TRUE)
                AS items_activos,

            COUNT(DISTINCT ic.id_item_carta)
                FILTER (WHERE ic.activo = FALSE)
                AS items_inactivos,

            COUNT(DISTINCT pv.id_presentacion_venta)
                AS total_presentaciones,

            COUNT(DISTINCT pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = TRUE)
                AS presentaciones_activas,

            COUNT(DISTINCT pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = FALSE)
                AS presentaciones_inactivas

        FROM categoria_carta AS cc

        LEFT JOIN item_carta AS ic
            ON ic.id_categoria_carta = cc.id_categoria_carta

        LEFT JOIN presentacion_venta AS pv
            ON pv.id_item_carta = ic.id_item_carta

        GROUP BY
            cc.id_categoria_carta,
            cc.nombre,
            cc.prefijo,
            cc.siguiente_numero,
            cc.activo

        ORDER BY cc.nombre ASC
$$;


--
-- Name: carta_editor_articulo_nombre_existe(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_articulo_nombre_existe(p_nombre text, p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS(SELECT 1 FROM item_carta WHERE lower(trim(nombre))=lower(p_nombre) AND id_item_carta<>p_id)
$$;


--
-- Name: carta_editor_articulo_receta_multiple(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_articulo_receta_multiple(p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS(SELECT 1 FROM receta r JOIN presentacion_venta pv USING(id_presentacion_venta)
            WHERE pv.id_item_carta=p_id AND (SELECT count(*) FROM receta_detalle d WHERE d.id_receta=r.id_receta)<>1)
$$;


--
-- Name: carta_editor_articulos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_articulos() RETURNS TABLE(id_item_carta integer, codigo character varying, nombre character varying, id_categoria_carta integer, tipo character varying, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT id_item_carta, codigo, nombre, id_categoria_carta, tipo, activo FROM item_carta ORDER BY nombre
$$;


--
-- Name: carta_editor_bloquear_articulo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_bloquear_articulo(p_id integer) RETURNS TABLE(id_item_carta integer, codigo character varying, nombre character varying, id_categoria_carta integer, tipo character varying, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT * FROM item_carta WHERE id_item_carta=p_id FOR UPDATE
$$;


--
-- Name: carta_editor_bloquear_articulos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_bloquear_articulos() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    LOCK TABLE item_carta IN SHARE ROW EXCLUSIVE MODE
$$;


--
-- Name: carta_editor_bloquear_categorias(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_bloquear_categorias() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    LOCK TABLE categoria_carta IN SHARE ROW EXCLUSIVE MODE
$$;


--
-- Name: carta_editor_bloquear_presentacion(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_bloquear_presentacion(p_id integer) RETURNS TABLE(id_presentacion_venta integer, id_item_carta integer, id_menaje integer, contenido numeric, unidad character varying, precio numeric, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT * FROM presentacion_venta WHERE id_presentacion_venta=p_id FOR UPDATE
$$;


--
-- Name: carta_editor_categoria_activa(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_categoria_activa(p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS(SELECT 1 FROM categoria_carta WHERE id_categoria_carta=p_id AND activo)
$$;


--
-- Name: carta_editor_categorias(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_categorias() RETURNS TABLE(id_categoria_carta integer, nombre character varying, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT id_categoria_carta, nombre, activo FROM categoria_carta ORDER BY nombre
$$;


--
-- Name: carta_editor_crear_articulo(text, text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_crear_articulo(p_codigo text, p_nombre text, p_categoria integer, p_tipo text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    INSERT INTO item_carta(codigo,nombre,id_categoria_carta,tipo,activo) VALUES (p_codigo,p_nombre,p_categoria,p_tipo,true) RETURNING id_item_carta
$$;


--
-- Name: carta_editor_crear_presentacion(integer, integer, numeric, text, numeric, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_crear_presentacion(p_item integer, p_menaje integer, p_contenido numeric, p_unidad text, p_precio numeric, p_activo boolean) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    INSERT INTO presentacion_venta(id_item_carta,id_menaje,contenido,unidad,precio,activo) VALUES (p_item,p_menaje,p_contenido,p_unidad,p_precio,p_activo) RETURNING id_presentacion_venta
$$;


--
-- Name: carta_editor_editar_articulo(text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_editar_articulo(p_nombre text, p_tipo text, p_categoria integer, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE item_carta SET nombre=p_nombre,tipo=p_tipo,id_categoria_carta=p_categoria WHERE id_item_carta=p_id
$$;


--
-- Name: carta_editor_editar_presentacion(integer, numeric, text, numeric, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_editar_presentacion(p_menaje integer, p_contenido numeric, p_unidad text, p_precio numeric, p_activo boolean, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE presentacion_venta SET id_menaje=p_menaje,contenido=p_contenido,unidad=p_unidad,precio=p_precio,activo=p_activo WHERE id_presentacion_venta=p_id
$$;


--
-- Name: carta_editor_leer_articulo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_leer_articulo(p_id integer) RETURNS TABLE(id_item_carta integer, codigo character varying, nombre character varying, id_categoria_carta integer, tipo character varying, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT * FROM item_carta WHERE id_item_carta=p_id
$$;


--
-- Name: carta_editor_leer_presentacion(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_leer_presentacion(p_id integer) RETURNS TABLE(id_presentacion_venta integer, id_item_carta integer, id_menaje integer, contenido numeric, unidad character varying, precio numeric, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT * FROM presentacion_venta WHERE id_presentacion_venta=p_id
$$;


--
-- Name: carta_editor_reservar_codigo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_reservar_codigo(p_id integer) RETURNS TABLE(prefijo character varying, numero integer)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE categoria_carta SET siguiente_numero=siguiente_numero+1 WHERE id_categoria_carta=p_id AND activo RETURNING prefijo,siguiente_numero-1 AS numero
$$;


--
-- Name: carta_editor_tipos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_editor_tipos() RETURNS text[]
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT ARRAY(
        SELECT coincidencia[1]
        FROM pg_constraint c
        CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([^'']+)''::character varying', 'g') AS coincidencia
        WHERE c.conname = 'ck_item_carta_tipo' AND c.conrelid = 'public.item_carta'::regclass
    )
$$;


--
-- Name: carta_medidas_menaje(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_medidas_menaje(p_id integer) RETURNS TABLE(id_menaje integer, nombre character varying, activo boolean, capacidad numeric, unidad_capacidad character varying, diametro_cm numeric, altura_cm numeric, largo_cm numeric, ancho_cm numeric, origen_medidas character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT m.id_menaje, m.nombre, m.activo, d.capacidad, d.unidad_capacidad,
           d.diametro_cm, d.altura_cm, d.largo_cm, d.ancho_cm, d.origen_medidas
    FROM public.menaje m
    LEFT JOIN public.menaje_medida d USING (id_menaje)
    WHERE p_id IS NULL OR m.id_menaje = p_id
    ORDER BY m.nombre
$$;


--
-- Name: carta_menajes_detallados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_menajes_detallados() RETURNS TABLE(id_menaje integer, nombre character varying, activo boolean, capacidad numeric, unidad_capacidad character varying, diametro_cm numeric, altura_cm numeric, largo_cm numeric, ancho_cm numeric, origen_medidas character varying, total_presentaciones bigint, presentaciones_activas bigint, presentaciones_inactivas bigint, total_items bigint, items jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT
            m.id_menaje,
            m.nombre,
            m.activo,
            md.capacidad,md.unidad_capacidad,md.diametro_cm,md.altura_cm,md.largo_cm,md.ancho_cm,md.origen_medidas,

            COUNT(pv.id_presentacion_venta)
                AS total_presentaciones,

            COUNT(pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = TRUE)
                AS presentaciones_activas,

            COUNT(pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = FALSE)
                AS presentaciones_inactivas,

            COUNT(DISTINCT pv.id_item_carta)
                AS total_items,

            COALESCE(
                JSONB_AGG(DISTINCT ic.nombre)
                    FILTER (
                        WHERE ic.id_item_carta IS NOT NULL
                    ),
                '[]'::JSONB
            ) AS items

        FROM menaje AS m
        LEFT JOIN menaje_medida md ON md.id_menaje=m.id_menaje

        LEFT JOIN presentacion_venta AS pv
            ON pv.id_menaje = m.id_menaje

        LEFT JOIN item_carta AS ic
            ON ic.id_item_carta = pv.id_item_carta

        GROUP BY
            m.id_menaje,
            md.id_menaje,
            m.nombre,
            m.activo

        ORDER BY m.nombre ASC
$$;


--
-- Name: carta_presentaciones_detalladas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_presentaciones_detalladas() RETURNS TABLE(id_presentacion_venta integer, id_item_carta integer, codigo_item character varying, item character varying, tipo character varying, id_categoria_carta integer, categoria character varying, id_menaje integer, menaje character varying, contenido numeric, unidad character varying, precio numeric, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT
            pv.id_presentacion_venta,
            pv.id_item_carta,
            ic.codigo AS codigo_item,
            ic.nombre AS item,
            ic.tipo,
            ic.id_categoria_carta,
            cc.nombre AS categoria,
            pv.id_menaje,
            m.nombre AS menaje,
            pv.contenido,
            pv.unidad,
            pv.precio,
            pv.activo
        FROM presentacion_venta AS pv
        INNER JOIN item_carta AS ic
            ON ic.id_item_carta = pv.id_item_carta
        INNER JOIN categoria_carta AS cc
            ON cc.id_categoria_carta =
                ic.id_categoria_carta
        INNER JOIN menaje AS m
            ON m.id_menaje = pv.id_menaje
        ORDER BY
            cc.nombre ASC,
            ic.nombre ASC,
            pv.contenido ASC,
            pv.precio ASC
$$;


--
-- Name: carta_reglas_medidas_menaje(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_reglas_medidas_menaje() RETURNS TABLE(campo text, etiqueta text, maximo numeric, decimales smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT r.campo, r.etiqueta, r.maximo, r.decimales FROM public.menaje_regla_medida r
$$;


--
-- Name: carta_validar_medidas_menaje(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carta_validar_medidas_menaje() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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


--
-- Name: catalogo_capacidad_menaje(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogo_capacidad_menaje() RETURNS TABLE(codigo character varying, nombre text, factor numeric, visible boolean, alias text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT u.codigo,u.nombre,u.factor,u.visible,u.alias FROM public.menaje_unidad_capacidad u ORDER BY u.orden,u.codigo
$$;


--
-- Name: catalogo_motivos_movimiento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogo_motivos_movimiento() RETURNS TABLE(valor character varying, etiqueta text, tipo_movimiento character varying, requiere_local boolean, requiere_proveedor boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT m.codigo,m.etiqueta,m.tipo_movimiento,m.requiere_local,m.requiere_proveedor FROM public.movimiento_motivo m WHERE m.activo AND m.registrable ORDER BY m.orden,m.codigo
$$;


--
-- Name: catalogo_motivos_recepcion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogo_motivos_recepcion() RETURNS TABLE(codigo text, etiqueta text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT r.codigo,r.etiqueta FROM public.recepcion_motivo_correccion r WHERE r.activo ORDER BY r.orden,r.codigo
$$;


--
-- Name: catalogo_unidades(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogo_unidades() RETURNS TABLE(codigo character varying, nombre character varying, simbolo character varying, dimension character varying, codigo_unece character varying, codigo_base character varying, factor_a_base numeric, simbolo_plural text, estandar text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT u.codigo,u.nombre,u.simbolo,u.dimension,u.codigo_unece,u.codigo_base,u.factor_a_base,u.simbolo_plural,u.estandar FROM public.unidad_medida u ORDER BY u.orden_catalogo,u.codigo
$$;


--
-- Name: catalogo_unidades_alias(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogo_unidades_alias() RETURNS TABLE(alias text, codigo character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT a.alias,a.codigo FROM public.unidad_medida_alias a
$$;


--
-- Name: catalogo_unidades_contextos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogo_unidades_contextos() RETURNS TABLE(contexto text, codigo_base character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT c.contexto,c.codigo_base FROM public.unidad_medida_contexto c
$$;


--
-- Name: catalogos_actualizar_categoria(text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_actualizar_categoria(p_nombre text, p_prefijo text, p_id_categoria integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE categoria_producto
            SET nombre = p_nombre, prefijo = p_prefijo
            WHERE id_categoria = p_id_categoria
$$;


--
-- Name: catalogos_actualizar_producto_registro(text, integer, integer, text, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_actualizar_producto_registro(p_nombre text, p_categoria integer, p_proveedor integer, p_unidad text, p_presentacion numeric, p_id_producto integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE producto
            SET nombre = p_nombre,
                id_categoria = p_categoria,
                id_proveedor = p_proveedor,
                unidad = p_unidad,
                presentacion = p_presentacion
            WHERE id_producto = p_id_producto
$$;


--
-- Name: catalogos_actualizar_proveedor(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_actualizar_proveedor(p_nombre text, p_id_proveedor integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE proveedor SET nombre = p_nombre
            WHERE id_proveedor = p_id_proveedor
$$;


--
-- Name: catalogos_asignar_categorias_proveedor_1(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_asignar_categorias_proveedor_1(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM proveedor_categoria WHERE id_proveedor = p_id
$$;


--
-- Name: catalogos_asignar_categorias_proveedor_2(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_asignar_categorias_proveedor_2(p_id integer, p_categoria integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO proveedor_categoria (id_proveedor, id_categoria)
            VALUES (p_id, p_categoria)
$$;


--
-- Name: catalogos_cambiar_estado_categoria(boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_cambiar_estado_categoria(p_activo boolean, p_id_categoria integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE categoria_producto SET activo = p_activo
            WHERE id_categoria = p_id_categoria
$$;


--
-- Name: catalogos_cambiar_estado_producto(boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_cambiar_estado_producto(p_activo boolean, p_id_producto integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE producto SET activo = p_activo
            WHERE id_producto = p_id_producto
$$;


--
-- Name: catalogos_cambiar_estado_proveedor(boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_cambiar_estado_proveedor(p_activo boolean, p_id_proveedor integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE proveedor SET activo = p_activo
            WHERE id_proveedor = p_id_proveedor
$$;


--
-- Name: catalogos_categoria_repetida(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_categoria_repetida(p_excluir_id integer, p_nombre text, p_prefijo text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
                SELECT 1 FROM categoria_producto
                WHERE (p_excluir_id IS NULL OR id_categoria <> p_excluir_id)
                  AND (
                    LOWER(BTRIM(nombre)) = LOWER(BTRIM(p_nombre))
                    OR UPPER(BTRIM(prefijo)) = UPPER(BTRIM(p_prefijo))
                  )
            )
$$;


--
-- Name: catalogos_categorias_proveedor(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_categorias_proveedor(p_id integer) RETURNS SETOF integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_categoria FROM public.catalogos_origen_categorias_proveedor() pc
        WHERE id_proveedor = p_id ORDER BY id_categoria
$$;


--
-- Name: catalogos_categorias_proveedor_disponibles(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_categorias_proveedor_disponibles() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.proveedor_categoria') IS NOT NULL
$$;


--
-- Name: catalogos_comprobar_dependencias(regclass, bigint[], jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_comprobar_dependencias(p_tabla regclass, p_ids bigint[], p_permitidas jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
DECLARE
    relacion record;
    existe boolean;
BEGIN
    FOR relacion IN
        SELECT n.nspname esquema, cl.relname tabla, a.attname columna,
               cardinality(c.conkey) columnas
        FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid
        JOIN pg_namespace n ON n.oid=cl.relnamespace
        JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
        WHERE c.contype='f' AND c.confrelid=p_tabla
    LOOP
        IF relacion.esquema='public' AND p_permitidas->>relacion.tabla=relacion.columna THEN CONTINUE; END IF;
        IF relacion.columnas<>1 THEN
            RAISE EXCEPTION 'El registro tiene relaciones compuestas que requieren revision antes de eliminar';
        END IF;
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I=ANY($1))',
            relacion.esquema,relacion.tabla,relacion.columna) INTO existe USING p_ids;
        IF existe THEN
            RAISE EXCEPTION 'No se puede eliminar: tiene registros asociados en %. Reasigna o retira sus dependencias; si son historicas, conserva el registro y desactivalo.', relacion.tabla;
        END IF;
    END LOOP;
END
$_$;


--
-- Name: catalogos_crear_categoria(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_crear_categoria(p_nombre text, p_prefijo text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO categoria_producto
                (nombre, prefijo, siguiente_numero, activo)
            VALUES (p_nombre, p_prefijo, 1, TRUE)
            RETURNING id_categoria
$$;


--
-- Name: catalogos_crear_producto_registro(text, text, integer, integer, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_crear_producto_registro(p_codigo text, p_nombre text, p_categoria integer, p_proveedor integer, p_unidad text, p_presentacion numeric) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO producto (
                codigo, nombre, id_categoria, id_proveedor,
                unidad, presentacion, activo
            ) VALUES (
                p_codigo, p_nombre, p_categoria, p_proveedor,
                p_unidad, p_presentacion, TRUE
            ) RETURNING id_producto
$$;


--
-- Name: catalogos_crear_proveedor(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_crear_proveedor(p_nombre text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO proveedor (nombre, activo)
            VALUES (p_nombre, TRUE)
            RETURNING id_proveedor
$$;


--
-- Name: catalogos_dependencias_producto(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_dependencias_producto(p_id integer) RETURNS TABLE(recetas bigint, subproductos bigint, salsas_activas bigint, ordenes bigint, recepciones bigint, inventarios bigint, movimientos bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
          (SELECT COUNT(*) FROM receta_detalle
           WHERE id_producto = p_id) AS recetas,
          (SELECT COUNT(*) FROM subproducto_detalle
           WHERE id_producto = p_id) AS subproductos,
          (SELECT COUNT(*) FROM grupo_salsa_opcion
           WHERE id_producto = p_id AND activo = TRUE) AS salsas_activas,
          (SELECT COUNT(*) FROM orden_compra_detalle
           WHERE id_producto = p_id) AS ordenes,
          (SELECT COUNT(*) FROM factura_recepcion_detalle
           WHERE id_producto = p_id) AS recepciones,
          (SELECT COUNT(*) FROM inventario_cierre_detalle
           WHERE id_producto = p_id) AS inventarios,
          (SELECT COUNT(*) FROM movimiento_inventario_detalle
           WHERE id_producto = p_id) AS movimientos
$$;


--
-- Name: catalogos_eliminar_registro(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_eliminar_registro(p_entidad text, p_id bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
DECLARE
    entidad record;
    hija record;
    anterior jsonb;
    detalles jsonb := '{}'::jsonb;
    filas jsonb;
    opciones jsonb;
    ids bigint[];
BEGIN
    SELECT * INTO entidad FROM public.catalogos_entidad_eliminable(p_entidad);
    IF NOT FOUND THEN RETURN NULL; END IF;
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE %I=$1 FOR UPDATE',
        entidad.tabla, entidad.clave) INTO anterior USING p_id;
    IF anterior IS NULL THEN RETURN NULL; END IF;
    PERFORM public.catalogos_comprobar_dependencias(
        to_regclass('public.' || entidad.tabla), ARRAY[p_id], entidad.hijas);

    FOR hija IN SELECT key tabla,value clave FROM jsonb_each_text(entidad.hijas) ORDER BY key LOOP
        EXECUTE format(
            'SELECT coalesce(jsonb_agg(to_jsonb(t)),''[]'') FROM
             (SELECT * FROM public.%I WHERE %I=$1 FOR UPDATE) t', hija.tabla,hija.clave)
        INTO filas USING p_id;
        detalles := detalles || jsonb_build_object(hija.tabla,
            public.catalogos_filas_auditoria(to_regclass('public.' || hija.tabla),filas));
        IF hija.tabla='promocion_grupo' THEN
            SELECT array_agg((x->>'id_promocion_grupo')::bigint) INTO ids FROM jsonb_array_elements(filas) x;
            IF ids IS NOT NULL THEN
                PERFORM public.catalogos_comprobar_dependencias('public.promocion_grupo',ids,
                    '{"promocion_opcion":"id_promocion_grupo"}');
                SELECT coalesce(jsonb_agg(to_jsonb(o)), '[]') INTO opciones FROM
                    (SELECT * FROM public.promocion_opcion WHERE id_promocion_grupo=ANY(ids) FOR UPDATE) o;
                detalles := detalles || jsonb_build_object('promocion_opcion',
                    public.catalogos_filas_auditoria('public.promocion_opcion',opciones));
                PERFORM public.catalogos_comprobar_dependencias('public.promocion_opcion',
                    ARRAY(SELECT (x->>'id_promocion_opcion')::bigint FROM jsonb_array_elements(opciones) x),'{}');
                DELETE FROM public.promocion_opcion WHERE id_promocion_grupo=ANY(ids);
            END IF;
        ELSIF hija.tabla NOT IN ('producto_stock_local','proveedor_categoria','promocion_reposicion') THEN
            PERFORM public.catalogos_comprobar_dependencias(to_regclass('public.' || hija.tabla),
                ARRAY(SELECT (x->>('id_' || hija.tabla))::bigint FROM jsonb_array_elements(filas) x),'{}');
        ELSIF hija.tabla='producto_stock_local' AND EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE contype='f' AND confrelid='public.producto_stock_local'::regclass
        ) THEN
            RAISE EXCEPTION 'La configuracion de stock tiene dependencias; no se puede eliminar';
        END IF;
        EXECUTE format('DELETE FROM public.%I WHERE %I=$1',hija.tabla,hija.clave) USING p_id;
    END LOOP;
    EXECUTE format('DELETE FROM public.%I WHERE %I=$1',entidad.tabla,entidad.clave) USING p_id;
    RETURN jsonb_build_object('tabla',entidad.tabla,'registro',
        public.catalogos_fila_auditoria(to_regclass('public.' || entidad.tabla),anterior),'detalles',detalles);
EXCEPTION WHEN raise_exception THEN
    RETURN jsonb_build_object('conflicto',SQLERRM);
END
$_$;


--
-- Name: catalogos_entidad_eliminable(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_entidad_eliminable(p_entidad text) RETURNS TABLE(tabla text, clave text, opcion integer, hijas jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT e.tabla,e.clave,e.opcion,e.hijas::jsonb
    FROM (VALUES
      ('productos','producto','id_producto',4,'{"producto_stock_local":"id_producto"}'),
      ('categorias-productos','categoria_producto','id_categoria',5,'{}'),
      ('proveedores','proveedor','id_proveedor',6,'{"proveedor_categoria":"id_proveedor"}'),
      ('categorias-carta','categoria_carta','id_categoria_carta',8,'{}'),
      ('presentaciones','presentacion_venta','id_presentacion_venta',9,'{}'),
      ('subproductos','subproducto','id_subproducto',12,'{"subproducto_detalle":"id_subproducto"}'),
      ('recetas','receta','id_receta',28,'{"receta_detalle":"id_receta"}'),
      ('promociones','promocion','id_promocion',14,'{"promocion_grupo":"id_promocion","promocion_reposicion":"id_promocion"}')
    ) AS e(entidad,tabla,clave,opcion,hijas)
    WHERE e.entidad=p_entidad
$$;


--
-- Name: catalogos_fila_auditoria(regclass, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_fila_auditoria(p_tabla regclass, p_fila jsonb) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    -- Preserve the previous JSON serializer's representation of Decimal and datetime values.
    SELECT coalesce(jsonb_object_agg(a.key, CASE
        WHEN a.value = 'null'::jsonb THEN a.value
        WHEN c.atttypid = 'numeric'::regtype THEN to_jsonb(p_fila->>a.key)
        WHEN c.atttypid IN ('timestamp'::regtype, 'timestamptz'::regtype)
            THEN to_jsonb(replace(p_fila->>a.key, 'T', ' '))
        ELSE a.value
    END), '{}'::jsonb)
    FROM jsonb_each(p_fila) a
    LEFT JOIN pg_attribute c ON c.attrelid=p_tabla AND c.attname=a.key AND NOT c.attisdropped
$$;


--
-- Name: catalogos_filas_auditoria(regclass, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_filas_auditoria(p_tabla regclass, p_filas jsonb) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT coalesce(jsonb_agg(public.catalogos_fila_auditoria(p_tabla, f.fila) ORDER BY f.posicion), '[]')
    FROM jsonb_array_elements(p_filas) WITH ORDINALITY AS f(fila,posicion)
$$;


--
-- Name: catalogos_generar_codigo_producto(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_generar_codigo_producto(p_id_categoria integer) RETURNS TABLE(prefijo character varying, numero integer)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE categoria_producto
            SET siguiente_numero = siguiente_numero + 1
            WHERE id_categoria = p_id_categoria AND activo = TRUE
            RETURNING prefijo, siguiente_numero - 1 AS numero
$$;


--
-- Name: catalogos_guardar_comercial_proveedor(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_guardar_comercial_proveedor(p_datos text, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE proveedor SET datos_comerciales=CAST(p_datos AS jsonb) WHERE id_proveedor=p_id
$$;


--
-- Name: catalogos_guardar_historial_categoria_producto(integer, integer, integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_guardar_historial_categoria_producto(p_producto integer, p_anterior integer, p_nueva integer, p_usuario integer, p_motivo text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO producto_categoria_historial (
            id_producto, id_categoria_anterior, id_categoria_nueva,
            usuario_cambio, motivo
        ) VALUES (p_producto, p_anterior, p_nueva, p_usuario, p_motivo)
$$;


--
-- Name: catalogos_guardar_historial_proveedor_producto(integer, integer, integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_guardar_historial_proveedor_producto(p_producto integer, p_anterior integer, p_nuevo integer, p_usuario integer, p_motivo text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO producto_proveedor_historial (
            id_producto, id_proveedor_anterior, id_proveedor_nuevo,
            usuario_cambio, motivo
        ) VALUES (p_producto, p_anterior, p_nuevo, p_usuario, p_motivo)
$$;


--
-- Name: catalogos_listar_categorias_producto(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_listar_categorias_producto() RETURNS TABLE(id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            id_categoria,
            nombre,
            prefijo,
            siguiente_numero,
            activo
        FROM categoria_producto
        ORDER BY nombre ASC
$$;


--
-- Name: catalogos_listar_categorias_producto_detalladas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_listar_categorias_producto_detalladas() RETURNS TABLE(id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean, total_productos bigint, productos_activos bigint, productos_inactivos bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            cp.id_categoria,
            cp.nombre,
            cp.prefijo,
            cp.siguiente_numero,
            cp.activo,
            COUNT(p.id_producto) AS total_productos,
            COUNT(p.id_producto)
                FILTER (WHERE p.activo = TRUE)
                AS productos_activos,
            COUNT(p.id_producto)
                FILTER (WHERE p.activo = FALSE)
                AS productos_inactivos
        FROM categoria_producto AS cp
        LEFT JOIN producto AS p
            ON p.id_categoria = cp.id_categoria
        GROUP BY
            cp.id_categoria,
            cp.nombre,
            cp.prefijo,
            cp.siguiente_numero,
            cp.activo
        ORDER BY cp.nombre ASC
$$;


--
-- Name: catalogos_listar_productos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_listar_productos() RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, unidad character varying, stock_minimo numeric, presentacion numeric, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.id_categoria,
            cp.nombre AS categoria,
            p.id_proveedor,
            pr.nombre AS proveedor,
            p.unidad,
            p.stock_minimo,
            p.presentacion,
            p.activo
        FROM producto AS p
        INNER JOIN categoria_producto AS cp
            ON cp.id_categoria = p.id_categoria
        INNER JOIN proveedor AS pr
            ON pr.id_proveedor = p.id_proveedor
        ORDER BY
            p.nombre ASC,
            p.codigo ASC
$$;


--
-- Name: catalogos_listar_proveedores(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_listar_proveedores() RETURNS TABLE(id_proveedor integer, nombre character varying, activo boolean, datos_comerciales jsonb, ids_categorias integer[])
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            id_proveedor,
            nombre,
            activo,
            datos_comerciales,
            ARRAY(SELECT pc.id_categoria FROM public.catalogos_origen_categorias_proveedor() pc
                  WHERE pc.id_proveedor = proveedor.id_proveedor
                  ORDER BY pc.id_categoria) AS ids_categorias
        FROM proveedor
        ORDER BY nombre ASC
$$;


--
-- Name: catalogos_listar_proveedores_detallados(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_listar_proveedores_detallados(p_id integer) RETURNS SETOF character varying
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT cp.nombre FROM public.catalogos_origen_categorias_proveedor() pc
            JOIN categoria_producto cp USING(id_categoria)
            WHERE pc.id_proveedor = p_id ORDER BY cp.nombre
$$;


--
-- Name: catalogos_obtener_categoria(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_obtener_categoria(p_id_categoria integer) RETURNS TABLE(id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_categoria, nombre, prefijo,
                   siguiente_numero, activo
            FROM categoria_producto
            WHERE id_categoria = p_id_categoria
$$;


--
-- Name: catalogos_obtener_categoria_bloqueado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_obtener_categoria_bloqueado(p_id_categoria integer) RETURNS TABLE(id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_categoria, nombre, prefijo,
                   siguiente_numero, activo
            FROM categoria_producto
            WHERE id_categoria = p_id_categoria FOR UPDATE
$$;


--
-- Name: catalogos_obtener_producto(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_obtener_producto(p_id_producto integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, id_categoria integer, id_proveedor integer, unidad character varying, stock_minimo numeric, presentacion numeric, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto, codigo, nombre, id_categoria,
                   id_proveedor, unidad, stock_minimo,
                   presentacion, activo
            FROM producto
            WHERE id_producto = p_id_producto
$$;


--
-- Name: catalogos_obtener_producto_bloqueado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_obtener_producto_bloqueado(p_id_producto integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, id_categoria integer, id_proveedor integer, unidad character varying, stock_minimo numeric, presentacion numeric, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto, codigo, nombre, id_categoria,
                   id_proveedor, unidad, stock_minimo,
                   presentacion, activo
            FROM producto
            WHERE id_producto = p_id_producto FOR UPDATE
$$;


--
-- Name: catalogos_obtener_proveedor(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_obtener_proveedor(p_id_proveedor integer) RETURNS TABLE(id_proveedor integer, nombre character varying, activo boolean, datos_comerciales jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_proveedor, nombre, activo, datos_comerciales
            FROM proveedor
            WHERE id_proveedor = p_id_proveedor
$$;


--
-- Name: catalogos_obtener_proveedor_bloqueado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_obtener_proveedor_bloqueado(p_id_proveedor integer) RETURNS TABLE(id_proveedor integer, nombre character varying, activo boolean, datos_comerciales jsonb)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_proveedor, nombre, activo, datos_comerciales
            FROM proveedor
            WHERE id_proveedor = p_id_proveedor FOR UPDATE
$$;


--
-- Name: catalogos_origen_categorias_proveedor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_origen_categorias_proveedor() RETURNS TABLE(id_proveedor integer, id_categoria integer)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    IF to_regclass('public.proveedor_categoria') IS NOT NULL THEN
        RETURN QUERY SELECT pc.id_proveedor, pc.id_categoria FROM public.proveedor_categoria pc;
    ELSE
        RETURN QUERY SELECT DISTINCT p.id_proveedor, p.id_categoria FROM public.producto p;
    END IF;
END;
$$;


--
-- Name: catalogos_producto_repetido(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_producto_repetido(p_nombre text, p_excluir_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
                SELECT 1 FROM producto
                WHERE LOWER(BTRIM(nombre)) = LOWER(BTRIM(p_nombre))
                  AND (p_excluir_id IS NULL OR id_producto <> p_excluir_id)
            )
$$;


--
-- Name: catalogos_productos_categoria(integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_productos_categoria(p_id_categoria integer, p_solo_activos boolean) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto, p.codigo, p.nombre, p.activo
            FROM producto p
            WHERE p.id_categoria = p_id_categoria AND (NOT p_solo_activos OR p.activo) ORDER BY p.nombre
$$;


--
-- Name: catalogos_productos_proveedor(integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_productos_proveedor(p_id_proveedor integer, p_solo_activos boolean) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, activo boolean, id_categoria integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto, p.codigo, p.nombre, p.activo,
                   p.id_categoria
            FROM producto p
            WHERE p.id_proveedor = p_id_proveedor AND (NOT p_solo_activos OR p.activo) ORDER BY p.nombre
$$;


--
-- Name: catalogos_proveedor_repetido(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_proveedor_repetido(p_nombre text, p_excluir_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
                SELECT 1 FROM proveedor
                WHERE LOWER(BTRIM(nombre)) = LOWER(BTRIM(p_nombre))
                  AND (p_excluir_id IS NULL OR id_proveedor <> p_excluir_id)
            )
$$;


--
-- Name: catalogos_reasignar_categoria_productos_1(integer, integer, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_reasignar_categoria_productos_1(p_nueva integer, p_anterior integer, p_ids integer[]) RETURNS SETOF integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE producto
            SET id_categoria = p_nueva
            WHERE id_categoria = p_anterior
              AND id_producto = ANY(p_ids)
            RETURNING id_producto
$$;


--
-- Name: catalogos_reasignar_categoria_productos_2(integer, integer, integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_reasignar_categoria_productos_2(p_id_producto integer, p_anterior integer, p_nueva integer, p_usuario integer, p_motivo text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO producto_categoria_historial (
                    id_producto, id_categoria_anterior,
                    id_categoria_nueva, usuario_cambio, motivo
                ) VALUES (
                    p_id_producto, p_anterior, p_nueva, p_usuario, p_motivo
                )
$$;


--
-- Name: catalogos_reasignar_proveedor_productos_1(integer, integer, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_reasignar_proveedor_productos_1(p_nuevo integer, p_anterior integer, p_ids integer[]) RETURNS SETOF integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE producto
            SET id_proveedor = p_nuevo
            WHERE id_proveedor = p_anterior
              AND id_producto = ANY(p_ids)
            RETURNING id_producto
$$;


--
-- Name: catalogos_reasignar_proveedor_productos_2(integer, integer, integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_reasignar_proveedor_productos_2(p_id_producto integer, p_anterior integer, p_nuevo integer, p_usuario integer, p_motivo text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO producto_proveedor_historial (
                    id_producto, id_proveedor_anterior,
                    id_proveedor_nuevo, usuario_cambio, motivo
                ) VALUES (
                    p_id_producto, p_anterior, p_nuevo, p_usuario, p_motivo
                )
$$;


--
-- Name: catalogos_ruc_proveedor_repetido(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_ruc_proveedor_repetido(p_ruc text, p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS(SELECT 1 FROM proveedor WHERE datos_comerciales->>'ruc'=p_ruc AND (p_id IS NULL OR id_proveedor<>p_id))
$$;


--
-- Name: catalogos_stock_guardar_limites(integer, integer, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_stock_guardar_limites(p_id integer, p_local integer, p_minimo numeric, p_maximo numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO producto_stock_local (id_producto, id_local, stock_minimo, stock_maximo)
            VALUES (p_id, p_local, p_minimo, p_maximo)
            ON CONFLICT (id_producto, id_local) DO UPDATE
            SET stock_minimo = EXCLUDED.stock_minimo, stock_maximo = EXCLUDED.stock_maximo
$$;


--
-- Name: catalogos_stock_limites(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_stock_limites(p_local integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, categoria character varying, unidad character varying, stock_minimo numeric, stock_maximo numeric, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto, p.codigo, p.nombre, c.nombre AS categoria,
               p.unidad, COALESCE(sl.stock_minimo, 0) AS stock_minimo,
               sl.stock_maximo, p.activo
        FROM producto p
        JOIN categoria_producto c ON c.id_categoria = p.id_categoria
        LEFT JOIN producto_stock_local sl
          ON sl.id_producto = p.id_producto AND sl.id_local = p_local
        ORDER BY p.nombre
$$;


--
-- Name: catalogos_stock_limites_bloqueados(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_stock_limites_bloqueados(p_local integer, p_id integer) RETURNS TABLE(id_producto integer, codigo character varying, stock_minimo numeric, stock_maximo numeric)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto, p.codigo, COALESCE(sl.stock_minimo, 0) AS stock_minimo,
                   sl.stock_maximo
            FROM producto p
            LEFT JOIN producto_stock_local sl
              ON sl.id_producto = p.id_producto AND sl.id_local = p_local
            WHERE p.id_producto = p_id FOR UPDATE OF p
$$;


--
-- Name: catalogos_stock_local_asignado(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_stock_local_asignado(p_usuario integer, p_local integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
                    SELECT 1 FROM usuario_local ul
                    JOIN local l ON l.id_local = ul.id_local
                    WHERE ul.id_usuario = p_usuario AND ul.id_local = p_local
                      AND ul.estado_registro = 1 AND l.estado_registro = 1
                )
$$;


--
-- Name: catalogos_stock_perfil_autorizado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalogos_stock_perfil_autorizado(p_perfil integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (SELECT FROM public.perfiles p
      WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.administra_limites_stock)
$$;


--
-- Name: clientes_buscar(integer, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clientes_buscar(p_local integer, p_q text, p_patron text, p_limite integer, p_offset integer) RETURNS TABLE(id_cliente uuid, tipo_persona character varying, tipo_documento character varying, numero_documento character varying, nombre character varying, direccion character varying, email character varying, telefono character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT c.id_cliente,c.tipo_persona,c.tipo_documento,c.numero_documento,
           c.nombre,c.direccion,c.email,c.telefono
    FROM public.cliente_comercial c
    WHERE c.id_local=p_local AND (p_q='' OR c.numero_documento=p_q OR c.nombre ILIKE p_patron ESCAPE chr(92))
    ORDER BY c.nombre,c.id_cliente LIMIT p_limite OFFSET p_offset
$$;


--
-- Name: clientes_crear(text, integer, text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clientes_crear(p_id text, p_local integer, p_persona text, p_documento text, p_numero text, p_nombre text, p_direccion text, p_email text, p_telefono text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    INSERT INTO public.cliente_comercial
        (id_cliente,id_local,tipo_persona,tipo_documento,numero_documento,nombre,direccion,email,telefono)
    VALUES (p_id::uuid,p_local,p_persona,p_documento,p_numero,p_nombre,p_direccion,p_email,p_telefono)
$$;


--
-- Name: clientes_directorio_disponible(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clientes_directorio_disponible() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT to_regclass('public.cliente_comercial') IS NOT NULL
$$;


--
-- Name: clientes_obtener(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clientes_obtener(p_local integer, p_id text) RETURNS TABLE(id_cliente uuid, tipo_persona character varying, tipo_documento character varying, numero_documento character varying, nombre character varying, direccion character varying, email character varying, telefono character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT c.id_cliente,c.tipo_persona,c.tipo_documento,c.numero_documento,
           c.nombre,c.direccion,c.email,c.telefono
    FROM public.cliente_comercial c WHERE c.id_local=p_local AND c.id_cliente=p_id::uuid
$$;


--
-- Name: clientes_perfil_autorizado(integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clientes_perfil_autorizado(p_perfil integer, p_salon boolean) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT FROM public.perfiles p WHERE p.id_perfil=p_perfil AND p.estado_registro=1
        AND CASE WHEN p_salon THEN p.accede_clientes_salon ELSE p.accede_directorio_clientes END
    )
$$;


--
-- Name: compras_bloquear_codigo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_bloquear_codigo() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock(
            hashtext('orden_compra_codigo')
        )
$$;


--
-- Name: compras_cambiar_estado_orden_historial(text, text, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_cambiar_estado_orden_historial(p_estado text, p_motivo text, p_id_usuario integer, p_id_orden integer, p_id_local_actual integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE orden_compra
            SET estado_orden_compra = p_estado,
                motivo_cierre = p_motivo,
                usuario_modificacion = p_id_usuario,
                fecha_modificacion = (
                    CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'
                )
            WHERE id_orden_compra = p_id_orden AND id_local=p_id_local_actual
$$;


--
-- Name: compras_crear_cabecera_orden(integer, text, text, integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_crear_cabecera_orden(p_id_local_actual integer, p_codigo text, p_estado text, p_id_usuario integer, p_fecha_registro date) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO orden_compra (
                id_local,
                codigo,
                estado_orden_compra,
                usuario_registro,
                fecha_registro
            ) VALUES (
                p_id_local_actual,
                p_codigo,
                p_estado,
                p_id_usuario,
                p_fecha_registro
            )
            RETURNING id_orden_compra
$$;


--
-- Name: compras_crear_detalle_orden(integer, integer, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_crear_detalle_orden(p_id_producto integer, p_id_orden integer, p_cantidad numeric, p_id_local_actual integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO orden_compra_detalle (
                id_proveedor,
                id_orden_compra,
                id_producto,
                cantidad_solicitada
            ) SELECT
                (SELECT id_proveedor FROM producto WHERE id_producto=p_id_producto),
                p_id_orden,
                p_id_producto,
                p_cantidad
             WHERE EXISTS (SELECT 1 FROM public.orden_compra o WHERE o.id_orden_compra=p_id_orden AND o.id_local=p_id_local_actual)
$$;


--
-- Name: compras_enviar_orden_borrador(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_enviar_orden_borrador(p_usuario integer, p_id integer, p_id_local_actual integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE orden_compra SET estado_orden_compra='ENVIADA',
        fecha_registro=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date,
        usuario_modificacion=p_usuario,fecha_modificacion=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')
        WHERE id_orden_compra=p_id AND estado_orden_compra='BORRADOR' AND id_local=p_id_local_actual
$$;


--
-- Name: compras_estado_orden_valido(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_estado_orden_valido(p_estado text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1 FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([^'']+)''::character varying', 'g') AS valor
    WHERE c.conname='ck_orden_estado' AND c.conrelid='public.orden_compra'::regclass AND valor[1]=p_estado
)
$$;


--
-- Name: compras_guardar_historial_estado_orden(integer, text, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_guardar_historial_estado_orden(p_id_orden integer, p_estado_anterior text, p_estado_nuevo text, p_motivo text, p_id_usuario integer, p_id_local_actual integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO orden_compra_estado_historial (
                id_orden_compra,
                estado_anterior,
                estado_nuevo,
                motivo,
                usuario_modificacion
            ) SELECT
                p_id_orden,
                p_estado_anterior,
                p_estado_nuevo,
                p_motivo,
                p_id_usuario
             WHERE EXISTS (SELECT 1 FROM public.orden_compra o WHERE o.id_orden_compra=p_id_orden AND o.id_local=p_id_local_actual)
$$;


--
-- Name: compras_listar_historial_ordenes(integer, date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_listar_historial_ordenes(p_id_local_actual integer, p_fecha_desde date, p_fecha_hasta date, p_estado text) RETURNS TABLE(id_orden_compra integer, codigo character varying, estado_orden_compra character varying, fecha_registro date, registrado_por text, total_productos bigint, productos_con_recepcion bigint, productos_completos bigint, productos_pendientes bigint, motivo_cierre character varying, fecha_modificacion timestamp without time zone, modificado_por text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH recibido_por_producto AS (
            SELECT
                fr.id_orden_compra,
                frd.id_producto,
                SUM(frd.cantidad_recibida) AS cantidad_recibida
            FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
            JOIN factura_recepcion_detalle frd
                ON frd.id_factura_recepcion =
                   fr.id_factura_recepcion
            GROUP BY
                fr.id_orden_compra,
                frd.id_producto
        ),
        avance_por_orden AS (
            SELECT
                ocd.id_orden_compra,
                COUNT(*) AS total_productos,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0) > 0
                ) AS productos_con_recepcion,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0)
                          >= ocd.cantidad_solicitada
                ) AS productos_completos,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0)
                          < ocd.cantidad_solicitada
                ) AS productos_pendientes
            FROM orden_compra_detalle ocd
            LEFT JOIN recibido_por_producto rpp
                ON rpp.id_orden_compra = ocd.id_orden_compra
               AND rpp.id_producto = ocd.id_producto
            GROUP BY ocd.id_orden_compra
        )
        SELECT
            oc.id_orden_compra,
            oc.codigo,
            oc.estado_orden_compra,
            oc.fecha_registro,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS registrado_por,
            COALESCE(apo.total_productos, 0)
                AS total_productos,
            COALESCE(apo.productos_con_recepcion, 0)
                AS productos_con_recepcion,
            COALESCE(apo.productos_completos, 0)
                AS productos_completos,
            COALESCE(apo.productos_pendientes, 0)
                AS productos_pendientes,
            oc.motivo_cierre,
            oc.fecha_modificacion,
            NULLIF(BTRIM(CONCAT_WS(
                ' ',
                um.nombres,
                um.apellido_paterno,
                um.apellido_materno
            )), '') AS modificado_por
        FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
        JOIN usuario u
            ON u.id_usuario = oc.usuario_registro
        LEFT JOIN usuario um
            ON um.id_usuario = oc.usuario_modificacion
        LEFT JOIN avance_por_orden apo
            ON apo.id_orden_compra = oc.id_orden_compra
        WHERE (
            CAST(p_fecha_desde AS DATE) IS NULL
            OR oc.fecha_registro >= CAST(p_fecha_desde AS DATE)
        )
          AND (
            CAST(p_fecha_hasta AS DATE) IS NULL
            OR oc.fecha_registro <= CAST(p_fecha_hasta AS DATE)
          )
          AND (
            CAST(p_estado AS VARCHAR) IS NULL
            OR oc.estado_orden_compra = CAST(p_estado AS VARCHAR)
          )
        ORDER BY
            oc.fecha_registro DESC NULLS LAST,
            oc.id_orden_compra DESC
$$;


--
-- Name: compras_obtener_detalle_orden_historial(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_obtener_detalle_orden_historial(p_id_local_actual integer, p_id_orden integer) RETURNS TABLE(id_orden_compra_detalle integer, id_producto integer, codigo character varying, nombre character varying, unidad character varying, id_proveedor integer, proveedor character varying, cantidad_solicitada numeric, cantidad_recibida numeric, cantidad_pendiente numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ocd.id_orden_compra_detalle,
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            pr.id_proveedor,
            pr.nombre AS proveedor,
            ocd.cantidad_solicitada,
            COALESCE((
                SELECT SUM(frd.cantidad_recibida)
                FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
                JOIN factura_recepcion_detalle frd
                    ON frd.id_factura_recepcion =
                       fr.id_factura_recepcion
                WHERE fr.id_orden_compra = ocd.id_orden_compra
                  AND frd.id_producto = ocd.id_producto
            ), 0) AS cantidad_recibida,
            GREATEST(
                ocd.cantidad_solicitada - COALESCE((
                    SELECT SUM(frd.cantidad_recibida)
                    FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
                    JOIN factura_recepcion_detalle frd
                        ON frd.id_factura_recepcion =
                           fr.id_factura_recepcion
                    WHERE fr.id_orden_compra = ocd.id_orden_compra
                      AND frd.id_producto = ocd.id_producto
                ), 0),
                0
            ) AS cantidad_pendiente
        FROM orden_compra_detalle ocd
        JOIN producto p
            ON p.id_producto = ocd.id_producto
        JOIN proveedor pr
            ON pr.id_proveedor = ocd.id_proveedor
        WHERE ocd.id_orden_compra = p_id_orden AND EXISTS (SELECT 1 FROM public.orden_compra o WHERE o.id_orden_compra=ocd.id_orden_compra AND o.id_local=p_id_local_actual)
        ORDER BY pr.nombre, p.nombre
$$;


--
-- Name: compras_obtener_orden_historial(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_obtener_orden_historial(p_id_local_actual integer, p_id_orden integer) RETURNS TABLE(id_orden_compra integer, codigo character varying, estado_orden_compra character varying, fecha_registro date, motivo_cierre character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            id_orden_compra,
            codigo,
            estado_orden_compra,
            fecha_registro,
            motivo_cierre
        FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) orden_compra
        WHERE id_orden_compra = p_id_orden
$$;


--
-- Name: compras_obtener_orden_historial_bloqueada(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_obtener_orden_historial_bloqueada(p_id_local_actual integer, p_id_orden integer) RETURNS TABLE(id_orden_compra integer, codigo character varying, estado_orden_compra character varying, fecha_registro date, motivo_cierre character varying)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            id_orden_compra,
            codigo,
            estado_orden_compra,
            fecha_registro,
            motivo_cierre
        FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) orden_compra
        WHERE id_orden_compra = p_id_orden FOR UPDATE
$$;


--
-- Name: compras_obtener_total_recibido_orden(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_obtener_total_recibido_orden(p_id_local_actual integer, p_id_orden integer) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT COALESCE(SUM(frd.cantidad_recibida), 0)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion = fr.id_factura_recepcion
        WHERE fr.id_orden_compra = p_id_orden
$$;


--
-- Name: compras_producto_activo_existe(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_producto_activo_existe(p_id_producto integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
                SELECT 1
                FROM producto
                WHERE id_producto = p_id_producto
                  AND activo = TRUE
            )
$$;


--
-- Name: compras_productos_sugeridos_historico(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_productos_sugeridos_historico(p_local integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, presentacion numeric, stock_minimo numeric, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, stock_actual numeric, consumo_total numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH fecha_referencia AS (
            -- Obtiene la fecha de la última orden enviada/recepcionada o la última recepción
            SELECT COALESCE(
                (
                    SELECT MAX(fecha_registro)
                    FROM (SELECT * FROM orden_compra WHERE id_local=p_local) orden_compra
                    WHERE estado_orden_compra IN ('ENVIADA', 'RECEPCIONADA', 'RECEPCION_PARCIAL')
                ),
                (
                    SELECT MIN(fecha_recepcion)
                    FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_local) factura_recepcion
                ),
                CURRENT_DATE
            ) AS fecha_inicio
        ),
        ultimo_inventario AS (
            -- Obtiene la fecha del último inventario de cierre registrado
            SELECT MAX(fecha_inventario) AS fecha_fin
            FROM (SELECT * FROM inventario_cierre WHERE id_local=p_local) inventario_cierre
            WHERE estado_inventario = 'CERRADO'
              AND fecha_inventario <= CURRENT_DATE
        ),
        consumo_calculado AS (
            -- Calcula todo lo movido (consumo) entre el lapso definido
            SELECT
                p.id_producto,
                COALESCE(inv_inicio.stock_contado, 0) AS stock_inicial,
                COALESCE(inv_fin.stock_contado, 0) AS stock_final,
                COALESCE(recepciones.cantidad_recibida, 0) AS entradas_compras,
                COALESCE(mov.entradas, 0) AS entradas_movimientos,
                COALESCE(mov.salidas, 0) AS salidas_movimientos,

                -- Consumo total transcurrido = (Stock Inicial + Entradas Compras + Entradas Movs) - (Stock Final + Salidas Movs)
                GREATEST(
                    0,
                    (COALESCE(inv_inicio.stock_contado, 0) + COALESCE(recepciones.cantidad_recibida, 0) + COALESCE(mov.entradas, 0))
                    - (COALESCE(inv_fin.stock_contado, 0) + COALESCE(mov.salidas, 0))
                ) AS consumo_total
            FROM producto p
            CROSS JOIN fecha_referencia fr
            CROSS JOIN ultimo_inventario ui
            -- Stock según el primer inventario del período
            LEFT JOIN LATERAL (
                SELECT icd.stock_contado
                FROM inventario_cierre_detalle icd
                JOIN (SELECT * FROM inventario_cierre WHERE id_local=p_local) ic ON ic.id_inventario_cierre = icd.id_inventario_cierre
                WHERE icd.id_producto = p.id_producto
                  AND ic.estado_inventario = 'CERRADO'
                  AND ic.fecha_inventario <= fr.fecha_inicio
                ORDER BY ic.fecha_inventario DESC
                LIMIT 1
            ) inv_inicio ON TRUE
            -- Stock según el último inventario de cierre registrado
            LEFT JOIN LATERAL (
                SELECT icd.stock_contado
                FROM inventario_cierre_detalle icd
                JOIN (SELECT * FROM inventario_cierre WHERE id_local=p_local) ic ON ic.id_inventario_cierre = icd.id_inventario_cierre
                WHERE icd.id_producto = p.id_producto
                  AND ic.estado_inventario = 'CERRADO'
                  AND ic.fecha_inventario = ui.fecha_fin
                ORDER BY icd.id_inventario_cierre DESC
                LIMIT 1
            ) inv_fin ON TRUE
            -- Entradas por compras en el período
            LEFT JOIN LATERAL (
                SELECT SUM(frd.cantidad_recibida) AS cantidad_recibida
                FROM factura_recepcion_detalle frd
                JOIN (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_local) f ON f.id_factura_recepcion = frd.id_factura_recepcion
                WHERE frd.id_producto = p.id_producto
                  AND f.fecha_recepcion > fr.fecha_inicio
                  AND f.fecha_recepcion <= ui.fecha_fin
            ) recepciones ON TRUE
            -- Entradas y salidas manuales de inventario en el período
            LEFT JOIN LATERAL (
                SELECT
                    SUM(CASE WHEN mi.tipo_movimiento = 'ENTRADA' THEN mid.cantidad ELSE 0 END) AS entradas,
                    SUM(CASE WHEN mi.tipo_movimiento = 'SALIDA' THEN mid.cantidad ELSE 0 END) AS salidas
                FROM movimiento_inventario_detalle mid
                JOIN (SELECT * FROM movimiento_inventario WHERE id_local=p_local) mi ON mi.id_movimiento_inventario = mid.id_movimiento_inventario
                WHERE mid.id_producto = p.id_producto
                  AND mi.fecha_movimiento > fr.fecha_inicio
                  AND mi.fecha_movimiento <= ui.fecha_fin
            ) mov ON TRUE
        )
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            p.presentacion,
            public.stock_minimo_por_local(p.id_producto, p_local, p.stock_minimo) AS stock_minimo,
            cp.id_categoria,
            cp.nombre AS categoria,
            pr.id_proveedor,
            pr.nombre AS proveedor,
            cc.stock_final AS stock_actual,
            cc.consumo_total
        FROM producto p
        JOIN categoria_producto cp ON cp.id_categoria = p.id_categoria
        JOIN proveedor pr ON pr.id_proveedor = p.id_proveedor
        LEFT JOIN consumo_calculado cc ON cc.id_producto = p.id_producto
        WHERE p.activo = TRUE
          AND cp.activo = TRUE
          AND pr.activo = TRUE
        ORDER BY cp.nombre, p.nombre
$$;


--
-- Name: compras_productos_sugeridos_operativo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_productos_sugeridos_operativo(p_local integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, presentacion numeric, stock_minimo numeric, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, stock_actual numeric, consumo_total numeric, origen_consumo text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,p.presentacion,
            coalesce(sl.stock_minimo,0) stock_minimo,cp.id_categoria,cp.nombre categoria,
            pr.id_proveedor,pr.nombre proveedor,s.stock_actual,
            coalesce(e.consumo,0) consumo_total, 'ultimos_30_dias' origen_consumo
            FROM producto p JOIN categoria_producto cp USING(id_categoria) JOIN proveedor pr USING(id_proveedor)
            JOIN inventario_stock_teorico s ON s.id_producto=p.id_producto AND s.id_local=p_local
            LEFT JOIN producto_stock_local sl ON sl.id_producto=p.id_producto AND sl.id_local=p_local
            LEFT JOIN (SELECT id_producto,sum(greatest(-cantidad,0)) consumo FROM inventario_evento
              WHERE id_local=p_local AND registrado_en>=clock_timestamp()-interval '30 days'
              GROUP BY id_producto) e ON e.id_producto=p.id_producto
            WHERE p.activo AND cp.activo AND pr.activo ORDER BY cp.nombre,p.nombre
$$;


--
-- Name: compras_siguiente_numero_orden(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compras_siguiente_numero_orden() RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
SELECT COALESCE(MAX(
            CASE
                WHEN codigo ~ '^OC-[0-9]+$'
                THEN SUBSTRING(codigo FROM 4)::INTEGER
                ELSE 0
            END
        ), 0) + 1
        FROM orden_compra
$_$;


--
-- Name: configuracion_motivo_movimiento(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.configuracion_motivo_movimiento(p_codigo text) RETURNS TABLE(tipo_movimiento character varying, requiere_local boolean, requiere_proveedor boolean, registrable boolean, motivo_recepcion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT m.tipo_movimiento,m.requiere_local,m.requiere_proveedor,m.registrable,m.motivo_recepcion FROM public.movimiento_motivo m WHERE m.codigo=p_codigo AND m.activo
$$;


--
-- Name: facturacion_abrir_intento(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_abrir_intento(p_id uuid, p_number integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO fact_api_intento(id_operacion,numero)
            VALUES(p_id,p_number)
$$;


--
-- Name: facturacion_actualizar_intentos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_actualizar_intentos(p_id uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_operacion SET intentos=(SELECT COALESCE(max(numero),0)
            FROM fact_api_intento WHERE id_operacion=p_id) WHERE id_operacion=p_id
$$;


--
-- Name: facturacion_actualizar_pdf(text, text, integer, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_actualizar_pdf(p_path text, p_hash text, p_size integer, p_id uuid, p_format text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_archivo SET ruta=p_path,sha256=p_hash,bytes=p_size
                    WHERE id_documento=p_id AND formato=p_format
$$;


--
-- Name: facturacion_actualizar_supervisor(uuid, integer, integer, integer, integer, integer, integer, integer, numeric, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_actualizar_supervisor(p_id uuid, p_pid integer, p_minimum integer, p_maximum integer, p_active integer, p_desired integer, p_ready integer, p_busy integer, p_oldest numeric, p_paused boolean, p_workers text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO fact_api_escalado
            (id,supervisor,pid,minimo,maximo,activos,objetivo,listos,ocupados,espera_segundos,pausado,workers,actualizado_en)
            VALUES(1,p_id,p_pid,p_minimum,p_maximum,p_active,p_desired,p_ready,p_busy,p_oldest,p_paused,CAST(p_workers AS jsonb),now())
            ON CONFLICT(id) DO UPDATE SET supervisor=EXCLUDED.supervisor,pid=EXCLUDED.pid,
            minimo=EXCLUDED.minimo,maximo=EXCLUDED.maximo,activos=EXCLUDED.activos,objetivo=EXCLUDED.objetivo,
            listos=EXCLUDED.listos,ocupados=EXCLUDED.ocupados,espera_segundos=EXCLUDED.espera_segundos,
            pausado=EXCLUDED.pausado,workers=EXCLUDED.workers,actualizado_en=now()
$$;


--
-- Name: facturacion_adquirir_liderazgo(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_adquirir_liderazgo(p_group integer, p_identity integer) RETURNS boolean
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_try_advisory_lock(p_group,p_identity)
$$;


--
-- Name: facturacion_adquirir_slot(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_adquirir_slot(p_group integer, p_slot integer) RETURNS boolean
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_try_advisory_lock(p_group,p_slot)
$$;


--
-- Name: facturacion_archivo_por_local(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_archivo_por_local(p_id uuid, p_local integer) RETURNS TABLE(id_archivo uuid, id_documento uuid, formato text, ruta text, sha256 character, bytes integer, creado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT a.* FROM fact_api_archivo a JOIN fact_api_documento d USING(id_documento)
        WHERE a.id_archivo=p_id AND d.id_local=p_local
$$;


--
-- Name: facturacion_bloquear_compra(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_bloquear_compra(p_id integer, p_local integer) RETURNS TABLE(id_factura_recepcion integer, id_orden_compra integer, id_proveedor integer, numero_factura character varying, fecha_recepcion date, usuario_recepcion integer, datos_factura jsonb, entregas jsonb, id_local integer, codigo_orden character varying)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT f.*,o.id_local,o.codigo AS codigo_orden
            FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
            WHERE f.id_factura_recepcion=p_id AND o.id_local=p_local FOR UPDATE OF f
$$;


--
-- Name: facturacion_bloquear_fuente(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_bloquear_fuente(p_key text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock(hashtext(p_key))
$$;


--
-- Name: facturacion_bloquear_pdf_actualizable(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_bloquear_pdf_actualizable(p_id uuid) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_operacion FROM fact_api_operacion
                WHERE id_operacion=p_id AND estado='COMPLETADO' AND NOT obsoleto FOR UPDATE
$$;


--
-- Name: facturacion_bloquear_procesada(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_bloquear_procesada(p_id uuid, p_lease uuid) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_operacion FROM fact_api_operacion
        WHERE id_operacion=p_id AND lease_token=p_lease AND estado='PROCESANDO' FOR UPDATE
$$;


--
-- Name: facturacion_bloquear_venta(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_bloquear_venta(p_id bigint, p_local integer) RETURNS TABLE(id_cobro bigint, id_local integer, id_usuario integer, mesa character varying, clave uuid, solicitud_hash character varying, tipo character varying, metodo character varying, documento character varying, cliente character varying, total numeric, comprobante jsonb, id_movimiento integer, creado_en timestamp with time zone, id_jornada bigint, id_cliente uuid)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM salon_cobro WHERE id_cobro=p_id AND id_local=p_local FOR UPDATE
$$;


--
-- Name: facturacion_cerrar_intentos_agotados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_cerrar_intentos_agotados() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_intento i SET fin=now(),resultado='LEASE_VENCIDO'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.estado='REVISION' AND o.intentos>=o.max_intentos
$$;


--
-- Name: facturacion_cerrar_intentos_fuente(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_cerrar_intentos_fuente(p_origin text, p_source bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_intento i SET fin=now(),resultado='FUENTE_MODIFICADA'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.origen=p_origin AND o.id_origen=p_source AND o.obsoleto
$$;


--
-- Name: facturacion_cerrar_intentos_operacion(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_cerrar_intentos_operacion(p_id uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_intento SET fin=now(),resultado='LEASE_VENCIDO'
            WHERE id_operacion=p_id AND fin IS NULL
$$;


--
-- Name: facturacion_cerrar_intentos_venta(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_cerrar_intentos_venta(p_id bigint, p_local integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_intento i SET fin=now(),resultado='FUENTE_ANULADA'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.origen='VENTA' AND o.id_origen=p_id AND o.id_local=p_local AND o.obsoleto
$$;


--
-- Name: facturacion_compra_disponible(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_compra_disponible(p_id integer, p_local integer) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT 1 FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
        WHERE f.id_factura_recepcion=p_id AND o.id_local=p_local
$$;


--
-- Name: facturacion_configuracion_activa(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_configuracion_activa(p_local integer) RETURNS TABLE(id_local integer, activo boolean, ambiente text, empresa jsonb, serie_factura character varying, serie_boleta character varying, tasa_igv numeric, creado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM fact_api_config WHERE id_local=p_local AND activo
$$;


--
-- Name: facturacion_conteo_estados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_conteo_estados() RETURNS TABLE(id_local integer, origen text, estado text, cantidad bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_local,origen,estado,count(*) AS cantidad FROM fact_api_operacion GROUP BY id_local,origen,estado ORDER BY 1,2
$$;


--
-- Name: facturacion_encolar(uuid, integer, text, bigint, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_encolar(p_id uuid, p_local integer, p_origin text, p_source bigint, p_version integer, p_payload text, p_hash text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO fact_api_operacion
        (id_operacion,id_local,origen,id_origen,version,payload,payload_hash)
        VALUES(p_id,p_local,p_origin,p_source,p_version,CAST(p_payload AS jsonb),p_hash)
$$;


--
-- Name: facturacion_es_supervisor(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_es_supervisor(p_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS(SELECT 1 FROM fact_api_escalado
        WHERE id=1 AND supervisor=p_id AND actualizado_en>now()-interval '20 seconds')
$$;


--
-- Name: facturacion_escalado_instalado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_escalado_instalado() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.fact_api_escalado') IS NOT NULL
$$;


--
-- Name: facturacion_estadisticas_cola(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_estadisticas_cola() RETURNS TABLE(ready bigint, busy bigint, oldest numeric, blocked boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
        count(*) FILTER(WHERE (estado IN ('PENDIENTE','REINTENTO') AND disponible_en<=now())
            OR (estado='PROCESANDO' AND lease_hasta<now())) AS ready,
        count(*) FILTER(WHERE estado='PROCESANDO' AND lease_hasta>=now()) AS busy,
        COALESCE(extract(epoch FROM now()-min(disponible_en) FILTER(WHERE estado IN ('PENDIENTE','REINTENTO')
            AND disponible_en<=now())),0) AS oldest,
        EXISTS(SELECT 1 FROM fact_api_circuito WHERE abierto_hasta>now()) AS blocked
        FROM fact_api_operacion WHERE NOT obsoleto AND (intentos<max_intentos
            OR (estado='PROCESANDO' AND lease_hasta>=now()))
$$;


--
-- Name: facturacion_estado_fuente(integer, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_estado_fuente(p_local integer, p_origin text, p_source bigint) RETURNS TABLE(id_operacion uuid, version integer, estado text, intentos integer, ultimo_error text, obsoleto boolean, creado_en timestamp with time zone, actualizado_en timestamp with time zone, id_documento uuid, numero text, estado_documento text, archivos jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT o.id_operacion,o.version,o.estado,o.intentos,o.ultimo_error,o.obsoleto,
        o.creado_en,o.actualizado_en,d.id_documento,d.numero,d.estado AS estado_documento,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id_archivo,'formato',a.formato))
            FROM fact_api_archivo a WHERE a.id_documento=d.id_documento),'[]'::jsonb) AS archivos
        FROM fact_api_operacion o LEFT JOIN fact_api_documento d USING(id_operacion)
        WHERE o.id_local=p_local AND o.origen=p_origin AND o.id_origen=p_source ORDER BY o.version DESC
$$;


--
-- Name: facturacion_finalizar_intento(numeric, integer, text, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_finalizar_intento(p_duration numeric, p_status integer, p_state text, p_id uuid, p_number integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_intento SET fin=now(),duracion_ms=p_duration,
        http_status=p_status,resultado=p_state WHERE id_operacion=p_id AND numero=p_number
$$;


--
-- Name: facturacion_finalizar_operacion(text, integer, text, numeric, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_finalizar_operacion(p_state text, p_status integer, p_error text, p_delay numeric, p_id uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_operacion SET estado=p_state,ultimo_http=p_status,
        ultimo_error=p_error,disponible_en=now()+make_interval(secs=>CAST(p_delay AS double precision)),
        lease_hasta=NULL,lease_token=NULL,actualizado_en=now() WHERE id_operacion=p_id
$$;


--
-- Name: facturacion_fuentes_ejemplo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_fuentes_ejemplo() RETURNS TABLE(origin text, id_local integer, source bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT 'VENTA' AS origin,id_local,max(id_cobro) AS source
                FROM salon_cobro WHERE NOT(comprobante ? 'anulacion') GROUP BY id_local
                UNION ALL SELECT 'COMPRA',o.id_local,max(f.id_factura_recepcion)
                FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
                WHERE datos_factura IS NOT NULL GROUP BY o.id_local
$$;


--
-- Name: facturacion_guardar_adjunto(uuid, integer, integer, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_guardar_adjunto(p_id uuid, p_local integer, p_source integer, p_kind text, p_path text, p_hash text, p_size integer) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO fact_api_adjunto
        (id_adjunto,id_local,id_factura_recepcion,formato,ruta,sha256,bytes)
        VALUES(p_id,p_local,p_source,p_kind,p_path,p_hash,p_size)
        ON CONFLICT(id_local,id_factura_recepcion,sha256) DO UPDATE SET sha256=EXCLUDED.sha256
        RETURNING id_adjunto
$$;


--
-- Name: facturacion_guardar_archivo(uuid, uuid, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_guardar_archivo(p_file uuid, p_id uuid, p_format text, p_path text, p_hash text, p_size integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO fact_api_archivo
                (id_archivo,id_documento,formato,ruta,sha256,bytes)
                VALUES(p_file,p_id,p_format,p_path,p_hash,p_size) ON CONFLICT(id_documento,formato) DO NOTHING
$$;


--
-- Name: facturacion_guardar_documento(uuid, integer, uuid, text, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_guardar_documento(p_id uuid, p_local integer, p_external uuid, p_numero text, p_subtotal numeric, p_igv numeric, p_total numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO fact_api_documento
            (id_documento,id_operacion,id_local,id_externo,numero,estado,subtotal,igv,total)
            VALUES(p_id,p_id,p_local,p_external,p_numero,'DEMO_GENERADO',p_subtotal,p_igv,p_total)
            ON CONFLICT(id_operacion) DO NOTHING
$$;


--
-- Name: facturacion_instalado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_instalado() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.fact_api_operacion') IS NOT NULL
$$;


--
-- Name: facturacion_liberar_liderazgo(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_liberar_liderazgo(p_group integer, p_identity integer) RETURNS boolean
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_unlock(p_group,p_identity)
$$;


--
-- Name: facturacion_local_configurado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_local_configurado(p_local integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT activo FROM fact_api_config WHERE id_local=p_local
$$;


--
-- Name: facturacion_metricas_intentos(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_metricas_intentos(p_local integer) RETURNS TABLE(intentos bigint, errores bigint, p95_ms double precision)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT count(*) AS intentos,
        count(*) FILTER(WHERE http_status>=400) AS errores,
        percentile_cont(.95) WITHIN GROUP(ORDER BY duracion_ms) AS p95_ms
        FROM fact_api_intento i JOIN fact_api_operacion o USING(id_operacion)
        WHERE o.id_local=p_local AND i.inicio>now()-interval '24 hours'
$$;


--
-- Name: facturacion_metricas_local(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_metricas_local(p_local integer) RETURNS TABLE(operaciones bigint, completadas bigint, pendientes bigint, requieren_revision bigint, espera_max_segundos numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT count(*) AS operaciones,
        count(*) FILTER(WHERE estado='COMPLETADO') AS completadas,
        count(*) FILTER(WHERE estado IN ('PENDIENTE','PROCESANDO','REINTENTO')) AS pendientes,
        count(*) FILTER(WHERE estado IN ('REVISION','BLOQUEADO','RECHAZADO')) AS requieren_revision,
        extract(epoch FROM now()-min(creado_en) FILTER(WHERE estado IN ('PENDIENTE','REINTENTO'))) AS espera_max_segundos
        FROM fact_api_operacion WHERE id_local=p_local
$$;


--
-- Name: facturacion_obsoletar_fuente(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_obsoletar_fuente(p_origin text, p_source bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_operacion SET obsoleto=true,
        estado=CASE WHEN estado='COMPLETADO' THEN estado ELSE 'BLOQUEADO' END,
        lease_token=NULL,lease_hasta=NULL,actualizado_en=now(),
        ultimo_error='Existe una versión más reciente de la fuente'
        WHERE origen=p_origin AND id_origen=p_source
$$;


--
-- Name: facturacion_obsoletar_venta(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_obsoletar_venta(p_id bigint, p_local integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_operacion SET obsoleto=true,
        estado=CASE WHEN estado='COMPLETADO' THEN estado ELSE 'BLOQUEADO' END,
        lease_token=NULL,lease_hasta=NULL,ultimo_error='Venta interna anulada; documento histórico',
        actualizado_en=now() WHERE origen='VENTA' AND id_origen=p_id AND id_local=p_local
$$;


--
-- Name: facturacion_obtener_escalado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_obtener_escalado() RETURNS TABLE(id integer, supervisor uuid, pid integer, minimo integer, maximo integer, activos integer, objetivo integer, listos integer, ocupados integer, espera_segundos numeric, pausado boolean, workers jsonb, actualizado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM fact_api_escalado WHERE id=1
$$;


--
-- Name: facturacion_operacion_previa(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_operacion_previa(p_origin text, p_source bigint) RETURNS TABLE(id_operacion uuid, id_local integer, origen text, id_origen bigint, version integer, payload jsonb, payload_hash character, estado text, intentos integer, disponible_en timestamp with time zone, lease_hasta timestamp with time zone, lease_token uuid, ultimo_http integer, ultimo_error text, creado_en timestamp with time zone, actualizado_en timestamp with time zone, max_intentos integer, obsoleto boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM fact_api_operacion
        WHERE origen=p_origin AND id_origen=p_source ORDER BY version DESC LIMIT 1
$$;


--
-- Name: facturacion_original_por_local(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_original_por_local(p_id uuid, p_local integer) RETURNS TABLE(id_adjunto uuid, id_local integer, id_factura_recepcion integer, formato text, ruta text, sha256 character, bytes integer, creado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM fact_api_adjunto WHERE id_adjunto=p_id AND id_local=p_local
$$;


--
-- Name: facturacion_originales_compra(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_originales_compra(p_local integer, p_source integer) RETURNS TABLE(id_adjunto uuid, formato text, creado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_adjunto,formato,creado_en FROM fact_api_adjunto
            WHERE id_local=p_local AND id_factura_recepcion=p_source ORDER BY creado_en
$$;


--
-- Name: facturacion_perfil_ve_escalado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_perfil_ve_escalado(p_perfil integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (SELECT FROM public.perfiles p
        WHERE p.id_perfil=p_perfil AND p.estado_registro=1 AND p.ve_escalado_fact_api)
$$;


--
-- Name: facturacion_pid_conexion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_pid_conexion() RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_backend_pid()
$$;


--
-- Name: facturacion_reclamar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_reclamar(p_token text) RETURNS TABLE(id_operacion uuid, id_local integer, origen text, id_origen bigint, version integer, payload jsonb, payload_hash character, estado text, intentos integer, disponible_en timestamp with time zone, lease_hasta timestamp with time zone, lease_token uuid, ultimo_http integer, ultimo_error text, creado_en timestamp with time zone, actualizado_en timestamp with time zone, max_intentos integer, obsoleto boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH job AS (
        SELECT id_operacion FROM fact_api_operacion
        WHERE NOT obsoleto AND intentos<max_intentos AND ((estado IN ('PENDIENTE','REINTENTO') AND disponible_en<=now())
          OR (estado='PROCESANDO' AND lease_hasta<now()))
          AND NOT EXISTS(SELECT 1 FROM fact_api_circuito WHERE abierto_hasta>now())
        ORDER BY creado_en FOR UPDATE SKIP LOCKED LIMIT 1
    ) UPDATE fact_api_operacion o SET estado='PROCESANDO',intentos=intentos+1,
        lease_hasta=now()+interval '3 minutes',lease_token=CAST(p_token AS uuid),actualizado_en=now()
        FROM job WHERE o.id_operacion=job.id_operacion RETURNING o.*
$$;


--
-- Name: facturacion_reencolar(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_reencolar(p_id uuid, p_local integer) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_operacion SET estado='PENDIENTE',max_intentos=intentos+6,
        disponible_en=now(),lease_token=NULL,lease_hasta=NULL,actualizado_en=now()
        WHERE id_operacion=p_id AND id_local=p_local AND NOT obsoleto AND estado IN ('REVISION','BLOQUEADO','REINTENTO','RECHAZADO')
        RETURNING id_operacion
$$;


--
-- Name: facturacion_registrar_fallo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_registrar_fallo() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_circuito SET fallos=fallos+1,
            abierto_hasta=CASE WHEN fallos>=2 THEN now()+interval '30 seconds' ELSE abierto_hasta END WHERE id=1
$$;


--
-- Name: facturacion_reiniciar_circuito(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_reiniciar_circuito() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_circuito SET fallos=0,abierto_hasta=NULL WHERE id=1
$$;


--
-- Name: facturacion_retirar_supervisor(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_retirar_supervisor(p_id uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_escalado SET activos=0,objetivo=0,workers='[]',
                    actualizado_en=now() WHERE supervisor=p_id
$$;


--
-- Name: facturacion_revisar_agotadas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_revisar_agotadas() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE fact_api_operacion SET estado='REVISION',lease_token=NULL,
        ultimo_error='Intentos agotados; conciliar con el mismo identificador',actualizado_en=now()
        WHERE estado='PROCESANDO' AND lease_hasta<now() AND intentos>=max_intentos
$$;


--
-- Name: facturacion_salud_transporte(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_salud_transporte() RETURNS TABLE(total bigint, bad bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT count(*) AS total,
        count(*) FILTER(WHERE http_status=429 OR http_status>=500) AS bad
        FROM fact_api_intento WHERE inicio>now()-interval '60 seconds' AND fin IS NOT NULL
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: fact_api_operacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_operacion (
    id_operacion uuid NOT NULL,
    id_local integer NOT NULL,
    origen text NOT NULL,
    id_origen bigint NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    payload jsonb NOT NULL,
    payload_hash character(64) NOT NULL,
    estado text DEFAULT 'PENDIENTE'::text NOT NULL,
    intentos integer DEFAULT 0 NOT NULL,
    disponible_en timestamp with time zone DEFAULT now() NOT NULL,
    lease_hasta timestamp with time zone,
    lease_token uuid,
    ultimo_http integer,
    ultimo_error text,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    max_intentos integer DEFAULT 6 NOT NULL,
    obsoleto boolean DEFAULT false NOT NULL,
    CONSTRAINT fact_api_operacion_estado_check CHECK ((estado = ANY (ARRAY['PENDIENTE'::text, 'PROCESANDO'::text, 'REINTENTO'::text, 'COMPLETADO'::text, 'RECHAZADO'::text, 'BLOQUEADO'::text, 'REVISION'::text]))),
    CONSTRAINT fact_api_operacion_origen_check CHECK ((origen = ANY (ARRAY['VENTA'::text, 'COMPRA'::text])))
);


--
-- Name: facturacion_ventas_completadas_pdf(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.facturacion_ventas_completadas_pdf() RETURNS SETOF public.fact_api_operacion
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT o.* FROM fact_api_operacion o
            JOIN fact_api_documento d USING(id_operacion)
            WHERE o.origen='VENTA' AND o.estado='COMPLETADO' AND NOT o.obsoleto
            ORDER BY o.creado_en
$$;


--
-- Name: health_estado_base(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.health_estado_base() RETURNS TABLE(base_datos name, usuario name, total_tablas bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT current_database(), current_user,
           (SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname='public')
$$;


--
-- Name: hora_limite_borrador_inventario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hora_limite_borrador_inventario() RETURNS time without time zone
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT hora_limite_borrador FROM public.configuracion_operativa
$$;


--
-- Name: inv_demand_global_report_1(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_demand_global_report_1(p_desde date, p_hasta date) RETURNS TABLE(id_local integer, nombre character varying, cobros bigint, cobros_con_inventario bigint, dias_con_ventas bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT l.id_local,l.nombre,count(c.id_cobro) cobros,
        count(m.id_movimiento_inventario) cobros_con_inventario,
        count(DISTINCT (c.creado_en AT TIME ZONE 'America/Lima')::date) dias_con_ventas
        FROM local l LEFT JOIN salon_cobro c ON c.id_local=l.id_local AND c.comprobante->'anulacion' IS NULL
        AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        LEFT JOIN movimiento_inventario m ON m.id_movimiento_inventario=c.id_movimiento AND m.id_local=l.id_local
        WHERE l.estado_registro=1 GROUP BY l.id_local,l.nombre ORDER BY l.id_local
$$;


--
-- Name: inv_demand_global_report_2(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_demand_global_report_2() RETURNS TABLE(id_local integer, id_producto integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_local,id_producto FROM inventario_saldo_inicial
                        UNION SELECT id_local,id_producto FROM inventario_evento
$$;


--
-- Name: inv_demand_global_report_3(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_demand_global_report_3() RETURNS TABLE(id_presentacion integer, nombre character varying, tipo character varying, contenido numeric, unidad character varying, precio numeric, activo boolean, menaje character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,ic.tipo,
        pv.contenido,pv.unidad,pv.precio,pv.activo,m.nombre menaje
        FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
        JOIN menaje m USING(id_menaje)
$$;


--
-- Name: inv_demand_report_1(integer, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_demand_report_1(p_local integer, p_desde date, p_hasta date) RETURNS TABLE(id_presentacion integer, id_promocion integer, nombre text, id_item_carta integer, categoria character varying, cantidad numeric, total numeric, cantidad_en_promociones numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH lineas AS (
        SELECT c.creado_en,linea
        FROM salon_cobro c CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') linea
        WHERE c.comprobante->'anulacion' IS NULL AND c.id_local=p_local AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
      ), demanda AS (
        SELECT creado_en,(linea->>'id_presentacion')::int id_presentacion,
          (linea->>'id_promocion')::int id_promocion,linea->>'nombre' nombre,
          (linea->>'cantidad')::numeric cantidad,
          (linea->>'cantidad')::numeric*(linea->>'precio')::numeric total,
          0::numeric cantidad_en_promociones FROM lineas
        UNION ALL
        SELECT creado_en,(opcion->>'id_presentacion')::int,NULL,opcion->>'nombre',
          (linea->>'cantidad')::numeric,0::numeric,(linea->>'cantidad')::numeric
          FROM lineas CROSS JOIN LATERAL jsonb_array_elements(coalesce(linea->'selecciones_promocion','[]'::jsonb)) opcion
          WHERE (linea->>'id_promocion') IS NOT NULL
      ) SELECT d.id_presentacion,d.id_promocion,
        (array_agg(d.nombre ORDER BY d.creado_en DESC))[1] nombre,
        pv.id_item_carta,cc.nombre categoria,sum(d.cantidad) cantidad,
        sum(d.total) total,sum(d.cantidad_en_promociones) cantidad_en_promociones
        FROM demanda d
        LEFT JOIN presentacion_venta pv ON pv.id_presentacion_venta=d.id_presentacion
        LEFT JOIN item_carta ic ON ic.id_item_carta=pv.id_item_carta
        LEFT JOIN categoria_carta cc ON cc.id_categoria_carta=ic.id_categoria_carta
        GROUP BY d.id_presentacion,d.id_promocion,pv.id_item_carta,cc.nombre
$$;


--
-- Name: inv_demand_report_2(integer, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_demand_report_2(p_local integer, p_desde date, p_hasta date) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, categoria character varying, stock_actual numeric, consumo_ventas numeric, entradas numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH consumo AS (
        SELECT d.id_producto,sum(d.cantidad) consumo_ventas
        FROM salon_cobro c
        JOIN movimiento_inventario m ON m.id_movimiento_inventario=c.id_movimiento AND m.id_local=c.id_local
        JOIN movimiento_inventario_detalle d USING(id_movimiento_inventario)
        WHERE c.id_local=p_local AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        GROUP BY d.id_producto
      ), entradas AS (
        SELECT id_producto,sum(greatest(cantidad,0)) entradas FROM inventario_evento
        WHERE id_local=p_local AND (registrado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        GROUP BY id_producto
      ) SELECT p.id_producto,p.codigo,p.nombre,p.unidad,cat.nombre categoria,
        coalesce(s.stock_actual,0) stock_actual,coalesce(c.consumo_ventas,0) consumo_ventas,
        coalesce(e.entradas,0) entradas
      FROM producto p LEFT JOIN categoria_producto cat ON cat.id_categoria=p.id_categoria
      LEFT JOIN inventario_stock_teorico s ON s.id_producto=p.id_producto AND s.id_local=p_local
      LEFT JOIN consumo c ON c.id_producto=p.id_producto
      LEFT JOIN entradas e ON e.id_producto=p.id_producto
      WHERE p.activo OR c.id_producto IS NOT NULL OR coalesce(s.stock_actual,0)<>0
$$;


--
-- Name: inv_operativo_abrir(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_abrir(p_local integer, p_usuario integer) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT inventario_abrir_jornada(p_local,p_usuario)
$$;


--
-- Name: inventario_conteo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_conteo (
    id_ronda bigint NOT NULL,
    id_producto integer NOT NULL,
    asignado_a integer,
    teorico numeric(18,3) NOT NULL,
    contado numeric(18,3),
    corregido numeric(18,3),
    contado_por integer,
    contado_en timestamp with time zone,
    estado character varying(15) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    observacion text DEFAULT ''::text NOT NULL,
    revisado_por integer,
    revisado_en timestamp with time zone,
    justificacion text DEFAULT ''::text NOT NULL,
    justificado_por integer,
    justificado_en timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    puesto_asignado integer,
    puesto_nombre text,
    contado_perfil integer,
    contado_puesto integer,
    contado_perfil_nombre text,
    contado_puesto_nombre text,
    CONSTRAINT inventario_conteo_check CHECK ((((estado)::text = 'PENDIENTE'::text) OR (contado IS NOT NULL))),
    CONSTRAINT inventario_conteo_contado_check CHECK (((contado IS NULL) OR (contado >= (0)::numeric))),
    CONSTRAINT inventario_conteo_corregido_check CHECK (((corregido IS NULL) OR (corregido >= (0)::numeric))),
    CONSTRAINT inventario_conteo_estado_check CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'EN_PROCESO'::character varying, 'HECHO'::character varying, 'REVISADO'::character varying])::text[])))
);


--
-- Name: inv_operativo_actualizar_conteo(bigint, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_actualizar_conteo(p_ronda bigint, p_producto integer, p_cambios text, p_accion text) RETURNS SETOF public.inventario_conteo
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
DECLARE
    campos text;
    fecha text;
    cambios jsonb := p_cambios::jsonb;
BEGIN
    IF EXISTS (
        SELECT FROM jsonb_object_keys(cambios) AS clave(nombre)
        WHERE nombre NOT IN ('puesto_asignado','puesto_nombre','asignado_a','contado','contado_por',
            'estado','contado_perfil','contado_puesto','contado_perfil_nombre','contado_puesto_nombre',
            'corregido','observacion','revisado_por','justificacion','justificado_por','justificado_en')
    ) THEN
        RAISE EXCEPTION 'Campo de conteo no autorizado';
    END IF;
    SELECT string_agg(format('%1$I=(jsonb_populate_record(c,$3)).%1$I',nombre), ',')
      INTO campos FROM jsonb_object_keys(cambios) AS clave(nombre);
    fecha := CASE p_accion WHEN 'contar' THEN 'contado_en' WHEN 'revisar' THEN 'revisado_en'
                          WHEN 'justificar' THEN 'justificado_en' END;
    IF fecha IS NOT NULL THEN campos := campos || format(',%I=clock_timestamp()',fecha); END IF;
    RETURN QUERY EXECUTE 'UPDATE public.inventario_conteo c SET ' || campos ||
        ',version=c.version+1 WHERE c.id_ronda=$1 AND c.id_producto=$2 RETURNING c.*'
        USING p_ronda,p_producto,cambios;
END;
$_$;


--
-- Name: inv_operativo_asignaciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_asignaciones(p_local integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, categoria character varying, id_puesto_laboral integer, puesto character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto,p.codigo,p.nombre,
        cp.nombre categoria,a.id_puesto_laboral,pl.nombre puesto
        FROM producto p JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN inventario_asignacion_puesto a ON a.id_producto=p.id_producto AND a.id_local=p_local
        LEFT JOIN puesto_laboral pl ON pl.id_puesto_laboral=a.id_puesto_laboral
        WHERE p.activo ORDER BY p.nombre
$$;


--
-- Name: inv_operativo_bloqueo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_bloqueo(p_clave text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock(hashtext(p_clave))
$$;


--
-- Name: inv_operativo_cerrar_1(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_cerrar_1() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
LOCK TABLE salon_pedido IN SHARE MODE
$$;


--
-- Name: inv_operativo_cerrar_2(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_cerrar_2(p_local integer) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT count(*) FROM salon_pedido_actual p WHERE p.id_local=p_local
            AND EXISTS(SELECT 1 FROM salon_pedido_linea l WHERE l.id_pedido=p.id_pedido
            AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea))
$$;


--
-- Name: inv_operativo_cerrar_3(integer, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_cerrar_3(p_usuario integer, p_reporte text, p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_jornada SET cerrado_en=clock_timestamp(),cerrado_por=p_usuario,
            reporte=CAST(p_reporte AS jsonb) WHERE id_jornada=p_id
$$;


--
-- Name: inv_operativo_crear_ronda_1(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_crear_ronda_1(p_local integer) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT 1 FROM inventario_asignacion_puesto a
                JOIN producto p USING(id_producto) JOIN puesto_laboral pl USING(id_puesto_laboral)
                WHERE a.id_local=p_local AND p.activo AND pl.estado_registro=1 LIMIT 1
$$;


--
-- Name: inv_operativo_crear_ronda_2(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_crear_ronda_2(p_local integer) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT 1 FROM inventario_ronda WHERE id_local=p_local AND cerrado_en IS NULL
$$;


--
-- Name: inv_operativo_crear_ronda_3(integer, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_crear_ronda_3(p_local integer, p_nombre text, p_usuario integer) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_ronda(id_local,nombre,creado_por)
            VALUES(p_local,p_nombre,p_usuario) RETURNING id_ronda
$$;


--
-- Name: inv_operativo_crear_ronda_4(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_crear_ronda_4(p_id bigint, p_local integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_conteo(id_ronda,id_producto,teorico)
            SELECT p_id,s.id_producto,s.stock_actual FROM inventario_stock_teorico s JOIN producto p USING(id_producto)
            WHERE s.id_local=p_local AND p.activo
$$;


--
-- Name: inv_operativo_crear_ronda_5(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_crear_ronda_5(p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_ronda SET por_puesto=true WHERE id_ronda=p_id
$$;


--
-- Name: inv_operativo_crear_ronda_6(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_crear_ronda_6(p_id bigint, p_local integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_conteo c SET puesto_asignado=a.id_puesto_laboral,puesto_nombre=p.nombre
                FROM inventario_asignacion_puesto a JOIN puesto_laboral p USING(id_puesto_laboral)
                WHERE c.id_ronda=p_id AND c.id_producto=a.id_producto AND a.id_local=p_local AND p.estado_registro=1
$$;


--
-- Name: inv_operativo_demanda(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_demanda() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_cobro') IS NOT NULL
$$;


--
-- Name: inv_operativo_detalle_conteo(bigint, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_detalle_conteo(p_id bigint, p_gestor boolean, p_usuario integer) RETURNS TABLE(id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text, nombre character varying, codigo character varying, unidad character varying, categoria character varying, asignado_nombre text, contado_nombre text, diferencia numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text,p.nombre,p.codigo,p.unidad,cp.nombre AS categoria,
        concat_ws(' ',u.nombres,u.apellido_paterno) AS asignado_nombre,
        concat_ws(' ',contador.nombres,contador.apellido_paterno) AS contado_nombre,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia
        FROM inventario_conteo c JOIN producto p USING(id_producto) JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN usuario contador ON contador.id_usuario=c.contado_por
        LEFT JOIN usuario u ON u.id_usuario=c.asignado_a WHERE c.id_ronda=p_id
        AND (p_gestor OR c.asignado_a=p_usuario) ORDER BY p.nombre
$$;


--
-- Name: inv_operativo_detalle_conteo_puestos(bigint, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_detalle_conteo_puestos(p_id bigint, p_gestor boolean, p_puesto integer) RETURNS TABLE(id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text, nombre character varying, codigo character varying, unidad character varying, categoria character varying, asignado_nombre text, contado_nombre text, diferencia numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT c.*,p.nombre,p.codigo,p.unidad,cp.nombre AS categoria,
        concat_ws(' ',u.nombres,u.apellido_paterno) AS asignado_nombre,
        concat_ws(' ',contador.nombres,contador.apellido_paterno) AS contado_nombre,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia
        FROM inventario_conteo c JOIN producto p USING(id_producto) JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN usuario contador ON contador.id_usuario=c.contado_por
        LEFT JOIN usuario u ON u.id_usuario=c.asignado_a WHERE c.id_ronda=p_id
        AND (p_gestor OR c.puesto_asignado=p_puesto) ORDER BY p.nombre
$$;


--
-- Name: inv_operativo_dias(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_dias(p_local integer) RETURNS TABLE(id_jornada bigint, fecha date, abierto_en timestamp with time zone, cerrado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_jornada,fecha,abierto_en,cerrado_en FROM inventario_jornada
        WHERE id_local=p_local ORDER BY fecha DESC LIMIT 366
$$;


--
-- Name: inv_operativo_diferencias(integer, date, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_diferencias(p_local integer, p_desde date, p_hasta date, p_top integer) RETURNS TABLE(id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text, nombre character varying, unidad character varying, ronda character varying, creado_en timestamp with time zone, diferencia numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text,p.nombre,p.unidad,r.nombre AS ronda,r.creado_en,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia FROM inventario_conteo c
        JOIN inventario_ronda r USING(id_ronda) JOIN producto p USING(id_producto)
        WHERE r.id_local=p_local AND (r.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        AND c.estado='REVISADO' AND coalesce(c.corregido,c.contado)<>c.teorico
        ORDER BY abs(coalesce(c.corregido,c.contado)-c.teorico) DESC,r.creado_en DESC,p.nombre LIMIT p_top
$$;


--
-- Name: inv_operativo_editar_conteo_2(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_editar_conteo_2(p_id bigint, p_local integer) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_ronda FROM inventario_ronda WHERE id_ronda=p_id AND id_local=p_local FOR UPDATE
$$;


--
-- Name: inv_operativo_editar_conteo_3(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_editar_conteo_3(p_id bigint, p_producto integer) RETURNS TABLE(id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text FROM inventario_conteo c WHERE id_ronda=p_id AND id_producto=p_producto FOR UPDATE
$$;


--
-- Name: inv_operativo_editar_conteo_4(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_editar_conteo_4(p_id bigint) RETURNS character varying
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT nombre FROM perfiles WHERE id_perfil=p_id
$$;


--
-- Name: inv_operativo_editar_conteo_5(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_editar_conteo_5(p_id bigint) RETURNS character varying
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT nombre FROM puesto_laboral WHERE id_puesto_laboral=p_id
$$;


--
-- Name: inv_operativo_editar_conteo_7(bigint, integer, integer, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_editar_conteo_7(p_id bigint, p_producto integer, p_usuario integer, p_accion text, p_anterior text, p_nuevo text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo)
            VALUES(p_id,p_producto,p_usuario,p_accion,CAST(p_anterior AS jsonb),CAST(p_nuevo AS jsonb))
$$;


--
-- Name: inv_operativo_equipo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_equipo(p_local integer) RETURNS TABLE(id_usuario integer, nombre text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) nombre
        FROM usuario u JOIN usuario_local ul USING(id_usuario) WHERE ul.id_local=p_local AND ul.estado_registro=1
        AND u.estado_registro=1 AND EXISTS(SELECT 1 FROM usuario_perfiles up JOIN perfiles p USING(id_perfil)
        WHERE up.id_usuario=u.id_usuario AND public.perfil_tiene_capacidad(up.id_perfil, 'operar_tienda') AND up.estado_registro=1 AND p.estado_registro=1)
        ORDER BY nombre
$$;


--
-- Name: inv_operativo_finalizar_conteo_1(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_finalizar_conteo_1(p_id bigint, p_local integer) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_ronda FROM inventario_ronda WHERE id_ronda=p_id AND id_local=p_local FOR UPDATE
$$;


--
-- Name: inv_operativo_finalizar_conteo_2(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_finalizar_conteo_2(p_id bigint) RETURNS TABLE(id_ronda bigint, id_producto integer, asignado_a integer, teorico numeric, contado numeric, corregido numeric, contado_por integer, contado_en timestamp with time zone, estado character varying, observacion text, revisado_por integer, revisado_en timestamp with time zone, justificacion text, justificado_por integer, justificado_en timestamp with time zone, version integer, puesto_asignado integer, puesto_nombre text, contado_perfil integer, contado_puesto integer, contado_perfil_nombre text, contado_puesto_nombre text)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT c.id_ronda,
    c.id_producto,
    c.asignado_a,
    c.teorico,
    c.contado,
    c.corregido,
    c.contado_por,
    c.contado_en,
    c.estado,
    c.observacion,
    c.revisado_por,
    c.revisado_en,
    c.justificacion,
    c.justificado_por,
    c.justificado_en,
    c.version,
    (to_jsonb(c)->>'puesto_asignado')::integer,
    (to_jsonb(c)->>'puesto_nombre')::text,
    (to_jsonb(c)->>'contado_perfil')::integer,
    (to_jsonb(c)->>'contado_puesto')::integer,
    (to_jsonb(c)->>'contado_perfil_nombre')::text,
    (to_jsonb(c)->>'contado_puesto_nombre')::text FROM inventario_conteo c WHERE id_ronda=p_id ORDER BY id_producto FOR UPDATE
$$;


--
-- Name: inv_operativo_finalizar_conteo_3(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_finalizar_conteo_3(p_perfil integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT puede_revisar FROM perfil_opcion_menu
                WHERE id_perfil=p_perfil AND id_opcion_menu=public.permiso_opcion_recurso('conteo_fisico') AND estado_registro=1
$$;


--
-- Name: inv_operativo_finalizar_conteo_4(numeric, text, integer, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_finalizar_conteo_4(p_valor numeric, p_nota text, p_usuario integer, p_id bigint, p_producto integer) RETURNS SETOF public.inventario_conteo
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_conteo SET corregido=p_valor,observacion=p_nota,estado='REVISADO',
                    justificacion='',justificado_por=NULL,justificado_en=NULL,
                    revisado_por=p_usuario,revisado_en=clock_timestamp(),version=version+1
                    WHERE id_ronda=p_id AND id_producto=p_producto RETURNING *
$$;


--
-- Name: inv_operativo_finalizar_conteo_5(bigint, integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_finalizar_conteo_5(p_id bigint, p_producto integer, p_usuario integer, p_anterior text, p_nuevo text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo)
                    VALUES(p_id,p_producto,p_usuario,'revisar',CAST(p_anterior AS jsonb),CAST(p_nuevo AS jsonb))
$$;


--
-- Name: inv_operativo_finalizar_conteo_6(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_finalizar_conteo_6(p_id bigint) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT count(*) FROM inventario_conteo WHERE id_ronda=p_id AND estado<>'REVISADO'
$$;


--
-- Name: inv_operativo_finalizar_conteo_7(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_finalizar_conteo_7(p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_ronda SET cerrado_en=clock_timestamp() WHERE id_ronda=p_id
$$;


--
-- Name: inv_operativo_guardar_asignaciones_1(integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_guardar_asignaciones_1(p_ids integer[]) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT count(*) FROM producto WHERE activo AND id_producto=ANY(p_ids)
$$;


--
-- Name: inv_operativo_guardar_asignaciones_2(integer, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_guardar_asignaciones_2(p_local integer, p_ids integer[]) RETURNS TABLE(id_local integer, id_producto integer, id_puesto_laboral integer, actualizado_por integer, actualizado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM inventario_asignacion_puesto WHERE id_local=p_local AND id_producto=ANY(p_ids)
$$;


--
-- Name: inv_operativo_guardar_asignaciones_3(integer, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_guardar_asignaciones_3(p_local integer, p_ids integer[]) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM inventario_asignacion_puesto WHERE id_local=p_local AND id_producto=ANY(p_ids)
$$;


--
-- Name: inv_operativo_guardar_asignaciones_4(integer, integer, integer, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_guardar_asignaciones_4(p_local integer, p_puesto integer, p_usuario integer, p_ids integer[]) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_asignacion_puesto(id_local,id_producto,id_puesto_laboral,actualizado_por)
                SELECT p_local,p.id_producto,p_puesto,p_usuario FROM producto p WHERE p.id_producto=ANY(p_ids)
                ON CONFLICT(id_local,id_producto) DO UPDATE SET id_puesto_laboral=excluded.id_puesto_laboral,
                actualizado_por=excluded.actualizado_por,actualizado_en=clock_timestamp()
$$;


--
-- Name: inv_operativo_historial(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_historial(p_id bigint) RETURNS TABLE(id_historial bigint, id_ronda bigint, id_producto integer, id_usuario integer, accion character varying, anterior jsonb, nuevo jsonb, creado_en timestamp with time zone, usuario text, producto character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT h.*,concat_ws(' ',u.nombres,u.apellido_paterno) usuario,p.nombre producto
        FROM inventario_conteo_historial h JOIN usuario u USING(id_usuario) JOIN producto p USING(id_producto)
        WHERE h.id_ronda=p_id ORDER BY h.id_historial DESC LIMIT 1000
$$;


--
-- Name: inv_operativo_jornada_local(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_jornada_local(p_id bigint, p_local integer) RETURNS TABLE(id_jornada bigint, id_local integer, fecha date, abierto_en timestamp with time zone, cerrado_en timestamp with time zone, abierto_por integer, cerrado_por integer, reporte jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM inventario_jornada WHERE id_jornada=p_id AND id_local=p_local
$$;


--
-- Name: inv_operativo_plan_semanal(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_plan_semanal() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_cobro') IS NOT NULL
$$;


--
-- Name: inv_operativo_puestos_conteo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_puestos_conteo() RETURNS TABLE(id_puesto_laboral integer, nombre character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_puesto_laboral,nombre FROM puesto_laboral WHERE estado_registro=1
        AND lower(trim(nombre)) IN ('cocina','bartender','mesero') ORDER BY nombre
$$;


--
-- Name: inv_operativo_puestos_instalados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_puestos_instalados() RETURNS regclass
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.inventario_asignacion_puesto')
$$;


--
-- Name: inv_operativo_reporte_1(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_reporte_1(p_id bigint) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, inicial numeric, entradas numeric, salidas numeric, final numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,
        coalesce(i.cantidad,0) AS inicial,
        coalesce(e.entradas,0) AS entradas,coalesce(e.salidas,0) AS salidas,
        coalesce(i.cantidad,0)+coalesce(e.entradas,0)-coalesce(e.salidas,0) AS final
        FROM producto p LEFT JOIN inventario_jornada_inicio i ON i.id_producto=p.id_producto AND i.id_jornada=p_id
        LEFT JOIN (SELECT id_producto,sum(greatest(cantidad,0)) entradas,sum(greatest(-cantidad,0)) salidas
          FROM inventario_evento WHERE id_jornada=p_id GROUP BY id_producto) e ON e.id_producto=p.id_producto
        WHERE i.id_producto IS NOT NULL OR e.id_producto IS NOT NULL OR p.activo ORDER BY p.nombre
$$;


--
-- Name: inv_operativo_reporte_2(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_reporte_2(p_id bigint) RETURNS TABLE(id_producto integer, motivo character varying, etiqueta text, entradas numeric, salidas numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT e.id_producto,e.motivo,
        coalesce(m.etiqueta, initcap(replace(e.motivo, '_', ' '))) etiqueta,
        sum(greatest(e.cantidad,0)) entradas,sum(greatest(-e.cantidad,0)) salidas
        FROM inventario_evento e LEFT JOIN public.movimiento_motivo m ON m.codigo=e.motivo
        WHERE e.id_jornada=p_id GROUP BY e.id_producto,e.motivo,m.etiqueta ORDER BY e.motivo
$$;


--
-- Name: inv_operativo_ronda_local(bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_ronda_local(p_id bigint, p_local integer) RETURNS TABLE(id_ronda bigint, id_local integer, nombre character varying, creado_por integer, creado_en timestamp with time zone, cerrado_en timestamp with time zone, por_puesto boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT r.id_ronda,
    r.id_local,
    r.nombre,
    r.creado_por,
    r.creado_en,
    r.cerrado_en,
    COALESCE((to_jsonb(r)->>'por_puesto')::boolean, false) FROM inventario_ronda r WHERE id_ronda=p_id AND id_local=p_local
$$;


--
-- Name: inv_operativo_rondas(integer, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_rondas(p_local integer, p_gestor boolean, p_usuario integer) RETURNS TABLE(id_ronda bigint, id_local integer, nombre character varying, creado_por integer, creado_en timestamp with time zone, cerrado_en timestamp with time zone, por_puesto boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT r.id_ronda,
    r.id_local,
    r.nombre,
    r.creado_por,
    r.creado_en,
    r.cerrado_en,
    COALESCE((to_jsonb(r)->>'por_puesto')::boolean, false) FROM inventario_ronda r WHERE id_local=p_local
        AND (p_gestor OR EXISTS(SELECT 1 FROM inventario_conteo c WHERE c.id_ronda=r.id_ronda AND c.asignado_a=p_usuario))
        ORDER BY creado_en DESC LIMIT 200
$$;


--
-- Name: inv_operativo_rondas_puestos(integer, boolean, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_rondas_puestos(p_local integer, p_gestor boolean, p_puesto integer, p_usuario integer) RETURNS TABLE(id_ronda bigint, id_local integer, nombre character varying, creado_por integer, creado_en timestamp with time zone, cerrado_en timestamp with time zone, por_puesto boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT r.* FROM inventario_ronda r WHERE id_local=p_local
        AND (p_gestor OR EXISTS(SELECT 1 FROM inventario_conteo c WHERE c.id_ronda=r.id_ronda AND ((r.por_puesto AND c.puesto_asignado=p_puesto) OR (NOT r.por_puesto AND c.asignado_a=p_usuario))))
        ORDER BY creado_en DESC LIMIT 200
$$;


--
-- Name: inv_operativo_ventas(boolean, integer, bigint, date, date, boolean, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_operativo_ventas(p_separar boolean, p_local integer, p_jornada bigint, p_desde date, p_hasta date, p_todas boolean, p_horas integer[]) RETURNS TABLE(id_presentacion integer, nombre text, hora integer, cantidad numeric, total numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT (linea->>'id_presentacion')::integer AS id_presentacion,
        linea->>'nombre' AS nombre,
        CASE WHEN p_separar THEN extract(hour FROM c.creado_en AT TIME ZONE 'America/Lima')::int ELSE NULL END AS hora,
        sum((linea->>'cantidad')::numeric) AS cantidad,
        sum((linea->>'cantidad')::numeric*(linea->>'precio')::numeric) AS total
        FROM salon_cobro c LEFT JOIN inventario_jornada j USING(id_jornada)
        CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') linea
        WHERE c.comprobante->'anulacion' IS NULL AND c.id_local=p_local AND
        ((CAST(p_jornada AS bigint) IS NOT NULL AND c.id_jornada=p_jornada) OR
         (CAST(p_jornada AS bigint) IS NULL AND coalesce(j.fecha,(c.creado_en AT TIME ZONE 'America/Lima')::date) BETWEEN p_desde AND p_hasta))
        AND (p_todas OR extract(hour FROM c.creado_en AT TIME ZONE 'America/Lima')::int=ANY(p_horas))
        GROUP BY 1,2,3 ORDER BY cantidad DESC,total DESC,nombre,hora
$$;


--
-- Name: inv_product_outlook_report_1(integer, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_product_outlook_report_1(p_local integer, p_desde date, p_hasta date) RETURNS TABLE(fecha date)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH receipts AS (
        SELECT (creado_en AT TIME ZONE 'America/Lima')::date fecha,count(*) cobros,
          count(*) FILTER (WHERE EXISTS (SELECT 1 FROM movimiento_inventario m
            WHERE m.id_movimiento_inventario=c.id_movimiento AND m.id_local=c.id_local)) vinculados
        FROM salon_cobro c WHERE id_local=p_local
          AND (creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta GROUP BY 1
        ), closures AS (SELECT fecha FROM inventario_jornada WHERE id_local=p_local
          AND cerrado_en IS NOT NULL AND fecha BETWEEN p_desde AND p_hasta)
        SELECT coalesce(r.fecha,j.fecha) fecha FROM receipts r FULL JOIN closures j USING(fecha)
        WHERE (coalesce(r.cobros,0)>0 OR j.fecha IS NOT NULL)
          AND coalesce(r.cobros,0)=coalesce(r.vinculados,0)
$$;


--
-- Name: inv_product_outlook_report_2(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_product_outlook_report_2(p_local integer) RETURNS TABLE(id_producto integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto FROM inventario_saldo_inicial WHERE id_local=p_local
                  UNION SELECT id_producto FROM inventario_evento WHERE id_local=p_local
$$;


--
-- Name: inv_product_outlook_report_3(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_product_outlook_report_3(p_local integer) RETURNS TABLE(nombre character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT nombre FROM local WHERE id_local=p_local
$$;


--
-- Name: inv_repository_actualizar_estado_inventario(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_actualizar_estado_inventario(p_estado text, p_id_inventario_cierre integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_cierre
        SET estado_inventario = p_estado
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
$$;


--
-- Name: inv_repository_actualizar_revision_inventario(integer, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_actualizar_revision_inventario(p_id_usuario_revision integer, p_motivo_revision text, p_observacion text, p_id_inventario integer) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_cierre
        SET
            usuario_revision = p_id_usuario_revision,
            motivo_revision = p_motivo_revision,
            observacion = p_observacion
        WHERE id_inventario_cierre = p_id_inventario
          AND estado_inventario = 'CERRADO'
        RETURNING id_inventario_cierre
$$;


--
-- Name: inv_repository_aplicar_stock_corregido_1(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_aplicar_stock_corregido_1(p_id_inventario integer, p_id_producto integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM inventario_cierre_detalle
            WHERE id_inventario_cierre = p_id_inventario
              AND id_producto = p_id_producto
$$;


--
-- Name: inv_repository_aplicar_stock_corregido_2(integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_aplicar_stock_corregido_2(p_id_inventario integer, p_id_producto integer, p_stock_nuevo numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_cierre_detalle (
                id_inventario_cierre,
                id_producto,
                stock_contado
            )
            VALUES (
                p_id_inventario,
                p_id_producto,
                p_stock_nuevo
            )
            ON CONFLICT (
                id_inventario_cierre,
                id_producto
            )
            DO UPDATE SET
                stock_contado = EXCLUDED.stock_contado
$$;


--
-- Name: inv_repository_bloquear_inventario_cerrado(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_bloquear_inventario_cerrado(p_id_local_actual integer, p_id_inventario integer) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            id_inventario_cierre,
            fecha_inventario,
            estado_inventario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) inventario_cierre
        WHERE id_inventario_cierre = p_id_inventario
          AND estado_inventario = 'CERRADO'
        FOR UPDATE
$$;


--
-- Name: inv_repository_buscar_cabecera_inventario_actual(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_buscar_cabecera_inventario_actual(p_id_local_actual integer) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, usuario text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) ic
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.estado_inventario IN (
            'BORRADOR',
            'INCOMPLETO'
        )
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
        LIMIT 1
$$;


--
-- Name: inv_repository_buscar_inventario_cerrado_por_id(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_buscar_inventario_cerrado_por_id(p_id_local_actual integer, p_id_inventario integer) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, fecha_registro timestamp without time zone, usuario_registro integer, registrado_por text, usuario_revision integer, revisado_por text, motivo_revision character varying, observacion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.usuario_registro,
            CONCAT_WS(
                ' ',
                ur.nombres,
                ur.apellido_paterno,
                ur.apellido_materno
            ) AS registrado_por,
            ic.usuario_revision,
            CASE
                WHEN ic.usuario_revision IS NULL THEN NULL
                ELSE CONCAT_WS(
                    ' ',
                    uv.nombres,
                    uv.apellido_paterno,
                    uv.apellido_materno
                )
            END AS revisado_por,
            ic.motivo_revision,
            ic.observacion
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) ic
        JOIN usuario ur
            ON ur.id_usuario = ic.usuario_registro
        LEFT JOIN usuario uv
            ON uv.id_usuario = ic.usuario_revision
        WHERE ic.id_inventario_cierre = p_id_inventario
          AND ic.estado_inventario = 'CERRADO'
$$;


--
-- Name: inv_repository_buscar_inventario_de_hoy(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_buscar_inventario_de_hoy(p_id_local_actual integer) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, productos_contados bigint, usuario text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            COUNT(icd.id_inventario_cierre_detalle) AS productos_contados,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) ic
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.fecha_inventario = CURRENT_DATE
        GROUP BY
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            u.nombres,
            u.apellido_paterno
        ORDER BY ic.id_inventario_cierre DESC
        LIMIT 1
$$;


--
-- Name: inv_repository_buscar_inventario_por_fecha(integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_buscar_inventario_por_fecha(p_id_local_actual integer, p_fecha_inventario date) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, usuario text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) ic
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.fecha_inventario = p_fecha_inventario
        ORDER BY ic.id_inventario_cierre DESC
        LIMIT 1
$$;


--
-- Name: inv_repository_buscar_producto_para_correccion(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_buscar_producto_para_correccion(p_id_inventario integer, p_id_producto integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, activo boolean, id_inventario_cierre_detalle integer, stock_contado numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.activo,
            icd.id_inventario_cierre_detalle,
            icd.stock_contado
        FROM producto p
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_producto = p.id_producto
           AND icd.id_inventario_cierre = p_id_inventario
        WHERE p.id_producto = p_id_producto
          AND (
              p.activo = TRUE
              OR icd.id_inventario_cierre_detalle IS NOT NULL
          )
$$;


--
-- Name: inv_repository_buscar_ultimo_inventario_cerrado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_buscar_ultimo_inventario_cerrado(p_id_local_actual integer) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, productos_contados bigint, usuario text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            COUNT(icd.id_inventario_cierre_detalle) AS productos_contados,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) ic
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.estado_inventario = 'CERRADO'
        GROUP BY
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            u.nombres,
            u.apellido_paterno
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
        LIMIT 1
$$;


--
-- Name: inv_repository_buscar_ultimos_inventarios(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_buscar_ultimos_inventarios(p_id_local_actual integer, p_limite integer) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, fecha_registro timestamp without time zone, observacion character varying, productos_contados bigint, usuario text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.observacion,
            COUNT(
                icd.id_inventario_cierre_detalle
            ) AS productos_contados,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) ic
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.fecha_inventario <= CURRENT_DATE
        GROUP BY
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.observacion,
            u.nombres,
            u.apellido_paterno
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
        LIMIT p_limite
$$;


--
-- Name: inv_repository_cerrar_inventario_en_base_datos(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_cerrar_inventario_en_base_datos(p_id_inventario_cierre integer) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE inventario_cierre
        SET
            estado_inventario = 'CERRADO',
            fecha_registro = (
                CURRENT_TIMESTAMP
                AT TIME ZONE 'America/Lima'
            )
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
          AND estado_inventario IN (
              'BORRADOR',
              'INCOMPLETO'
          )
        RETURNING id_inventario_cierre
$$;


--
-- Name: inv_repository_consultar_productos_para_inventario(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_consultar_productos_para_inventario(p_id_inventario_cierre integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, id_categoria integer, categoria character varying, stock_contado numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            p.id_categoria,
            cp.nombre AS categoria,
            icd.stock_contado
        FROM producto p
        INNER JOIN categoria_producto cp
            ON cp.id_categoria = p.id_categoria
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_producto = p.id_producto
           AND icd.id_inventario_cierre =
               p_id_inventario_cierre
        WHERE p.activo = TRUE
          AND cp.activo = TRUE
        ORDER BY
            cp.nombre,
            p.nombre
$$;


--
-- Name: inv_repository_contar_detalles_inventario(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_contar_detalles_inventario(p_id_inventario_cierre integer) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT COUNT(*)
        FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
$$;


--
-- Name: inv_repository_contar_productos_activos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_contar_productos_activos() RETURNS TABLE(total bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT COUNT(*) AS total
        FROM producto
        WHERE activo = TRUE
$$;


--
-- Name: inv_repository_crear_cabecera_correccion(integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_crear_cabecera_correccion(p_id_inventario integer, p_id_usuario integer, p_motivo text, p_observacion text) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_cierre_correccion (
            id_inventario_cierre,
            usuario_correccion,
            motivo_correccion,
            observacion
        )
        VALUES (
            p_id_inventario,
            p_id_usuario,
            p_motivo,
            p_observacion
        )
        RETURNING id_inventario_cierre_correccion
$$;


--
-- Name: inv_repository_crear_detalle_correccion(bigint, integer, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_crear_detalle_correccion(p_id_correccion bigint, p_id_producto integer, p_stock_anterior numeric, p_stock_nuevo numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_cierre_correccion_detalle (
            id_inventario_cierre_correccion,
            id_producto,
            stock_anterior,
            stock_nuevo
        )
        VALUES (
            p_id_correccion,
            p_id_producto,
            p_stock_anterior,
            p_stock_nuevo
        )
$$;


--
-- Name: inv_repository_crear_inventario_actual(integer, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_crear_inventario_actual(p_id_local_actual integer, p_fecha_inventario date, p_id_usuario integer) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_cierre (
            id_local,
            fecha_inventario,
            estado_inventario,
            usuario_registro
        )
        VALUES (
            p_id_local_actual,
            p_fecha_inventario,
            'BORRADOR',
            p_id_usuario
        )
        ON CONFLICT (id_local, fecha_inventario)
        DO NOTHING
        RETURNING id_inventario_cierre
$$;


--
-- Name: inv_repository_eliminar_detalle_inventario(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_eliminar_detalle_inventario(p_id_inventario_cierre integer, p_id_producto integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
          AND id_producto = p_id_producto
$$;


--
-- Name: inv_repository_eliminar_inventario_provisional_1(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_eliminar_inventario_provisional_1(p_id_inventario_cierre integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
$$;


--
-- Name: inv_repository_eliminar_inventario_provisional_2(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_eliminar_inventario_provisional_2(p_id_inventario_cierre integer) RETURNS boolean
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH eliminada AS (DELETE FROM inventario_cierre
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
          AND estado_inventario IN (
              'BORRADOR',
              'INCOMPLETO'
          ) RETURNING 1) SELECT EXISTS(SELECT 1 FROM eliminada)
$$;


--
-- Name: inv_repository_guardar_detalle_inventario(integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_guardar_detalle_inventario(p_id_inventario_cierre integer, p_id_producto integer, p_stock_contado numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO inventario_cierre_detalle (
            id_inventario_cierre,
            id_producto,
            stock_contado
        )
        VALUES (
            p_id_inventario_cierre,
            p_id_producto,
            p_stock_contado
        )
        ON CONFLICT (
            id_inventario_cierre,
            id_producto
        )
        DO UPDATE SET
            stock_contado = EXCLUDED.stock_contado
$$;


--
-- Name: inv_repository_listar_historial_correcciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_listar_historial_correcciones(p_id_inventario integer) RETURNS TABLE(id_inventario_cierre_correccion bigint, fecha_correccion timestamp without time zone, motivo_correccion character varying, observacion character varying, corregido_por text, id_producto integer, codigo character varying, producto character varying, unidad character varying, stock_anterior numeric, stock_nuevo numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            icc.id_inventario_cierre_correccion,
            icc.fecha_correccion,
            icc.motivo_correccion,
            icc.observacion,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS corregido_por,
            iccd.id_producto,
            p.codigo,
            p.nombre AS producto,
            p.unidad,
            iccd.stock_anterior,
            iccd.stock_nuevo
        FROM inventario_cierre_correccion icc
        JOIN usuario u
            ON u.id_usuario = icc.usuario_correccion
        JOIN inventario_cierre_correccion_detalle iccd
            ON iccd.id_inventario_cierre_correccion =
               icc.id_inventario_cierre_correccion
        JOIN producto p
            ON p.id_producto = iccd.id_producto
        WHERE icc.id_inventario_cierre = p_id_inventario
        ORDER BY
            icc.fecha_correccion DESC,
            icc.id_inventario_cierre_correccion DESC,
            p.nombre
$$;


--
-- Name: inv_repository_listar_inventarios_para_revision(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_listar_inventarios_para_revision(p_id_local_actual integer) RETURNS TABLE(id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, fecha_registro timestamp without time zone, usuario_registro integer, registrado_por text, usuario_revision integer, revisado_por text, motivo_revision character varying, observacion character varying, productos_contados bigint, productos_en_cero bigint, productos_con_existencia bigint, total_productos_actuales bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.usuario_registro,
            CONCAT_WS(
                ' ',
                ur.nombres,
                ur.apellido_paterno,
                ur.apellido_materno
            ) AS registrado_por,
            ic.usuario_revision,
            CASE
                WHEN ic.usuario_revision IS NULL THEN NULL
                ELSE CONCAT_WS(
                    ' ',
                    uv.nombres,
                    uv.apellido_paterno,
                    uv.apellido_materno
                )
            END AS revisado_por,
            ic.motivo_revision,
            ic.observacion,
            COUNT(icd.id_inventario_cierre_detalle)
                AS productos_contados,
            COUNT(*) FILTER (
                WHERE icd.stock_contado = 0
            ) AS productos_en_cero,
            COUNT(*) FILTER (
                WHERE icd.stock_contado > 0
            ) AS productos_con_existencia,
            (
                SELECT COUNT(*)
                FROM producto p
                WHERE p.activo = TRUE
            ) AS total_productos_actuales
        FROM inventario_cierre ic
        JOIN usuario ur
            ON ur.id_usuario = ic.usuario_registro
        LEFT JOIN usuario uv
            ON uv.id_usuario = ic.usuario_revision
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        WHERE ic.id_local=p_id_local_actual AND ic.estado_inventario = 'CERRADO'
        GROUP BY
            ic.id_inventario_cierre,
            ur.id_usuario,
            uv.id_usuario
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
$$;


--
-- Name: inv_repository_producto_activo_existe(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_repository_producto_activo_existe(p_id_producto integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
            SELECT 1
            FROM producto
            WHERE id_producto = p_id_producto
              AND activo = TRUE
        ) AS existe
$$;


--
-- Name: inv_weekly_report_1(integer, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_weekly_report_1(p_local integer, p_desde date, p_hasta date) RETURNS TABLE(fecha date, cobros bigint, cobros_con_inventario bigint, jornada_cerrada boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH cobros AS (SELECT (creado_en AT TIME ZONE 'America/Lima')::date fecha,count(*) cobros,
        count(*) FILTER (WHERE EXISTS (SELECT 1 FROM movimiento_inventario m
            WHERE m.id_movimiento_inventario=c.id_movimiento AND m.id_local=c.id_local)) cobros_con_inventario
        FROM salon_cobro c WHERE id_local=p_local
        AND (creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta GROUP BY 1),
        cierres AS (SELECT fecha FROM inventario_jornada WHERE id_local=p_local AND cerrado_en IS NOT NULL
            AND fecha BETWEEN p_desde AND p_hasta)
        SELECT coalesce(c.fecha,j.fecha) fecha,coalesce(c.cobros,0) cobros,
            coalesce(c.cobros_con_inventario,0) cobros_con_inventario,j.fecha IS NOT NULL jornada_cerrada
        FROM cobros c FULL JOIN cierres j USING(fecha)
$$;


--
-- Name: inv_weekly_report_2(integer, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_weekly_report_2(p_local integer, p_desde date, p_hasta date) RETURNS TABLE(fecha date, id_presentacion integer, id_promocion integer, nombre text, cantidad numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH lineas AS (
        SELECT (creado_en AT TIME ZONE 'America/Lima')::date fecha,linea FROM salon_cobro c
        CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') linea
        WHERE c.comprobante->'anulacion' IS NULL AND id_local=p_local AND (creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
      ), demanda AS (
        SELECT fecha,(linea->>'id_presentacion')::int id_presentacion,(linea->>'id_promocion')::int id_promocion,
          linea->>'nombre' nombre,(linea->>'cantidad')::numeric cantidad FROM lineas
        UNION ALL SELECT fecha,(opcion->>'id_presentacion')::int,NULL,opcion->>'nombre',(linea->>'cantidad')::numeric
          FROM lineas CROSS JOIN LATERAL jsonb_array_elements(coalesce(linea->'selecciones_promocion','[]'::jsonb)) opcion
          WHERE linea->>'id_promocion' IS NOT NULL)
        SELECT fecha,id_presentacion,id_promocion,max(nombre) nombre,sum(cantidad) cantidad
        FROM demanda GROUP BY fecha,id_presentacion,id_promocion
$$;


--
-- Name: inv_weekly_report_3(integer, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_weekly_report_3(p_local integer, p_desde date, p_hasta date) RETURNS TABLE(fecha date, id_producto integer, cantidad numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT (c.creado_en AT TIME ZONE 'America/Lima')::date fecha,d.id_producto,sum(d.cantidad) cantidad
        FROM salon_cobro c JOIN movimiento_inventario m ON m.id_movimiento_inventario=c.id_movimiento AND m.id_local=c.id_local
        JOIN movimiento_inventario_detalle d USING(id_movimiento_inventario)
        WHERE c.id_local=p_local AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        GROUP BY 1,d.id_producto
$$;


--
-- Name: inv_weekly_report_4(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inv_weekly_report_4(p_local integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, presentacion numeric, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, stock_actual numeric, compra_habilitada boolean, stock_minimo numeric, stock_maximo numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,p.presentacion,p.id_categoria,cat.nombre categoria,
        p.id_proveedor,pr.nombre proveedor,s.stock_actual,
        coalesce(p.activo AND cat.activo AND pr.activo,false) compra_habilitada,
        coalesce(sl.stock_minimo,0) stock_minimo,sl.stock_maximo
        FROM producto p LEFT JOIN categoria_producto cat USING(id_categoria) LEFT JOIN proveedor pr USING(id_proveedor)
        LEFT JOIN inventario_stock_teorico s ON s.id_producto=p.id_producto AND s.id_local=p_local
        LEFT JOIN producto_stock_local sl ON sl.id_producto=p.id_producto AND sl.id_local=p_local
        WHERE p.activo OR coalesce(s.stock_actual,0)<>0 ORDER BY p.nombre
$$;


--
-- Name: inventario_abrir_jornada(integer, integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_abrir_jornada(local_id integer, usuario_id integer DEFAULT NULL::integer, fecha_solicitada date DEFAULT NULL::date) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE identidad bigint; ultima date; siguiente date;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('inventario-dia:'||local_id));
 SELECT id_jornada INTO identidad FROM inventario_jornada WHERE id_local=local_id AND cerrado_en IS NULL;
 IF identidad IS NOT NULL THEN RETURN identidad; END IF;
 SELECT max(fecha) INTO ultima FROM inventario_jornada WHERE id_local=local_id;
 siguiente:=greatest((clock_timestamp() AT TIME ZONE 'America/Lima')::date,ultima+1);
 IF fecha_solicitada IS NOT NULL THEN
  IF fecha_solicitada> siguiente OR (ultima IS NOT NULL AND fecha_solicitada<=ultima) THEN RAISE EXCEPTION 'Fecha operativa inválida'; END IF;
  siguiente:=fecha_solicitada;
 END IF;
 INSERT INTO inventario_jornada(id_local,fecha,abierto_por) VALUES(local_id,siguiente,usuario_id) RETURNING id_jornada INTO identidad;
 INSERT INTO inventario_jornada_inicio SELECT identidad,id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=local_id;
 RETURN identidad;
END $$;


--
-- Name: inventario_cobro_jornada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_cobro_jornada() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
 NEW.id_jornada:=inventario_abrir_jornada(NEW.id_local,NEW.id_usuario);
 RETURN NEW;
END $$;


--
-- Name: inventario_operativo_instalado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_operativo_instalado() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT to_regclass('public.inventario_evento') IS NOT NULL
$$;


--
-- Name: inventario_productos_revision(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_productos_revision(p_local integer, p_inventario integer) RETURNS TABLE(id_producto integer, codigo character varying, producto character varying, categoria character varying, unidad character varying, stock_minimo numeric, activo boolean, stock_contado numeric, fue_contado boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
            p.id_producto,
            p.codigo,
            p.nombre AS producto,
            cp.nombre AS categoria,
            p.unidad,
            public.stock_minimo_por_local(p.id_producto, p_local, p.stock_minimo) AS stock_minimo,
            p.activo,
            icd.stock_contado,
            CASE
                WHEN icd.id_inventario_cierre_detalle
                     IS NULL
                THEN FALSE
                ELSE TRUE
            END AS fue_contado
        FROM producto p
        JOIN categoria_producto cp
            ON cp.id_categoria = p.id_categoria
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_producto = p.id_producto
           AND icd.id_inventario_cierre = p_inventario
        WHERE p.activo = TRUE
           OR icd.id_inventario_cierre_detalle IS NOT NULL
        ORDER BY
            fue_contado DESC,
            cp.nombre,
            p.nombre
$$;


--
-- Name: inventario_registrar_evento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_registrar_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE fila record; cab record; delta numeric; jornada bigint; anterior numeric; actual numeric; motivo_evento text;
BEGIN
 IF TG_OP='DELETE' THEN fila:=OLD; ELSE fila:=NEW; END IF;
 IF TG_OP='UPDATE' AND (NEW.id_producto<>OLD.id_producto) THEN RAISE EXCEPTION 'No cambie el producto de una operación registrada'; END IF;
 IF TG_TABLE_NAME='movimiento_inventario_detalle' THEN
  IF TG_OP='UPDATE' AND NEW.id_movimiento_inventario<>OLD.id_movimiento_inventario THEN RAISE EXCEPTION 'Movimiento inmutable'; END IF;
  SELECT m.id_local,m.usuario_registro,m.tipo_movimiento,m.motivo_movimiento INTO cab FROM movimiento_inventario m WHERE id_movimiento_inventario=fila.id_movimiento_inventario;
  anterior:=CASE WHEN TG_OP='INSERT' THEN 0 ELSE OLD.cantidad END;
  actual:=CASE WHEN TG_OP='DELETE' THEN 0 ELSE NEW.cantidad END;
  delta:=(actual-anterior)*CASE WHEN cab.tipo_movimiento='ENTRADA' THEN 1 ELSE -1 END;
  motivo_evento:=cab.motivo_movimiento;
 ELSE
  IF TG_OP='UPDATE' AND NEW.id_factura_recepcion<>OLD.id_factura_recepcion THEN RAISE EXCEPTION 'Recepción inmutable'; END IF;
  SELECT o.id_local,f.usuario_recepcion AS usuario_registro INTO cab FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra) WHERE f.id_factura_recepcion=fila.id_factura_recepcion;
  anterior:=CASE WHEN TG_OP='INSERT' THEN 0 ELSE OLD.cantidad_recibida END;
  actual:=CASE WHEN TG_OP='DELETE' THEN 0 ELSE NEW.cantidad_recibida END;
  delta:=actual-anterior;
  motivo_evento:=CASE WHEN TG_OP='INSERT' THEN 'RECEPCION_COMPRA' ELSE 'CORRECCION_RECEPCION' END;
 END IF;
 IF delta<>0 THEN
  jornada:=inventario_abrir_jornada(cab.id_local,cab.usuario_registro);
  INSERT INTO inventario_evento(id_local,id_jornada,id_producto,cantidad,motivo,origen,id_origen)
  VALUES(cab.id_local,jornada,fila.id_producto,delta,motivo_evento,
   CASE WHEN TG_TABLE_NAME='movimiento_inventario_detalle' THEN 'MOVIMIENTO' ELSE 'RECEPCION' END,
   CASE WHEN TG_TABLE_NAME='movimiento_inventario_detalle' THEN (to_jsonb(fila)->>'id_movimiento_inventario')::bigint ELSE (to_jsonb(fila)->>'id_factura_recepcion')::bigint END);
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;


--
-- Name: inventario_stock_consulta_historico(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_stock_consulta_historico(p_local integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, stock_minimo numeric, id_categoria integer, categoria character varying, fecha_ultimo_conteo date, stock_ultimo_conteo numeric, entradas_recepcion numeric, entradas_movimiento numeric, salidas_movimiento numeric, stock_actual numeric, estado_stock text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH stock_calculado AS (
            SELECT
                p.id_producto,
                p.codigo,
                p.nombre,
                p.unidad,
                public.stock_minimo_por_local(p.id_producto, p_local, p.stock_minimo) AS stock_minimo,
                p.id_categoria,
                cp.nombre AS categoria,

                ultimo_conteo.fecha_inventario
                    AS fecha_ultimo_conteo,

                ultimo_conteo.stock_contado
                    AS stock_ultimo_conteo,

                COALESCE(
                    recepciones.cantidad,
                    0
                ) AS entradas_recepcion,

                COALESCE(
                    movimientos.entradas,
                    0
                ) AS entradas_movimiento,

                COALESCE(
                    movimientos.salidas,
                    0
                ) AS salidas_movimiento,

                CASE
                    WHEN ultimo_conteo.stock_contado IS NULL
                        THEN COALESCE(recepciones.cantidad,0) + COALESCE(movimientos.entradas,0) - COALESCE(movimientos.salidas,0)
                    ELSE
                        ultimo_conteo.stock_contado
                        + COALESCE(
                            recepciones.cantidad,
                            0
                        )
                        + COALESCE(
                            movimientos.entradas,
                            0
                        )
                        - COALESCE(
                            movimientos.salidas,
                            0
                        )
                END AS stock_actual

            FROM producto p

            INNER JOIN categoria_producto cp
                ON cp.id_categoria = p.id_categoria

            LEFT JOIN LATERAL (
                SELECT
                    ic.fecha_inventario, ic.fecha_registro,
                    icd.stock_contado
                FROM inventario_cierre_detalle icd
                INNER JOIN (SELECT * FROM inventario_cierre WHERE id_local=p_local) ic
                    ON ic.id_inventario_cierre =
                       icd.id_inventario_cierre
                WHERE icd.id_producto = p.id_producto
                  AND ic.estado_inventario = 'CERRADO'
                  AND ic.fecha_inventario <= CURRENT_DATE
                ORDER BY
                    ic.fecha_inventario DESC,
                    ic.id_inventario_cierre DESC
                LIMIT 1
            ) AS ultimo_conteo ON TRUE

            LEFT JOIN LATERAL (
                SELECT
                    SUM(frd.cantidad_recibida) AS cantidad
                FROM factura_recepcion_detalle frd
                INNER JOIN (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_local) fr
                    ON fr.id_factura_recepcion =
                       frd.id_factura_recepcion
                WHERE frd.id_producto = p.id_producto
                  AND (ultimo_conteo.fecha_inventario IS NULL OR fr.fecha_recepcion > ultimo_conteo.fecha_inventario)
                  AND fr.fecha_recepcion <= CURRENT_DATE
            ) AS recepciones ON TRUE

            LEFT JOIN LATERAL (
                SELECT
                    SUM(
                        CASE
                            WHEN mi.tipo_movimiento = 'ENTRADA'
                                THEN mid.cantidad
                            ELSE 0
                        END
                    ) AS entradas,

                    SUM(
                        CASE
                            WHEN mi.tipo_movimiento = 'SALIDA'
                                THEN mid.cantidad
                            ELSE 0
                        END
                    ) AS salidas

                FROM movimiento_inventario_detalle mid
                INNER JOIN (SELECT * FROM movimiento_inventario WHERE id_local=p_local) mi
                    ON mi.id_movimiento_inventario =
                       mid.id_movimiento_inventario
                WHERE mid.id_producto = p.id_producto
                  AND (ultimo_conteo.fecha_inventario IS NULL OR mi.fecha_movimiento > ultimo_conteo.fecha_inventario OR (mi.fecha_movimiento = ultimo_conteo.fecha_inventario AND (to_jsonb(mi)->>'registrado_en')::timestamp > ultimo_conteo.fecha_registro))
                  AND mi.fecha_movimiento <= CURRENT_DATE
            ) AS movimientos ON TRUE

            WHERE p.activo = TRUE
              AND cp.activo = TRUE
        )

        SELECT
            *,
            CASE
                WHEN stock_actual IS NULL
                    THEN 'SIN_CONTEO'
                WHEN stock_actual <= 0
                    THEN 'AGOTADO'
                WHEN stock_actual <= stock_minimo
                    THEN 'STOCK_BAJO'
                ELSE 'DISPONIBLE'
            END AS estado_stock
        FROM stock_calculado
        ORDER BY
            categoria,
            nombre
$$;


--
-- Name: inventario_stock_consulta_operativo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_stock_consulta_operativo(p_local integer) RETURNS TABLE(id_producto integer, codigo character varying, nombre character varying, unidad character varying, id_categoria integer, categoria character varying, stock_minimo numeric, stock_maximo numeric, fecha_ultimo_conteo date, stock_ultimo_conteo numeric, stock_actual numeric, entradas_recepcion numeric, entradas_movimiento numeric, salidas_movimiento numeric, estado_stock text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,p.id_categoria,cp.nombre categoria,
            coalesce(sl.stock_minimo,0) stock_minimo,sl.stock_maximo,
            (b.creado_en AT TIME ZONE 'America/Lima')::date fecha_ultimo_conteo,
            s.inicial stock_ultimo_conteo,s.stock_actual,
            coalesce(e.recepciones,0) entradas_recepcion,coalesce(e.entradas,0) entradas_movimiento,
            coalesce(e.salidas,0) salidas_movimiento,
            CASE WHEN s.stock_actual<=0 THEN 'AGOTADO' WHEN s.stock_actual<=coalesce(sl.stock_minimo,0)
              THEN 'STOCK_BAJO' ELSE 'DISPONIBLE' END estado_stock
            FROM inventario_stock_teorico s JOIN producto p USING(id_producto) JOIN categoria_producto cp USING(id_categoria)
            LEFT JOIN producto_stock_local sl ON sl.id_producto=p.id_producto AND sl.id_local=s.id_local
            LEFT JOIN inventario_saldo_inicial b ON b.id_producto=p.id_producto AND b.id_local=s.id_local
            LEFT JOIN (SELECT id_producto,sum(CASE WHEN origen='RECEPCION' THEN cantidad ELSE 0 END) recepciones,
              sum(CASE WHEN origen='MOVIMIENTO' THEN greatest(cantidad,0) ELSE 0 END) entradas,
              sum(CASE WHEN origen='MOVIMIENTO' THEN greatest(-cantidad,0) ELSE 0 END) salidas
              FROM inventario_evento WHERE id_local=p_local GROUP BY id_producto) e ON e.id_producto=p.id_producto
            WHERE s.id_local=p_local AND p.activo AND cp.activo ORDER BY cp.nombre,p.nombre
$$;


--
-- Name: local_permitido(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.local_permitido(p_usuario integer, p_perfil integer, p_local integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT EXISTS (SELECT 1 FROM public.locales_permitidos(p_usuario,p_perfil) l WHERE l.id_local=p_local)
$$;


--
-- Name: locales_permitidos(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.locales_permitidos(p_usuario integer, p_perfil integer) RETURNS TABLE(id_local integer, codigo character varying, nombre character varying, direccion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
        SELECT DISTINCT l.id_local, l.codigo, l.nombre, l.direccion
        FROM local l
        JOIN usuario u ON u.id_usuario=p_usuario AND u.estado_registro=1
        JOIN usuario_perfiles up ON up.id_usuario=u.id_usuario AND up.estado_registro=1
        JOIN perfiles p ON p.id_perfil=up.id_perfil AND p.estado_registro=1
        WHERE l.estado_registro=1 AND p.id_perfil=p_perfil
          AND (p.acceso_todos_locales OR EXISTS (
              SELECT 1 FROM usuario_local ul WHERE ul.id_usuario=u.id_usuario
                AND ul.id_local=l.id_local AND ul.estado_registro=1))
        ORDER BY l.nombre
$$;


--
-- Name: menu_disponible_para_perfil(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.menu_disponible_para_perfil(p_perfil integer, p_opcion integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT public.perfil_tiene_capacidad(p_perfil, 'operar_tienda')
        OR NOT EXISTS (
            SELECT FROM public.menu_requiere_perfil_operativo m WHERE m.id_opcion_menu = p_opcion
        )
$$;


--
-- Name: mov_actualizar_seguimiento(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_actualizar_seguimiento(p_estado text, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE movimiento_seguimiento SET estado=p_estado WHERE id_movimiento=p_id
$$;


--
-- Name: mov_bloquear_codigo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_bloquear_codigo() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock(
    hashtext('movimiento_inventario_codigo')
)
$$;


--
-- Name: mov_buscar_cabecera(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_buscar_cabecera(p_id_local_actual integer, p_id_movimiento integer) RETURNS TABLE(id_movimiento_inventario integer, codigo text, tipo_movimiento text, motivo_movimiento text, fecha_movimiento date, local_relacionado text, id_proveedor integer, proveedor text, observacion text, registrado_por text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    mi.id_movimiento_inventario,
    mi.codigo,
    mi.tipo_movimiento,
    mi.motivo_movimiento,
    mi.fecha_movimiento,
    mi.local_relacionado,
    mi.id_proveedor,
    pr.nombre AS proveedor,
    mi.observacion,
    CONCAT_WS(
        ' ',
        u.nombres,
        u.apellido_paterno,
        u.apellido_materno
    ) AS registrado_por
FROM (SELECT * FROM movimiento_inventario WHERE id_local=p_id_local_actual) mi
JOIN usuario u
    ON u.id_usuario = mi.usuario_registro
LEFT JOIN proveedor pr
    ON pr.id_proveedor = mi.id_proveedor
WHERE mi.id_movimiento_inventario = p_id_movimiento
$$;


--
-- Name: mov_cantidades(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_cantidades(p_id integer) RETURNS TABLE(id_producto integer, cantidad numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto,cantidad FROM movimiento_inventario_detalle WHERE id_movimiento_inventario=p_id
$$;


--
-- Name: mov_cantidades_recibidas(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_cantidades_recibidas(p_id integer) RETURNS TABLE(id_producto integer, cantidad numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT d.id_producto,sum(d.cantidad) FROM movimiento_reintegro r
            JOIN movimiento_inventario_detalle d ON d.id_movimiento_inventario=r.id_movimiento
            WHERE r.id_salida=p_id GROUP BY d.id_producto
$$;


--
-- Name: mov_crear_cabecera(integer, text, text, text, date, integer, text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_crear_cabecera(p_id_local_actual integer, p_codigo text, p_tipo_movimiento text, p_motivo_movimiento text, p_fecha_movimiento date, p_id_usuario integer, p_local_relacionado text, p_id_proveedor integer, p_observacion text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO movimiento_inventario (
    id_local,
    codigo,
    tipo_movimiento,
    motivo_movimiento,
    fecha_movimiento,
    usuario_registro,
    local_relacionado,
    id_proveedor,
    observacion
)
VALUES (
    p_id_local_actual,
    p_codigo,
    p_tipo_movimiento,
    p_motivo_movimiento,
    p_fecha_movimiento,
    p_id_usuario,
    p_local_relacionado,
    p_id_proveedor,
    p_observacion
)
RETURNING id_movimiento_inventario
$$;


--
-- Name: mov_crear_detalle(integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_crear_detalle(p_id_movimiento integer, p_id_producto integer, p_cantidad numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO movimiento_inventario_detalle (
    id_movimiento_inventario,
    id_producto,
    cantidad
)
VALUES (
    p_id_movimiento,
    p_id_producto,
    p_cantidad
)
$$;


--
-- Name: mov_destino_bloqueado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_destino_bloqueado(p_id integer) RETURNS TABLE(id_local integer, nombre text)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_local,nombre FROM local WHERE id_local=p_id AND estado_registro=1 FOR SHARE
$$;


--
-- Name: mov_detalles_seguimiento(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_detalles_seguimiento(p_id integer) RETURNS TABLE(id_producto integer, codigo text, nombre text, unidad text, cantidad numeric, recibido numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,d.cantidad,
  COALESCE((SELECT sum(rd.cantidad) FROM movimiento_reintegro r
    JOIN movimiento_inventario_detalle rd ON rd.id_movimiento_inventario=r.id_movimiento
    WHERE r.id_salida=p_id AND rd.id_producto=d.id_producto),0) AS recibido
FROM movimiento_inventario_detalle d JOIN producto p USING(id_producto)
WHERE d.id_movimiento_inventario=p_id ORDER BY p.nombre
$$;


--
-- Name: mov_guia_registrada(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_guia_registrada(p_id integer, p_guia text) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT 1 FROM movimiento_reintegro WHERE id_salida=p_id AND guia_proveedor=p_guia
$$;


--
-- Name: mov_listar_detalles(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_listar_detalles(p_id_movimiento integer) RETURNS TABLE(id_producto integer, codigo text, nombre text, unidad text, cantidad numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    p.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    mid.cantidad
FROM movimiento_inventario_detalle mid
JOIN producto p
    ON p.id_producto = mid.id_producto
WHERE mid.id_movimiento_inventario = p_id_movimiento
ORDER BY p.nombre
$$;


--
-- Name: mov_listar_seguimiento(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_listar_seguimiento(p_local integer) RETURNS TABLE(id integer, codigo text, fecha date, id_local integer, id_local_destino integer, estado text, motivo text, origen text, destino text, proveedor text, observacion text, registrado_por text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT m.id_movimiento_inventario AS id, m.codigo,m.fecha_movimiento AS fecha,
  m.id_local,s.id_local_destino,s.estado,m.motivo_movimiento AS motivo,
  o.nombre AS origen,d.nombre AS destino,p.nombre AS proveedor,m.observacion,
  concat_ws(' ',u.nombres,u.apellido_paterno) AS registrado_por
FROM movimiento_seguimiento s JOIN movimiento_inventario m ON m.id_movimiento_inventario=s.id_movimiento
JOIN local o ON o.id_local=m.id_local LEFT JOIN local d ON d.id_local=s.id_local_destino
LEFT JOIN proveedor p ON p.id_proveedor=m.id_proveedor JOIN usuario u ON u.id_usuario=m.usuario_registro
WHERE m.id_local=p_local OR s.id_local_destino=p_local ORDER BY m.id_movimiento_inventario DESC
$$;


--
-- Name: mov_locales_destino(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_locales_destino(p_id_local_actual integer) RETURNS TABLE(id_local integer, nombre text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_local,nombre FROM local WHERE estado_registro=1 AND id_local<>p_id_local_actual ORDER BY nombre
$$;


--
-- Name: mov_producto_activo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_producto_activo(p_id_producto integer) RETURNS TABLE(id_producto integer, codigo text, nombre text, unidad text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto, codigo, nombre, unidad
FROM producto
WHERE id_producto = p_id_producto
  AND activo = TRUE
$$;


--
-- Name: mov_productos_activos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_productos_activos() RETURNS TABLE(id_producto integer, codigo text, nombre text, unidad text, id_categoria integer, categoria text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    p.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    p.id_categoria,
    cp.nombre AS categoria
FROM producto p
JOIN categoria_producto cp
    ON cp.id_categoria = p.id_categoria
WHERE p.activo = TRUE
  AND cp.activo = TRUE
ORDER BY cp.nombre, p.nombre
$$;


--
-- Name: mov_proveedor_activo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_proveedor_activo(p_id_proveedor integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM proveedor
    WHERE id_proveedor = p_id_proveedor
      AND activo = TRUE
)
$$;


--
-- Name: mov_proveedores_activos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_proveedores_activos() RETURNS TABLE(id_proveedor integer, nombre text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_proveedor, nombre
FROM proveedor
WHERE activo = TRUE
ORDER BY nombre
$$;


--
-- Name: mov_recepciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_recepciones(p_id integer) RETURNS TABLE(codigo text, guia_proveedor text, fecha text, nombre text, unidad text, cantidad double precision)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT m.codigo,r.guia_proveedor,m.fecha_movimiento::text AS fecha,
    p.nombre,p.unidad,d.cantidad::float AS cantidad
FROM movimiento_reintegro r JOIN movimiento_inventario m ON m.id_movimiento_inventario=r.id_movimiento
JOIN movimiento_inventario_detalle d ON d.id_movimiento_inventario=m.id_movimiento_inventario
JOIN producto p USING(id_producto) WHERE r.id_salida=p_id ORDER BY r.id_movimiento,p.nombre
$$;


--
-- Name: mov_registrar_reintegro(integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_registrar_reintegro(p_id integer, p_salida integer, p_guia text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO movimiento_reintegro(id_movimiento,id_salida,guia_proveedor) VALUES (p_id,p_salida,p_guia)
$$;


--
-- Name: mov_registrar_salida(integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_registrar_salida(p_id integer, p_destino integer, p_estado text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO movimiento_seguimiento (id_movimiento, id_local_destino, estado) VALUES (p_id,p_destino,p_estado)
$$;


--
-- Name: mov_salida_bloqueada(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_salida_bloqueada(p_id integer, p_local integer) RETURNS TABLE(id_local integer, id_proveedor integer, codigo text, id_local_destino integer, estado text, motivo_recepcion text)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT m.id_local,m.id_proveedor,m.codigo,s.id_local_destino,s.estado,motivo.motivo_recepcion FROM movimiento_seguimiento s
JOIN movimiento_inventario m ON m.id_movimiento_inventario=s.id_movimiento
LEFT JOIN public.movimiento_motivo motivo ON motivo.codigo=m.motivo_movimiento
WHERE s.id_movimiento=p_id AND (m.id_local=p_local OR s.id_local_destino=p_local)
FOR UPDATE OF s
$$;


--
-- Name: mov_seguimiento_instalado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_seguimiento_instalado() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.movimiento_seguimiento') IS NOT NULL
$$;


--
-- Name: mov_siguiente_numero(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mov_siguiente_numero() RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
SELECT COALESCE(
    MAX(
        CASE
            WHEN codigo ~ '^MI-[0-9]+$'
            THEN SUBSTRING(
                codigo FROM 4
            )::INTEGER
            ELSE 0
        END
    ),
    0
) + 1
FROM movimiento_inventario
$_$;


--
-- Name: operaciones_por_local_listas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.operaciones_por_local_listas() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid=to_regclass('public.inventario_cierre')
          AND conname='uq_inventario_local_fecha' AND convalidated)
$$;


--
-- Name: perfil_tiene_capacidad(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.perfil_tiene_capacidad(p_perfil integer, p_capacidad text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT FROM public.perfil_capacidad c JOIN public.perfiles p USING (id_perfil)
        WHERE c.id_perfil = p_perfil AND c.capacidad = p_capacidad AND p.estado_registro = 1
    )
$$;


--
-- Name: permiso_opcion_recurso(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.permiso_opcion_recurso(p_recurso text) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT id_opcion_menu FROM public.permiso_recurso WHERE recurso = p_recurso
$$;


--
-- Name: produccion_actualizar_subproducto(text, numeric, text, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_actualizar_subproducto(p_nombre text, p_rendimiento numeric, p_instruccion text, p_activo boolean, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE subproducto SET nombre=p_nombre,rendimiento=p_rendimiento,
                instruccion=p_instruccion,activo=p_activo WHERE id_subproducto=p_id
$$;


--
-- Name: produccion_bloquear_catalogo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_bloquear_catalogo() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock(hashtext('subproducto_catalogo'))
$$;


--
-- Name: produccion_crear_ingrediente(integer, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_crear_ingrediente(p_subproducto integer, p_producto integer, p_cantidad numeric, p_unidad text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO subproducto_detalle(id_subproducto,id_producto,cantidad,unidad)
                VALUES(p_subproducto,p_producto,p_cantidad,p_unidad)
$$;


--
-- Name: produccion_crear_subproducto(text, text, numeric, text, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_crear_subproducto(p_codigo text, p_nombre text, p_rendimiento numeric, p_unidad text, p_instruccion text, p_activo boolean) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO subproducto(codigo,nombre,rendimiento,unidad,instruccion,activo)
                VALUES(p_codigo,p_nombre,p_rendimiento,p_unidad,p_instruccion,p_activo)
                RETURNING id_subproducto
$$;


--
-- Name: produccion_eliminar_ingredientes(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_eliminar_ingredientes(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM subproducto_detalle WHERE id_subproducto=p_id
$$;


--
-- Name: produccion_en_recetas_activas(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_en_recetas_activas(p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS(SELECT 1 FROM receta_detalle d JOIN receta r USING(id_receta)
WHERE d.id_subproducto=p_id AND r.activo)
$$;


--
-- Name: produccion_ingredientes(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_ingredientes(p_id integer) RETURNS TABLE(id_producto integer, cantidad numeric, unidad text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto,cantidad,unidad FROM subproducto_detalle WHERE id_subproducto=p_id
$$;


--
-- Name: produccion_listar_grupos_salsa(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_listar_grupos_salsa() RETURNS TABLE(id_grupo_salsa integer, id_presentacion_venta integer, cantidad_maxima smallint, activo boolean, id_item_carta integer, codigo_item text, item_carta text, categoria_carta text, contenido numeric, unidad_presentacion text, precio numeric, total_opciones bigint, opciones jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    gs.id_grupo_salsa,
    gs.id_presentacion_venta,
    gs.cantidad_maxima,
    gs.activo,

    ic.id_item_carta,
    ic.codigo AS codigo_item,
    ic.nombre AS item_carta,
    cc.nombre AS categoria_carta,

    pv.contenido,
    pv.unidad AS unidad_presentacion,
    pv.precio,

    COUNT(gso.id_grupo_salsa)
        AS total_opciones,

    COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'id_producto',
                    gso.id_producto,

                'codigo',
                    p.codigo,

                'producto',
                    CASE
                        WHEN gso.id_producto IS NULL
                            THEN 'Sin salsa'
                        ELSE p.nombre
                    END,

                'cantidad',
                    gso.cantidad,

                'unidad',
                    gso.unidad,

                'es_sin_salsa',
                    CASE
                        WHEN gso.id_producto IS NULL
                            THEN TRUE
                        ELSE FALSE
                    END
            )
            ORDER BY
                (
                    gso.id_producto IS NULL
                ),
                p.nombre
        )
        FILTER (
            WHERE gso.id_grupo_salsa IS NOT NULL
        ),
        '[]'::JSONB
    ) AS opciones

FROM grupo_salsa AS gs

INNER JOIN presentacion_venta AS pv
    ON pv.id_presentacion_venta =
        gs.id_presentacion_venta

INNER JOIN item_carta AS ic
    ON ic.id_item_carta =
        pv.id_item_carta

INNER JOIN categoria_carta AS cc
    ON cc.id_categoria_carta =
        ic.id_categoria_carta

LEFT JOIN grupo_salsa_opcion AS gso
    ON gso.id_grupo_salsa =
        gs.id_grupo_salsa

LEFT JOIN producto AS p
    ON p.id_producto =
        gso.id_producto

GROUP BY
    gs.id_grupo_salsa,
    gs.id_presentacion_venta,
    gs.cantidad_maxima,
    gs.activo,
    ic.id_item_carta,
    ic.codigo,
    ic.nombre,
    cc.nombre,
    pv.contenido,
    pv.unidad,
    pv.precio

ORDER BY ic.nombre ASC
$$;


--
-- Name: produccion_listar_subproductos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_listar_subproductos() RETURNS TABLE(id_subproducto integer, codigo text, nombre text, rendimiento numeric, unidad text, activo boolean, instruccion text, total_ingredientes bigint, ingredientes jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    s.id_subproducto,
    s.codigo,
    s.nombre,
    s.rendimiento,
    s.unidad,
    s.activo,
    s.instruccion,

    COUNT(sd.id_producto)
        AS total_ingredientes,

    COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'id_producto', p.id_producto,
                'codigo', p.codigo,
                'producto', p.nombre,
                'cantidad', sd.cantidad,
                'unidad', sd.unidad,
                'activo', p.activo
            )
            ORDER BY p.nombre
        ) FILTER (
            WHERE sd.id_producto IS NOT NULL
        ),
        '[]'::JSONB
    ) AS ingredientes

FROM subproducto AS s

LEFT JOIN subproducto_detalle AS sd
    ON sd.id_subproducto = s.id_subproducto

LEFT JOIN producto AS p
    ON p.id_producto = sd.id_producto

GROUP BY
    s.id_subproducto,
    s.codigo,
    s.nombre,
    s.rendimiento,
    s.unidad,
    s.activo

ORDER BY s.nombre ASC
$$;


--
-- Name: produccion_nombre_existe(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_nombre_existe(p_nombre text, p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS(SELECT 1 FROM subproducto
            WHERE lower(btrim(nombre))=lower(p_nombre)
              AND (p_id IS NULL OR id_subproducto<>p_id))
$$;


--
-- Name: produccion_productos_formulario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_productos_formulario() RETURNS TABLE(id integer, codigo text, nombre text, unidad text, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto AS id,codigo,nombre,unidad,activo FROM producto ORDER BY nombre
$$;


--
-- Name: produccion_siguiente_codigo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_siguiente_codigo() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
SELECT 'SP-' || lpad(numero, greatest(3, length(numero)), '0')
FROM (SELECT (coalesce(max(substring(codigo FROM 4)::bigint),0)+1)::text AS numero
                FROM subproducto WHERE codigo ~ '^SP-[0-9]+$') siguiente
$_$;


--
-- Name: produccion_subproducto_bloqueado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.produccion_subproducto_bloqueado(p_id integer) RETURNS TABLE(codigo text, unidad text, activo boolean, nombre text, rendimiento numeric, instruccion text, id_subproducto integer)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT codigo, unidad, activo, nombre, rendimiento, instruccion, id_subproducto FROM subproducto WHERE id_subproducto=p_id FOR UPDATE
$$;


--
-- Name: promo_actualizar(text, numeric, time without time zone, time without time zone, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_actualizar(p_nombre text, p_precio numeric, p_inicio time without time zone, p_fin time without time zone, p_activo boolean, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE promocion SET nombre=p_nombre,precio=p_precio,hora_inicio=p_inicio,hora_fin=p_fin,activo=p_activo WHERE id_promocion=p_id
$$;


--
-- Name: promo_actualizar_grupo(integer, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_actualizar_grupo(p_elegir integer, p_repetir boolean, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE promocion_grupo SET cantidad_elegir=p_elegir,permite_repetir=p_repetir WHERE id_promocion_grupo=p_id
$$;


--
-- Name: promo_bloquear_catalogo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_bloquear_catalogo() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
LOCK TABLE promocion IN SHARE ROW EXCLUSIVE MODE
$$;


--
-- Name: promo_bloquear_presentacion(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_bloquear_presentacion(p_id integer) RETURNS TABLE(activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pv.activo AND ic.activo AS activo FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta) WHERE pv.id_presentacion_venta=p_id FOR SHARE OF pv,ic
$$;


--
-- Name: promo_bloquear_promocion(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_bloquear_promocion(p_id integer) RETURNS TABLE(id_promocion integer, codigo text, nombre text, precio numeric, hora_inicio time without time zone, hora_fin time without time zone, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_promocion, codigo, nombre, precio, hora_inicio, hora_fin, activo FROM promocion WHERE id_promocion=p_id FOR UPDATE
$$;


--
-- Name: promo_buscar(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_buscar(p_id integer) RETURNS TABLE(id_promocion integer, codigo text, nombre text, precio numeric, hora_inicio time without time zone, hora_fin time without time zone, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_promocion, codigo, nombre, precio, hora_inicio, hora_fin, activo FROM promocion WHERE id_promocion=p_id
$$;


--
-- Name: promo_crear(text, text, numeric, time without time zone, time without time zone, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_crear(p_codigo text, p_nombre text, p_precio numeric, p_inicio time without time zone, p_fin time without time zone, p_activo boolean) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO promocion(codigo,nombre,precio,hora_inicio,hora_fin,activo) VALUES (p_codigo,p_nombre,p_precio,p_inicio,p_fin,p_activo) RETURNING id_promocion
$$;


--
-- Name: promo_crear_grupo(integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_crear_grupo(p_promo integer, p_elegir integer, p_repetir boolean) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO promocion_grupo(id_promocion,cantidad_elegir,permite_repetir) VALUES (p_promo,p_elegir,p_repetir) RETURNING id_promocion_grupo
$$;


--
-- Name: promo_crear_opcion(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_crear_opcion(p_grupo integer, p_pid integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO promocion_opcion(id_promocion_grupo,id_presentacion_venta) VALUES (p_grupo,p_pid) ON CONFLICT (id_promocion_grupo,id_presentacion_venta) DO NOTHING
$$;


--
-- Name: promo_crear_reposicion(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_crear_reposicion(p_promo integer, p_pid integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO promocion_reposicion(id_promocion,id_presentacion_venta) VALUES (p_promo,p_pid)
$$;


--
-- Name: promo_eliminar_grupo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_eliminar_grupo(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM promocion_grupo WHERE id_promocion_grupo=p_id
$$;


--
-- Name: promo_eliminar_opciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_eliminar_opciones(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM promocion_opcion WHERE id_promocion_grupo=p_id
$$;


--
-- Name: promo_eliminar_reposiciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_eliminar_reposiciones(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM promocion_reposicion WHERE id_promocion=p_id
$$;


--
-- Name: promo_formulario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_formulario() RETURNS TABLE(id_presentacion_venta integer, codigo text, nombre text, contenido numeric, unidad text, menaje text, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pv.id_presentacion_venta, ic.codigo, ic.nombre,
        pv.contenido, pv.unidad, m.nombre AS menaje, (pv.activo AND ic.activo) AS activo
        FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
        JOIN menaje m USING(id_menaje) ORDER BY ic.nombre,pv.contenido
$$;


--
-- Name: promo_grupos_previos(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_grupos_previos(p_id integer) RETURNS TABLE(id_promocion_grupo integer, id_promocion integer, cantidad_elegir smallint, permite_repetir boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_promocion_grupo, id_promocion, cantidad_elegir, permite_repetir FROM promocion_grupo WHERE id_promocion=p_id
$$;


--
-- Name: promo_listar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_listar() RETURNS TABLE(id_promocion integer, codigo text, nombre text, precio numeric, hora_inicio time without time zone, hora_fin time without time zone, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    id_promocion,
    codigo,
    nombre,
    precio,
    hora_inicio,
    hora_fin,
    activo
FROM promocion
ORDER BY
    activo DESC,
    codigo ASC
$$;


--
-- Name: promo_listar_grupos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_listar_grupos() RETURNS TABLE(id_promocion_grupo integer, id_promocion integer, cantidad_elegir smallint, permite_repetir boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    id_promocion_grupo,
    id_promocion,
    cantidad_elegir,
    permite_repetir
FROM promocion_grupo
ORDER BY
    id_promocion,
    id_promocion_grupo
$$;


--
-- Name: promo_listar_opciones(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_listar_opciones() RETURNS TABLE(id_promocion_opcion integer, id_promocion_grupo integer, id_presentacion_venta integer, id_item_carta integer, codigo_item text, item_carta text, tipo text, id_categoria_carta integer, categoria_carta text, contenido numeric, unidad text, precio_individual numeric, presentacion_activa boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    po.id_promocion_opcion,
    po.id_promocion_grupo,
    po.id_presentacion_venta,

    pv.id_item_carta,
    ic.codigo AS codigo_item,
    ic.nombre AS item_carta,
    ic.tipo,

    cc.id_categoria_carta,
    cc.nombre AS categoria_carta,

    pv.contenido,
    pv.unidad,
    pv.precio AS precio_individual,
    pv.activo AS presentacion_activa

FROM promocion_opcion AS po

INNER JOIN presentacion_venta AS pv
    ON pv.id_presentacion_venta =
        po.id_presentacion_venta

INNER JOIN item_carta AS ic
    ON ic.id_item_carta =
        pv.id_item_carta

INNER JOIN categoria_carta AS cc
    ON cc.id_categoria_carta =
        ic.id_categoria_carta

ORDER BY
    po.id_promocion_grupo,
    ic.nombre ASC
$$;


--
-- Name: promo_listar_reposiciones(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_listar_reposiciones() RETURNS TABLE(id_promocion integer, id_presentacion_venta integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_promocion,id_presentacion_venta
FROM promocion_reposicion
ORDER BY id_promocion,id_presentacion_venta
$$;


--
-- Name: promo_nombre_existe(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_nombre_existe(p_nombre text, p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS(SELECT 1 FROM promocion WHERE lower(trim(nombre))=lower(p_nombre) AND id_promocion<>p_id)
$$;


--
-- Name: promo_opciones_previas(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_opciones_previas(p_id integer) RETURNS TABLE(id_promocion_opcion integer, id_promocion_grupo integer, id_presentacion_venta integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT o.id_promocion_opcion, o.id_promocion_grupo, o.id_presentacion_venta FROM promocion_opcion o JOIN promocion_grupo g USING(id_promocion_grupo) WHERE g.id_promocion=p_id
$$;


--
-- Name: promo_quitar_opciones(integer, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_quitar_opciones(p_id integer, p_opciones integer[]) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM promocion_opcion WHERE id_promocion_grupo=p_id AND NOT (id_presentacion_venta=ANY(p_opciones))
$$;


--
-- Name: promo_reposiciones_instaladas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_reposiciones_instaladas() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.promocion_reposicion') IS NOT NULL
$$;


--
-- Name: promo_reposiciones_previas(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_reposiciones_previas(p_id integer) RETURNS TABLE(id_promocion integer, id_presentacion_venta integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_promocion, id_presentacion_venta FROM promocion_reposicion WHERE id_promocion=p_id
$$;


--
-- Name: promo_siguiente_codigo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promo_siguiente_codigo() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
SELECT 'P-' || lpad(numero, greatest(3, length(numero)), '0')
FROM (
    SELECT (coalesce(max(substring(codigo FROM 3)::bigint), 0) + 1)::text AS numero
    FROM promocion WHERE codigo ~ '^P-[0-9]+$'
) siguiente
$_$;


--
-- Name: proteger_linea_salon(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proteger_linea_salon() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE estado_actual text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN
   SELECT estado INTO estado_actual FROM salon_pedido WHERE id_pedido=OLD.id_pedido FOR UPDATE;
   IF estado_actual='ENVIADO' THEN RAISE EXCEPTION 'Los productos enviados no pueden modificarse'; END IF;
 END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN
   SELECT estado INTO estado_actual FROM salon_pedido WHERE id_pedido=NEW.id_pedido FOR UPDATE;
   IF estado_actual='ENVIADO' THEN RAISE EXCEPTION 'No se pueden agregar productos al pedido enviado'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;


--
-- Name: proteger_pedido_salon(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proteger_pedido_salon() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF OLD.estado='ENVIADO' THEN RAISE EXCEPTION 'Un pedido enviado no puede modificarse'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;


--
-- Name: proveedor_limites_comerciales(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proveedor_limites_comerciales() RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT jsonb_object_agg(campo, longitud_maxima) FROM public.proveedor_campo_comercial
$$;


--
-- Name: recep_actualizar_cantidad(integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_actualizar_cantidad(p_id_detalle integer, p_cantidad numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE factura_recepcion_detalle
SET cantidad_recibida = p_cantidad
WHERE id_factura_recepcion_detalle = p_id_detalle
$$;


--
-- Name: recep_actualizar_estado(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_actualizar_estado(p_id_orden integer, p_estado text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE orden_compra
SET estado_orden_compra = p_estado
WHERE id_orden_compra = p_id_orden
$$;


--
-- Name: recep_actualizar_factura(integer, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_actualizar_factura(p_id_factura integer, p_numero_factura text, p_fecha_recepcion date) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE factura_recepcion
SET numero_factura = p_numero_factura,
    fecha_recepcion = p_fecha_recepcion
WHERE id_factura_recepcion = p_id_factura
$$;


--
-- Name: recep_anotar_entrega(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_anotar_entrega(p_id integer, p_datos text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE factura_recepcion SET entregas=entregas || CAST(p_datos AS jsonb) WHERE id_factura_recepcion=p_id
$$;


--
-- Name: recep_bloquear_factura(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_bloquear_factura(p_id_factura integer, p_id_local_actual integer) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT fr.id_factura_recepcion
FROM factura_recepcion fr
JOIN orden_compra oc USING (id_orden_compra)
WHERE fr.id_factura_recepcion = p_id_factura AND oc.id_local = p_id_local_actual
FOR UPDATE OF fr
$$;


--
-- Name: recep_bloquear_orden(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_bloquear_orden(p_id_orden integer, p_id_local_actual integer) RETURNS TABLE(id_orden_compra integer, codigo text, estado_orden_compra text)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    id_orden_compra,
    codigo,
    estado_orden_compra
FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) orden_compra
WHERE id_orden_compra = p_id_orden
FOR UPDATE
$$;


--
-- Name: recep_crear_detalle(integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_crear_detalle(p_id_factura integer, p_id_producto integer, p_cantidad numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO factura_recepcion_detalle (
    id_factura_recepcion,
    id_producto,
    cantidad_recibida
) VALUES (
    p_id_factura,
    p_id_producto,
    p_cantidad
)
$$;


--
-- Name: recep_crear_factura(integer, integer, text, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_crear_factura(p_id_orden integer, p_id_proveedor integer, p_numero_factura text, p_fecha_recepcion date, p_id_usuario integer) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO factura_recepcion (
    id_orden_compra,
    id_proveedor,
    numero_factura,
    fecha_recepcion,
    usuario_recepcion
) VALUES (
    p_id_orden,
    p_id_proveedor,
    p_numero_factura,
    p_fecha_recepcion,
    p_id_usuario
)
RETURNING id_factura_recepcion
$$;


--
-- Name: recep_crear_historial(integer, text, text, date, date, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_crear_historial(p_id_factura integer, p_numero_anterior text, p_numero_nuevo text, p_fecha_anterior date, p_fecha_nueva date, p_id_usuario integer, p_motivo text, p_observacion text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO factura_recepcion_historial (
    id_factura_recepcion,
    numero_factura_anterior,
    numero_factura_nuevo,
    fecha_recepcion_anterior,
    fecha_recepcion_nueva,
    usuario_correccion,
    motivo_correccion,
    observacion
) VALUES (
    p_id_factura,
    p_numero_anterior,
    p_numero_nuevo,
    p_fecha_anterior,
    p_fecha_nueva,
    p_id_usuario,
    p_motivo,
    p_observacion
)
RETURNING id_factura_recepcion_historial
$$;


--
-- Name: recep_crear_historial_detalle(integer, integer, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_crear_historial_detalle(p_id_historial integer, p_id_producto integer, p_cantidad_anterior numeric, p_cantidad_nueva numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO factura_recepcion_detalle_historial (
    id_factura_recepcion_historial,
    id_producto,
    cantidad_anterior,
    cantidad_nueva
) VALUES (
    p_id_historial,
    p_id_producto,
    p_cantidad_anterior,
    p_cantidad_nueva
)
$$;


--
-- Name: recep_datos_factura(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_datos_factura(p_id integer) RETURNS TABLE(datos_factura jsonb, entregas jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT datos_factura, entregas FROM factura_recepcion WHERE id_factura_recepcion=p_id
$$;


--
-- Name: recep_detalles_factura(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_detalles_factura(p_id_factura integer, p_id_local_actual integer) RETURNS TABLE(id_factura_recepcion_detalle integer, id_producto integer, codigo text, nombre text, unidad text, cantidad_recibida numeric, cantidad_solicitada numeric, recibido_otras_facturas numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    frd.id_factura_recepcion_detalle,
    frd.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    frd.cantidad_recibida,
    ocd.cantidad_solicitada,
    COALESCE((
        SELECT SUM(otra.cantidad_recibida)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) otra_fr
        JOIN factura_recepcion_detalle otra
            ON otra.id_factura_recepcion =
               otra_fr.id_factura_recepcion
        WHERE otra_fr.id_orden_compra = fr.id_orden_compra
          AND otra.id_producto = frd.id_producto
          AND otra_fr.id_factura_recepcion <>
              fr.id_factura_recepcion
    ), 0) AS recibido_otras_facturas
FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
JOIN factura_recepcion_detalle frd
    ON frd.id_factura_recepcion = fr.id_factura_recepcion
JOIN producto p
    ON p.id_producto = frd.id_producto
JOIN orden_compra_detalle ocd
    ON ocd.id_orden_compra = fr.id_orden_compra
   AND ocd.id_producto = frd.id_producto
WHERE fr.id_factura_recepcion = p_id_factura
ORDER BY p.nombre
$$;


--
-- Name: recep_factura_duplicada(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_factura_duplicada(p_id_proveedor integer, p_numero_factura text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM factura_recepcion
    WHERE id_proveedor = p_id_proveedor
      AND UPPER(numero_factura) = UPPER(p_numero_factura)
)
$$;


--
-- Name: recep_factura_duplicada_excepto(integer, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_factura_duplicada_excepto(p_id_proveedor integer, p_numero_factura text, p_id_factura integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM factura_recepcion
    WHERE id_proveedor = p_id_proveedor
      AND UPPER(numero_factura) = UPPER(p_numero_factura)
      AND id_factura_recepcion <> p_id_factura
)
$$;


--
-- Name: recep_facturacion_pendiente(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_facturacion_pendiente(p_orden integer, p_proveedor integer, p_producto integer, p_id_local_actual integer) RETURNS TABLE(nombre text, codigo text, unidad text, cantidad_solicitada numeric, facturado numeric)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.nombre, p.codigo, p.unidad, d.cantidad_solicitada,
  COALESCE((SELECT SUM(CASE WHEN f.datos_factura IS NULL THEN
    COALESCE((SELECT SUM(r.cantidad_recibida) FROM factura_recepcion_detalle r
      WHERE r.id_factura_recepcion=f.id_factura_recepcion AND r.id_producto=d.id_producto),0)
    ELSE COALESCE((SELECT SUM((j->>'cantidad_facturada')::numeric)
      FROM jsonb_array_elements(f.datos_factura->'lineas') j
      WHERE (j->>'id_producto')::int=d.id_producto),0) END)
    FROM factura_recepcion f WHERE f.id_orden_compra=d.id_orden_compra AND f.id_proveedor=p_proveedor),0) AS facturado
FROM orden_compra_detalle d JOIN orden_compra o USING(id_orden_compra)
JOIN producto p USING(id_producto)
WHERE d.id_orden_compra=p_orden AND d.id_proveedor=p_proveedor
  AND d.id_producto=p_producto AND o.id_local=p_id_local_actual
FOR UPDATE OF d
$$;


--
-- Name: recep_guardar_datos(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_guardar_datos(p_id integer, p_datos text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE factura_recepcion SET datos_factura=CAST(p_datos AS jsonb) WHERE id_factura_recepcion=p_id
$$;


--
-- Name: recep_historial(integer, date, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_historial(p_id_local_actual integer, p_fecha_desde date, p_fecha_hasta date, p_id_proveedor integer) RETURNS TABLE(id_factura_recepcion integer, id_orden_compra integer, codigo_orden text, estado_orden_compra text, total_factura text, moneda text, numero_factura text, fecha_recepcion date, id_proveedor integer, proveedor text, recibido_por text, productos_recibidos bigint, cantidad_total numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    fr.id_factura_recepcion,
    fr.id_orden_compra,
    oc.codigo AS codigo_orden,
    oc.estado_orden_compra,
    fr.datos_factura->>'total' AS total_factura,
    fr.datos_factura->>'moneda' AS moneda,
    fr.numero_factura,
    fr.fecha_recepcion,
    fr.id_proveedor,
    pr.nombre AS proveedor,
    CONCAT_WS(
        ' ',
        u.nombres,
        u.apellido_paterno,
        u.apellido_materno
    ) AS recibido_por,
    COUNT(frd.id_factura_recepcion_detalle)
        AS productos_recibidos,
    COALESCE(SUM(frd.cantidad_recibida), 0)
        AS cantidad_total
FROM factura_recepcion fr
JOIN orden_compra oc
    ON oc.id_orden_compra = fr.id_orden_compra
JOIN proveedor pr
    ON pr.id_proveedor = fr.id_proveedor
JOIN usuario u
    ON u.id_usuario = fr.usuario_recepcion
JOIN factura_recepcion_detalle frd
    ON frd.id_factura_recepcion = fr.id_factura_recepcion
WHERE oc.id_local=p_id_local_actual AND (
    CAST(p_fecha_desde AS DATE) IS NULL
    OR fr.fecha_recepcion >= CAST(p_fecha_desde AS DATE)
)
  AND (
    CAST(p_fecha_hasta AS DATE) IS NULL
    OR fr.fecha_recepcion <= CAST(p_fecha_hasta AS DATE)
  )
  AND (
    CAST(p_id_proveedor AS INTEGER) IS NULL
    OR fr.id_proveedor = CAST(p_id_proveedor AS INTEGER)
  )
GROUP BY
    fr.id_factura_recepcion,
    oc.id_orden_compra,
    pr.id_proveedor,
    u.id_usuario
ORDER BY
    fr.fecha_recepcion DESC,
    fr.id_factura_recepcion DESC
$$;


--
-- Name: recep_obtener_factura(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_obtener_factura(p_id_factura integer, p_id_local_actual integer) RETURNS TABLE(id_factura_recepcion integer, id_orden_compra integer, codigo_orden text, estado_orden_compra text, id_proveedor integer, proveedor text, numero_factura text, fecha_recepcion date, recibido_por text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    fr.id_factura_recepcion,
    fr.id_orden_compra,
    oc.codigo AS codigo_orden,
    oc.estado_orden_compra,
    fr.id_proveedor,
    pr.nombre AS proveedor,
    fr.numero_factura,
    fr.fecha_recepcion,
    CONCAT_WS(
        ' ',
        u.nombres,
        u.apellido_paterno,
        u.apellido_materno
    ) AS recibido_por
FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
JOIN (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
    ON oc.id_orden_compra = fr.id_orden_compra
JOIN proveedor pr
    ON pr.id_proveedor = fr.id_proveedor
JOIN usuario u
    ON u.id_usuario = fr.usuario_recepcion
WHERE fr.id_factura_recepcion = p_id_factura
$$;


--
-- Name: recep_orden_de_factura(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_orden_de_factura(p_id integer) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_orden_compra FROM factura_recepcion WHERE id_factura_recepcion=p_id
$$;


--
-- Name: recep_orden_pendiente(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_orden_pendiente(p_id_orden integer, p_id_local_actual integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM orden_compra_detalle ocd
    JOIN producto p
        ON p.id_producto = ocd.id_producto
    WHERE ocd.id_orden_compra = p_id_orden
      AND ocd.cantidad_solicitada > COALESCE((
          SELECT SUM(frd.cantidad_recibida)
          FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
          JOIN factura_recepcion_detalle frd
              ON frd.id_factura_recepcion = fr.id_factura_recepcion
          WHERE fr.id_orden_compra = ocd.id_orden_compra
            AND fr.id_proveedor = ocd.id_proveedor
            AND frd.id_producto = ocd.id_producto
      ), 0)
)
$$;


--
-- Name: recep_pendientes(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_pendientes(p_id_local_actual integer) RETURNS TABLE(id_orden_compra integer, codigo_orden text, estado_orden_compra text, fecha_registro date, id_proveedor integer, proveedor text, datos_comerciales jsonb, id_producto integer, codigo_producto text, producto text, categoria text, unidad text, presentacion numeric, cantidad_solicitada numeric, cantidad_recibida numeric, cantidad_pendiente numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH recibido AS (
    SELECT
        fr.id_orden_compra,
        fr.id_proveedor,
        frd.id_producto,
        SUM(frd.cantidad_recibida) AS cantidad_recibida
    FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
    JOIN factura_recepcion_detalle frd
        ON frd.id_factura_recepcion = fr.id_factura_recepcion
    GROUP BY
        fr.id_orden_compra,
        fr.id_proveedor,
        frd.id_producto
)
SELECT
    oc.id_orden_compra,
    oc.codigo AS codigo_orden,
    oc.estado_orden_compra,
    oc.fecha_registro,
    pr.id_proveedor,
    pr.nombre AS proveedor,
    pr.datos_comerciales,
    p.id_producto,
    p.codigo AS codigo_producto,
    p.nombre AS producto,
    cp.nombre AS categoria,
    p.unidad,
    p.presentacion,
    ocd.cantidad_solicitada,
    COALESCE(r.cantidad_recibida, 0) AS cantidad_recibida,
    GREATEST(
        ocd.cantidad_solicitada
        - COALESCE(r.cantidad_recibida, 0),
        0
    ) AS cantidad_pendiente
FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
JOIN orden_compra_detalle ocd
    ON ocd.id_orden_compra = oc.id_orden_compra
JOIN producto p
    ON p.id_producto = ocd.id_producto
JOIN categoria_producto cp
    ON cp.id_categoria = p.id_categoria
JOIN proveedor pr
    ON pr.id_proveedor = ocd.id_proveedor
LEFT JOIN recibido r
    ON r.id_orden_compra = oc.id_orden_compra
   AND r.id_proveedor = pr.id_proveedor
   AND r.id_producto = p.id_producto
WHERE oc.estado_orden_compra IN (
    'ENVIADA',
    'RECEPCION_PARCIAL'
)
  AND ocd.cantidad_solicitada
      > COALESCE(r.cantidad_recibida, 0)
ORDER BY
    oc.fecha_registro,
    oc.codigo,
    pr.nombre,
    p.nombre
$$;


--
-- Name: recep_producto_pendiente(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_producto_pendiente(p_id_orden integer, p_id_proveedor integer, p_id_producto integer, p_id_local_actual integer) RETURNS TABLE(id_producto integer, codigo text, nombre text, unidad text, cantidad_solicitada numeric, cantidad_recibida numeric)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    p.id_producto,
    p.codigo,
    p.nombre,
    p.unidad,
    ocd.cantidad_solicitada,
    COALESCE((
        SELECT SUM(frd.cantidad_recibida)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion = fr.id_factura_recepcion
        WHERE fr.id_orden_compra = oc.id_orden_compra
          AND fr.id_proveedor = p_id_proveedor
          AND frd.id_producto = p.id_producto
    ), 0) AS cantidad_recibida
FROM (SELECT * FROM orden_compra WHERE id_local=p_id_local_actual) oc
JOIN orden_compra_detalle ocd
    ON ocd.id_orden_compra = oc.id_orden_compra
JOIN producto p
    ON p.id_producto = ocd.id_producto
WHERE oc.id_orden_compra = p_id_orden
  AND p.id_producto = p_id_producto
  AND ocd.id_proveedor = p_id_proveedor
FOR UPDATE OF ocd
$$;


--
-- Name: recep_proveedor(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_proveedor(p_id integer) RETURNS TABLE(nombre text, datos_comerciales jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT nombre, datos_comerciales FROM proveedor WHERE id_proveedor=p_id
$$;


--
-- Name: recep_totales_orden(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recep_totales_orden(p_id_orden integer, p_id_local_actual integer) RETURNS TABLE(total_solicitado numeric, total_recibido numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    COALESCE((
        SELECT SUM(cantidad_solicitada)
        FROM orden_compra_detalle
        WHERE id_orden_compra = p_id_orden
    ), 0) AS total_solicitado,
    COALESCE((
        SELECT SUM(frd.cantidad_recibida)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=p_id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion =
               fr.id_factura_recepcion
        WHERE fr.id_orden_compra = p_id_orden
    ), 0) AS total_recibido
$$;


--
-- Name: receta_actualizar(text, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_actualizar(p_instrucciones text, p_activo boolean, p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE receta SET instrucciones=p_instrucciones,activo=p_activo WHERE id_receta=p_id
$$;


--
-- Name: receta_bloquear_producto(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_bloquear_producto(p_id integer) RETURNS TABLE(id integer, codigo text, nombre text, unidad text, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_producto AS id, codigo, nombre, unidad, activo FROM producto WHERE id_producto=p_id FOR SHARE
$$;


--
-- Name: receta_bloquear_subproducto(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_bloquear_subproducto(p_id integer) RETURNS TABLE(id integer, codigo text, nombre text, unidad text, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_subproducto AS id, codigo, nombre, unidad, activo FROM subproducto WHERE id_subproducto=p_id FOR SHARE
$$;


--
-- Name: receta_buscar_bloqueada(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_buscar_bloqueada(p_id integer) RETURNS TABLE(id_receta integer, id_presentacion_venta integer, instrucciones text, activo boolean, id_item_carta integer, contenido numeric, unidad text, id_menaje integer, tipo text, nombre text, id_categoria_carta integer)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT r.id_receta, r.id_presentacion_venta, r.instrucciones, r.activo, pv.id_item_carta, pv.contenido, pv.unidad, pv.id_menaje,
       ic.tipo, ic.nombre, ic.id_categoria_carta
FROM receta r JOIN presentacion_venta pv USING(id_presentacion_venta)
JOIN item_carta ic USING(id_item_carta)
WHERE r.id_receta = p_id FOR UPDATE OF r, pv, ic
$$;


--
-- Name: receta_categorias(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_categorias() RETURNS TABLE(id_categoria_carta integer, nombre text, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_categoria_carta, nombre, activo FROM categoria_carta ORDER BY nombre
$$;


--
-- Name: receta_crear(integer, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_crear(p_presentacion integer, p_instrucciones text, p_activo boolean) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO receta(id_presentacion_venta,instrucciones,activo)
VALUES (p_presentacion,p_instrucciones,p_activo) RETURNING id_receta
$$;


--
-- Name: receta_crear_detalle(integer, text, integer, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_crear_detalle(p_receta integer, p_tipo text, p_producto integer, p_subproducto integer, p_cantidad numeric, p_unidad text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO receta_detalle (id_receta, tipo_componente, id_producto, id_subproducto, cantidad, unidad)
VALUES (p_receta, p_tipo, p_producto, p_subproducto, p_cantidad, p_unidad)
$$;


--
-- Name: receta_definicion_check(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_definicion_check(p_nombre text) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conname = p_nombre AND connamespace = 'public'::regnamespace
$$;


--
-- Name: receta_desactivar_grupo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_desactivar_grupo(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE grupo_salsa SET activo=FALSE WHERE id_presentacion_venta=p_id
$$;


--
-- Name: receta_desactivar_opciones(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_desactivar_opciones(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE grupo_salsa_opcion SET activo=FALSE WHERE id_grupo_salsa=p_id
$$;


--
-- Name: receta_detalles(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_detalles(p_id integer) RETURNS TABLE(id_receta_detalle integer, id_receta integer, tipo_componente text, id_producto integer, id_subproducto integer, cantidad numeric, unidad text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_receta_detalle, id_receta, tipo_componente, id_producto, id_subproducto, cantidad, unidad FROM receta_detalle WHERE id_receta=p_id ORDER BY id_receta_detalle
$$;


--
-- Name: receta_eliminar_detalles(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_eliminar_detalles(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM receta_detalle WHERE id_receta=p_id
$$;


--
-- Name: receta_grupo_bloqueado(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_grupo_bloqueado(p_id integer) RETURNS TABLE(id_grupo_salsa integer, id_presentacion_venta integer, cantidad_maxima smallint, permite_repetir boolean, activo boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_grupo_salsa, id_presentacion_venta, cantidad_maxima, permite_repetir, activo FROM grupo_salsa WHERE id_presentacion_venta=p_id FOR UPDATE
$$;


--
-- Name: receta_guardar_grupo(integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_guardar_grupo(p_id integer, p_maximo integer, p_repetir boolean) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO grupo_salsa (id_presentacion_venta, cantidad_maxima, permite_repetir, activo)
VALUES (p_id, p_maximo, p_repetir, TRUE)
ON CONFLICT (id_presentacion_venta) DO UPDATE
SET cantidad_maxima=EXCLUDED.cantidad_maxima, permite_repetir=EXCLUDED.permite_repetir, activo=TRUE
RETURNING id_grupo_salsa
$$;


--
-- Name: receta_guardar_opcion(integer, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_guardar_opcion(p_grupo integer, p_producto integer, p_cantidad numeric, p_unidad text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO grupo_salsa_opcion (id_grupo_salsa,id_producto,cantidad,unidad,activo)
VALUES (p_grupo,p_producto,p_cantidad,p_unidad,TRUE)
ON CONFLICT (id_grupo_salsa,id_producto) DO UPDATE
SET cantidad=EXCLUDED.cantidad, unidad=EXCLUDED.unidad, activo=TRUE
$$;


--
-- Name: receta_items(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_items() RETURNS TABLE(id_item_carta integer, codigo text, nombre text, id_categoria_carta integer, tipo text, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_item_carta, codigo, nombre, id_categoria_carta, tipo, activo FROM item_carta ORDER BY nombre
$$;


--
-- Name: receta_listar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_listar() RETURNS TABLE(id_receta integer, id_presentacion_venta integer, instrucciones text, activo boolean, id_item_carta integer, codigo_item text, item_carta text, tipo_item text, id_categoria_carta integer, categoria_carta text, contenido numeric, unidad_presentacion text, precio numeric, id_menaje integer, total_componentes bigint, componentes jsonb, id_grupo_salsa integer, cantidad_maxima smallint, permite_repetir boolean, grupo_salsa_activo boolean, opciones_salsa jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    r.id_receta,
    r.id_presentacion_venta,
    r.instrucciones,
    r.activo,

    ic.id_item_carta,
    ic.codigo AS codigo_item,
    ic.nombre AS item_carta,
    ic.tipo AS tipo_item,
    ic.id_categoria_carta,
    cc.nombre AS categoria_carta,

    pv.contenido,
    pv.unidad AS unidad_presentacion,
    pv.precio,
    pv.id_menaje,

    (
        SELECT COUNT(*)
        FROM receta_detalle rd_conteo
        WHERE rd_conteo.id_receta = r.id_receta
    ) AS total_componentes,

    COALESCE(
        (
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_receta_detalle', rd.id_receta_detalle,
                    'tipo_componente', rd.tipo_componente,
                    'id_producto', rd.id_producto,
                    'producto_codigo', p.codigo,
                    'producto_nombre', p.nombre,
                    'id_subproducto', rd.id_subproducto,
                    'subproducto_codigo', sp.codigo,
                    'subproducto_nombre', sp.nombre,
                    'cantidad', rd.cantidad,
                    'unidad', rd.unidad
                )
                ORDER BY
                    rd.tipo_componente,
                    COALESCE(p.nombre, sp.nombre)
            )
            FROM receta_detalle rd
            LEFT JOIN producto p
                ON p.id_producto = rd.id_producto
            LEFT JOIN subproducto sp
                ON sp.id_subproducto = rd.id_subproducto
            WHERE rd.id_receta = r.id_receta
        ),
        '[]'::JSONB
    ) AS componentes,

    gs.id_grupo_salsa,
    gs.cantidad_maxima,
    gs.permite_repetir,
    gs.activo AS grupo_salsa_activo,

    COALESCE(
        (
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_grupo_salsa_opcion', gso.id_grupo_salsa_opcion,
                    'id_producto', producto_salsa.id_producto,
                    'codigo', producto_salsa.codigo,
                    'nombre', producto_salsa.nombre,
                    'cantidad', gso.cantidad,
                    'unidad', gso.unidad,
                    'activo', gso.activo
                )
                ORDER BY producto_salsa.nombre
            )
            FROM grupo_salsa_opcion gso
            INNER JOIN producto producto_salsa
                ON producto_salsa.id_producto = gso.id_producto
            WHERE gso.id_grupo_salsa = gs.id_grupo_salsa
              AND gso.activo = TRUE
        ),
        '[]'::JSONB
    ) AS opciones_salsa

FROM receta r

INNER JOIN presentacion_venta pv
    ON pv.id_presentacion_venta = r.id_presentacion_venta

INNER JOIN item_carta ic
    ON ic.id_item_carta = pv.id_item_carta

INNER JOIN categoria_carta cc
    ON cc.id_categoria_carta = ic.id_categoria_carta

LEFT JOIN grupo_salsa gs
    ON gs.id_presentacion_venta = pv.id_presentacion_venta
   AND gs.activo = TRUE

ORDER BY ic.nombre, pv.contenido
$$;


--
-- Name: receta_opciones_grupo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_opciones_grupo(p_id integer) RETURNS TABLE(id_grupo_salsa_opcion integer, id_grupo_salsa integer, id_producto integer, cantidad numeric, unidad text, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_grupo_salsa_opcion, id_grupo_salsa, id_producto, cantidad, unidad, activo FROM grupo_salsa_opcion WHERE id_grupo_salsa=p_id ORDER BY id_producto
$$;


--
-- Name: receta_presentacion_bloqueada(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_presentacion_bloqueada(p_id integer) RETURNS TABLE(id_presentacion_venta integer, id_item_carta integer, id_menaje integer, contenido numeric, unidad text, precio numeric, activo boolean, tipo text)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pv.id_presentacion_venta, pv.id_item_carta, pv.id_menaje, pv.contenido, pv.unidad, pv.precio, pv.activo, ic.tipo FROM presentacion_venta pv
JOIN item_carta ic USING(id_item_carta)
WHERE pv.id_presentacion_venta=p_id FOR UPDATE OF ic, pv
$$;


--
-- Name: receta_presentacion_ocupada(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_presentacion_ocupada(p_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS(SELECT 1 FROM receta WHERE id_presentacion_venta=p_id)
$$;


--
-- Name: receta_presentaciones_disponibles(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_presentaciones_disponibles() RETURNS TABLE(id_presentacion_venta integer, id_item_carta integer, id_menaje integer, contenido numeric, unidad text, activo boolean, id_receta integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pv.id_presentacion_venta, pv.id_item_carta, pv.id_menaje,
       pv.contenido, pv.unidad, pv.activo, r.id_receta
FROM presentacion_venta pv LEFT JOIN receta r USING (id_presentacion_venta)
WHERE r.id_receta IS NULL
ORDER BY pv.id_item_carta, pv.contenido
$$;


--
-- Name: receta_subproductos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receta_subproductos() RETURNS TABLE(id integer, codigo text, nombre text, unidad text, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_subproducto AS id, codigo, nombre, unidad, activo FROM subproducto ORDER BY nombre
$$;


--
-- Name: registro_de_local(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registro_de_local(p_tipo text, p_identidad integer, p_local integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
    SELECT CASE p_tipo
        WHEN 'inventario' THEN EXISTS (SELECT 1 FROM inventario_cierre
            WHERE id_inventario_cierre=p_identidad AND id_local=p_local)
        WHEN 'orden' THEN EXISTS (SELECT 1 FROM orden_compra
            WHERE id_orden_compra=p_identidad AND id_local=p_local)
        WHEN 'movimiento' THEN EXISTS (SELECT 1 FROM movimiento_inventario
            WHERE id_movimiento_inventario=p_identidad AND id_local=p_local)
        WHEN 'factura' THEN EXISTS (SELECT 1 FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
            WHERE f.id_factura_recepcion=p_identidad AND o.id_local=p_local)
        WHEN 'detalle_recepcion' THEN EXISTS (SELECT 1 FROM factura_recepcion_detalle d JOIN factura_recepcion f USING(id_factura_recepcion) JOIN orden_compra o USING(id_orden_compra)
            WHERE d.id_factura_recepcion_detalle=p_identidad AND o.id_local=p_local)
        WHEN 'correccion' THEN EXISTS (SELECT 1 FROM inventario_cierre_correccion c JOIN inventario_cierre i USING(id_inventario_cierre)
            WHERE c.id_inventario_cierre_correccion=p_identidad AND i.id_local=p_local)
        WHEN 'historial_factura' THEN EXISTS (SELECT 1 FROM factura_recepcion_historial h JOIN factura_recepcion f USING(id_factura_recepcion) JOIN orden_compra o USING(id_orden_compra)
            WHERE h.id_factura_recepcion_historial=p_identidad AND o.id_local=p_local)
        ELSE false
    END
$$;


--
-- Name: salon_actualizar_cliente(text, text, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_actualizar_cliente(p_tipo text, p_doc text, p_cliente text, p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE salon_cobro SET tipo=p_tipo,documento=p_doc,cliente=p_cliente,id_cliente=NULL WHERE id_cobro=p_id
$$;


--
-- Name: salon_anular_linea(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_anular_linea(p_id bigint, p_usuario bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_linea_anulada(id_linea,id_responsable) VALUES(p_id,p_usuario)
$$;


--
-- Name: salon_asignar_pedido(bigint, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_asignar_pedido(p_id bigint, p_mesa text, p_usuario bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_pedido_asignacion(id_pedido,mesa,id_usuario) VALUES(p_id,p_mesa,p_usuario) ON CONFLICT(id_pedido) DO UPDATE SET mesa=excluded.mesa,id_usuario=excluded.id_usuario
$$;


--
-- Name: salon_bloquear_catalogo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_bloquear_catalogo() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
LOCK TABLE presentacion_venta,item_carta,categoria_carta,grupo_salsa,grupo_salsa_opcion,producto,promocion,promocion_grupo,promocion_opcion,promocion_reposicion IN SHARE MODE
$$;


--
-- Name: salon_bloquear_codigo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_bloquear_codigo() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock(hashtext('movimiento_inventario_codigo'))
$$;


--
-- Name: salon_bloquear_pin(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_bloquear_pin(p_id bigint) RETURNS TABLE(id_usuario integer, pin_hash text, version integer, fallos integer, bloqueado_hasta timestamp with time zone, actualizado_en timestamp with time zone, bloqueado boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT *,bloqueado_hasta>clock_timestamp() AS bloqueado FROM usuario_pin_salon WHERE id_usuario=p_id FOR UPDATE
$$;


--
-- Name: salon_bloquear_recetas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_bloquear_recetas() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
LOCK TABLE receta,receta_detalle,subproducto,subproducto_detalle,producto,grupo_salsa,grupo_salsa_opcion IN SHARE MODE
$$;


--
-- Name: salon_bloqueo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_bloqueo(p_clave text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock(hashtext(p_clave))
$$;


--
-- Name: salon_bloqueo_compartido(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_bloqueo_compartido(p_clave text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pg_advisory_xact_lock_shared(hashtext(p_clave))
$$;


--
-- Name: salon_cambio_bloqueado(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_cambio_bloqueado(p_id bigint, p_local bigint) RETURNS TABLE(id_cobro bigint, id_local integer, id_usuario integer, mesa character varying, clave uuid, solicitud_hash character varying, tipo character varying, metodo character varying, documento character varying, cliente character varying, total numeric, comprobante jsonb, id_movimiento integer, creado_en timestamp with time zone, id_jornada bigint, id_cliente uuid, jornada_fecha date, cerrado_en timestamp with time zone, hoy date, fecha_venta date)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT c.*,j.fecha AS jornada_fecha,j.cerrado_en,
            (clock_timestamp() AT TIME ZONE 'America/Lima')::date AS hoy,
            (c.creado_en AT TIME ZONE 'America/Lima')::date AS fecha_venta
            FROM salon_cobro c LEFT JOIN inventario_jornada j USING(id_jornada)
            WHERE c.id_cobro=p_id AND c.id_local=p_local FOR UPDATE OF c
$$;


--
-- Name: salon_catalogo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_catalogo() RETURNS TABLE(id integer, nombre character varying, contenido numeric, unidad character varying, precio numeric, id_categoria integer, categoria character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pv.id_presentacion_venta AS id,ic.nombre,pv.contenido,pv.unidad,pv.precio,
  cc.id_categoria_carta AS id_categoria,cc.nombre AS categoria
FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
JOIN categoria_carta cc USING(id_categoria_carta)
WHERE pv.activo AND ic.activo AND cc.activo ORDER BY cc.nombre,ic.nombre,pv.contenido
$$;


--
-- Name: salon_cierres_diarios(bigint, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_cierres_diarios(p_local bigint, p_desde date, p_fin date) RETURNS TABLE(fecha date, simulacion boolean, cantidad integer, efectivo numeric, tarjeta numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT fecha, simulacion, cantidad, efectivo, tarjeta
FROM public.salon_cierre_diario
WHERE id_local = p_local AND fecha >= p_desde AND fecha < p_fin
ORDER BY fecha DESC
$$;


--
-- Name: salon_cierres_instalados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_cierres_instalados() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_cierre_diario') IS NOT NULL
$$;


--
-- Name: salon_cliente_cobro(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_cliente_cobro(p_cliente text, p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE salon_cobro SET id_cliente=CAST(p_cliente AS uuid) WHERE id_cobro=p_id
$$;


--
-- Name: salon_cobro_previo(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_cobro_previo(p_local bigint, p_clave text) RETURNS TABLE(id_cobro bigint, id_local integer, id_usuario integer, mesa character varying, clave uuid, solicitud_hash character varying, tipo character varying, metodo character varying, documento character varying, cliente character varying, total numeric, comprobante jsonb, id_movimiento integer, creado_en timestamp with time zone, id_cliente uuid)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_cobro, id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento, cliente, total, comprobante, id_movimiento, creado_en, id_cliente FROM salon_cobro WHERE id_local=p_local AND clave=CAST(p_clave AS uuid)
$$;


--
-- Name: salon_cobros_instalados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_cobros_instalados() RETURNS regclass
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_cobro')
$$;


--
-- Name: salon_comprobante(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_comprobante(p_id bigint, p_local bigint) RETURNS TABLE(id_cobro bigint, id_local integer, id_usuario integer, mesa character varying, clave uuid, solicitud_hash character varying, tipo character varying, metodo character varying, documento character varying, cliente character varying, total numeric, comprobante jsonb, id_movimiento integer, creado_en timestamp with time zone, id_cliente uuid)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_cobro, id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento, cliente, total, comprobante, id_movimiento, creado_en, id_cliente FROM salon_cobro WHERE id_cobro=p_id AND id_local=p_local
$$;


--
-- Name: salon_comprobante_editable(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_comprobante_editable(p_id bigint) RETURNS TABLE(editable boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT j.cerrado_en IS NULL AND j.fecha=(clock_timestamp() AT TIME ZONE 'America/Lima')::date AND (c.creado_en AT TIME ZONE 'America/Lima')::date=j.fecha AS editable FROM salon_cobro c LEFT JOIN inventario_jornada j USING(id_jornada) WHERE c.id_cobro=p_id
$$;


--
-- Name: salon_consumir_autorizacion(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_consumir_autorizacion(p_id text) RETURNS uuid
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_autorizacion_usada(clave) VALUES(CAST(p_id AS uuid)) ON CONFLICT DO NOTHING RETURNING clave
$$;


--
-- Name: salon_control_instalado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_control_instalado() RETURNS regclass
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_pedido_actual')
$$;


--
-- Name: salon_crear_cobro(bigint, bigint, text, text, text, text, text, text, text, numeric, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_crear_cobro(p_local bigint, p_usuario bigint, p_mesa text, p_clave text, p_hash text, p_tipo text, p_metodo text, p_documento text, p_cliente text, p_total numeric, p_snapshot text, p_movimiento bigint) RETURNS TABLE(id_cobro bigint, id_local integer, id_usuario integer, mesa character varying, clave uuid, solicitud_hash character varying, tipo character varying, metodo character varying, documento character varying, cliente character varying, total numeric, comprobante jsonb, id_movimiento integer, creado_en timestamp with time zone, id_cliente uuid)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_cobro
            (id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,documento,cliente,total,comprobante,id_movimiento)
            VALUES(p_local,p_usuario,p_mesa,CAST(p_clave AS uuid),p_hash,p_tipo,p_metodo,p_documento,p_cliente,p_total,CAST(p_snapshot AS jsonb),p_movimiento)
            RETURNING id_cobro, id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento, cliente, total, comprobante, id_movimiento, creado_en, id_cliente
$$;


--
-- Name: salon_crear_linea(bigint, bigint, bigint, bigint, text, bigint, text, numeric, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_crear_linea(p_pedido bigint, p_posicion bigint, p_id_presentacion bigint, p_id_promocion bigint, p_selecciones_promocion text, p_id_barra_libre bigint, p_nombre text, p_precio numeric, p_cantidad numeric, p_comentario text, p_opciones text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_pedido_linea(id_pedido,posicion,id_presentacion,id_promocion,
                            selecciones_promocion,id_barra_libre,nombre,precio,cantidad,comentario,opciones)
                            VALUES(p_pedido,p_posicion,p_id_presentacion,p_id_promocion,CAST(p_selecciones_promocion AS jsonb),
                            p_id_barra_libre,p_nombre,p_precio,p_cantidad,p_comentario,CAST(p_opciones AS jsonb))
$$;


--
-- Name: salon_crear_movimiento(text, bigint, bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_crear_movimiento(p_codigo text, p_usuario bigint, p_local bigint, p_observacion text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO movimiento_inventario
            (codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local,observacion)
            VALUES(p_codigo,'SALIDA','VENTA_SALON',(clock_timestamp() AT TIME ZONE 'America/Lima')::date,p_usuario,p_local,p_observacion)
            RETURNING id_movimiento_inventario
$$;


--
-- Name: salon_crear_pedido(bigint, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_crear_pedido(p_local bigint, p_mesa text, p_usuario bigint) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_pedido(id_local,mesa,id_usuario)
              VALUES(p_local,p_mesa,p_usuario) RETURNING id_pedido
$$;


--
-- Name: salon_detalle_movimiento(bigint, bigint, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_detalle_movimiento(p_movimiento bigint, p_producto bigint, p_cantidad numeric) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO movimiento_inventario_detalle
                (id_movimiento_inventario,id_producto,cantidad) VALUES(p_movimiento,p_producto,p_cantidad)
$$;


--
-- Name: salon_detalles_receta(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_detalles_receta(p_id bigint) RETURNS TABLE(id_receta_detalle integer, id_receta integer, tipo_componente character varying, id_producto integer, id_subproducto integer, cantidad numeric, unidad character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM receta_detalle WHERE id_receta=p_id
$$;


--
-- Name: salon_diario(bigint, timestamp with time zone, timestamp with time zone, text, text, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_diario(p_local bigint, p_inicio timestamp with time zone, p_fin timestamp with time zone, p_tipo text, p_metodo text, p_codigo text, p_offset bigint) RETURNS TABLE(cantidad bigint, total numeric, efectivo numeric, tarjeta numeric, ventas jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH filtradas AS (
        SELECT id_cobro,creado_en,mesa,tipo,metodo,total,comprobante->'anulacion' AS anulacion,
            comprobante->>'usuario' AS usuario, comprobante ? 'prueba' AS simulacion
        FROM salon_cobro WHERE id_local = p_local AND creado_en >= p_inicio AND creado_en < p_fin
            AND (nullif(p_tipo, '') IS NULL OR tipo = p_tipo)
            AND (nullif(p_metodo, '') IS NULL OR metodo = p_metodo)
            AND (nullif(p_codigo, '') IS NULL OR strpos('INT-' || lpad(id_cobro::text,8,'0'), upper(p_codigo)) > 0)
    ), pagina AS (SELECT * FROM filtradas ORDER BY creado_en DESC,id_cobro DESC LIMIT 20 OFFSET p_offset)
    SELECT (SELECT count(*) FROM filtradas) AS cantidad,
        (SELECT coalesce(sum(total) FILTER (WHERE anulacion IS NULL),0) FROM filtradas) AS total,
        (SELECT coalesce(sum(total) FILTER (WHERE metodo='EFECTIVO' AND anulacion IS NULL),0) FROM filtradas) AS efectivo,
        (SELECT coalesce(sum(total) FILTER (WHERE metodo='TARJETA' AND anulacion IS NULL),0) FROM filtradas) AS tarjeta,
        coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY creado_en DESC,id_cobro DESC) FROM pagina),'[]'::jsonb) AS ventas
$$;


--
-- Name: salon_distribucion(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_distribucion(p_local bigint) RETURNS TABLE(version integer, elementos jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT version,elementos FROM salon_distribucion WHERE id_local=p_local
$$;


--
-- Name: salon_distribucion_instalada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_distribucion_instalada() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_distribucion') IS NOT NULL
$$;


--
-- Name: salon_distribucion_predeterminada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_distribucion_predeterminada() RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT distribucion_salon FROM public.configuracion_operativa
$$;


--
-- Name: salon_elegible(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_elegible(p_id bigint) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT 1 FROM usuario u WHERE u.id_usuario=p_id AND public.salon_usuario_elegible(u.id_usuario)
$$;


--
-- Name: salon_eliminar_lineas(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_eliminar_lineas(p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM salon_pedido_linea WHERE id_pedido=p_id
$$;


--
-- Name: salon_eliminar_pedido(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_eliminar_pedido(p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM salon_pedido WHERE id_pedido=p_id
$$;


--
-- Name: salon_eliminar_pin(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_eliminar_pin(p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM usuario_pin_salon WHERE id_usuario=p_id
$$;


--
-- Name: salon_envio_previo(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_envio_previo(p_local bigint, p_clave text) RETURNS TABLE(envio_hash character varying, mesa character varying, vigente boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.envio_hash,coalesce(a.mesa,p.mesa) AS mesa,
                EXISTS(SELECT 1 FROM salon_pedido_actual actual WHERE actual.id_pedido=p.id_pedido) AS vigente
                FROM salon_pedido p LEFT JOIN salon_pedido_asignacion a USING(id_pedido)
                WHERE p.id_local=p_local AND p.envio_clave=CAST(p_clave AS uuid)
$$;


--
-- Name: salon_envios_instalados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_envios_instalados() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='salon_pedido' AND column_name='envio_clave')
$$;


--
-- Name: salon_fallo_pin(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_fallo_pin(p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE usuario_pin_salon SET bloqueado_hasta=CASE WHEN fallos>=4 THEN clock_timestamp()+interval '5 minutes' ELSE NULL END,
    fallos=CASE WHEN fallos>=4 THEN 0 ELSE fallos+1 END WHERE id_usuario=p_id
$$;


--
-- Name: salon_grupos_promocion(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_grupos_promocion(p_id bigint) RETURNS TABLE(id_promocion_grupo integer, cantidad_elegir smallint, permite_repetir boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_promocion_grupo,cantidad_elegir,permite_repetir
          FROM promocion_grupo WHERE id_promocion=p_id ORDER BY id_promocion_grupo
$$;


--
-- Name: salon_grupos_salsa(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_grupos_salsa() RETURNS TABLE(id_grupo_salsa integer, id_presentacion_venta integer, cantidad_maxima smallint, permite_repetir boolean, id integer, nombre character varying, cantidad numeric, unidad character varying, id_producto integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT gs.id_grupo_salsa,gs.id_presentacion_venta,
       gs.cantidad_maxima,gs.permite_repetir,gso.id_grupo_salsa_opcion AS id,
       p.nombre,gso.cantidad,p.unidad,gso.id_producto
       FROM grupo_salsa gs LEFT JOIN grupo_salsa_opcion gso ON gso.id_grupo_salsa=gs.id_grupo_salsa AND gso.activo
       LEFT JOIN producto p ON p.id_producto=gso.id_producto AND p.activo
       WHERE gs.activo ORDER BY gs.id_grupo_salsa,p.nombre
$$;


--
-- Name: salon_guardar_comprobante(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_guardar_comprobante(p_c text, p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE salon_cobro SET comprobante=CAST(p_c AS jsonb) WHERE id_cobro=p_id
$$;


--
-- Name: salon_guardar_distribucion(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_guardar_distribucion(p_local bigint, p_elementos text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_distribucion(id_local,version,elementos) VALUES(p_local,1,CAST(p_elementos AS jsonb)) ON CONFLICT(id_local) DO UPDATE SET version=salon_distribucion.version+1,elementos=excluded.elementos
$$;


--
-- Name: salon_guardar_pedido(bigint, text, boolean, text, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_guardar_pedido(p_version bigint, p_estado text, p_enviar boolean, p_envio_clave text, p_envio_hash text, p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE salon_pedido SET version=p_version,estado=p_estado,
            enviado_en=CASE WHEN p_enviar THEN clock_timestamp() ELSE NULL END,
            envio_clave=CAST(p_envio_clave AS uuid),envio_hash=p_envio_hash WHERE id_pedido=p_id
$$;


--
-- Name: salon_guardar_pin(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_guardar_pin(p_id bigint, p_hash text) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO usuario_pin_salon(id_usuario,pin_hash) VALUES(p_id,p_hash)
          ON CONFLICT(id_usuario) DO UPDATE SET pin_hash=EXCLUDED.pin_hash,
          version=usuario_pin_salon.version+1,fallos=0,bloqueado_hasta=NULL,actualizado_en=clock_timestamp()
$$;


--
-- Name: salon_incrementar_intentos(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_incrementar_intentos(p_origen text) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_intentos(origen,intentos) VALUES(p_origen,1)
      ON CONFLICT(origen) DO UPDATE SET
        intentos=CASE WHEN salon_intentos.inicio<clock_timestamp()-interval '5 minutes' THEN 1 ELSE salon_intentos.intentos+1 END,
        inicio=CASE WHEN salon_intentos.inicio<clock_timestamp()-interval '5 minutes' THEN clock_timestamp() ELSE salon_intentos.inicio END
      RETURNING intentos
$$;


--
-- Name: salon_ingredientes_subproducto(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_ingredientes_subproducto(p_id bigint) RETURNS TABLE(id_subproducto_detalle integer, id_subproducto integer, id_producto integer, cantidad numeric, unidad character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM subproducto_detalle WHERE id_subproducto=p_id
$$;


--
-- Name: salon_jornadas_instaladas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_jornadas_instaladas() RETURNS regclass
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.inventario_jornada')
$$;


--
-- Name: salon_limpiar_intentos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_limpiar_intentos() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DELETE FROM salon_intentos WHERE inicio<clock_timestamp()-interval '1 day'
$$;


--
-- Name: salon_lineas(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_lineas(p_local bigint, p_mesa text) RETURNS TABLE(id_linea bigint, id_presentacion integer, id_promocion integer, selecciones_promocion jsonb, id_barra_libre bigint, barra_nombre text, nombre text, precio numeric, cantidad integer, comentario character varying, opciones jsonb, enviada boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT l.id_linea,l.id_presentacion,l.id_promocion,l.selecciones_promocion,
        l.id_barra_libre,barra.nombre AS barra_nombre,l.nombre,l.precio,l.cantidad,l.comentario,l.opciones,
        p.estado='ENVIADO' AS enviada FROM salon_pedido_linea l JOIN salon_pedido_actual p USING(id_pedido)
        LEFT JOIN salon_pedido_linea barra ON barra.id_linea=l.id_barra_libre
        WHERE p.id_local=p_local AND p.mesa=p_mesa AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea) ORDER BY p.id_pedido,l.posicion
$$;


--
-- Name: salon_lineas_anulables(bigint, text, bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_lineas_anulables(p_local bigint, p_mesa text, p_ids bigint[]) RETURNS TABLE(id_linea bigint, nombre text, cantidad integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT l.id_linea,l.nombre,l.cantidad FROM salon_pedido_linea l JOIN salon_pedido_actual p USING(id_pedido)
    WHERE p.id_local=p_local AND p.mesa=p_mesa AND p.estado='ENVIADO' AND l.id_linea=ANY(p_ids)
    AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea)
$$;


--
-- Name: salon_lineas_cobro(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_lineas_cobro(p_local bigint, p_mesa text) RETURNS TABLE(id_linea bigint, id_pedido bigint, posicion integer, id_presentacion integer, nombre text, precio numeric, cantidad integer, comentario character varying, opciones jsonb, id_promocion integer, selecciones_promocion jsonb, id_barra_libre bigint, id_usuario integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT l.*,p.id_usuario FROM salon_pedido_linea l
        JOIN salon_pedido_actual p USING(id_pedido)
        WHERE p.id_local=p_local AND p.mesa=p_mesa AND p.estado='ENVIADO'
        AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea)
        ORDER BY l.id_linea
$$;


--
-- Name: salon_locales(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_locales() RETURNS TABLE(id_local integer, nombre character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_local,nombre FROM local WHERE estado_registro=1 ORDER BY nombre
$$;


--
-- Name: salon_mesas_control(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_mesas_control(p_local bigint) RETURNS TABLE(mesa character varying, id_usuario integer, usuario text, desde timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT p.mesa,p.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) AS usuario,
 min(p.creado_en) AS desde FROM salon_pedido_actual p JOIN usuario u USING(id_usuario)
 WHERE p.id_local=p_local GROUP BY p.mesa,p.id_usuario,u.nombres,u.apellido_paterno ORDER BY p.mesa
$$;


--
-- Name: salon_mesas_propias(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_mesas_propias(p_local bigint, p_usuario bigint) RETURNS TABLE(mesa character varying, estado text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT mesa,CASE WHEN bool_or(estado='BORRADOR') THEN 'BORRADOR' ELSE 'ENVIADO' END AS estado FROM salon_pedido_actual
      WHERE id_local=p_local AND id_usuario=p_usuario AND EXISTS(
        SELECT 1 FROM salon_pedido_linea l WHERE l.id_pedido=salon_pedido_actual.id_pedido)
      GROUP BY mesa ORDER BY mesa
$$;


--
-- Name: salon_mesas_usadas(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_mesas_usadas(p_local bigint) RETURNS TABLE(mesa character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT DISTINCT mesa FROM salon_pedido_actual WHERE id_local=p_local
$$;


--
-- Name: salon_mesas_usadas_anteriores(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_mesas_usadas_anteriores(p_local bigint) RETURNS TABLE(mesa character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT DISTINCT mesa FROM salon_pedido WHERE id_local=p_local
$$;


--
-- Name: salon_mesero_bloqueado(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_mesero_bloqueado(p_id bigint, p_local bigint) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT u.id_usuario FROM usuario u JOIN usuario_local ul USING(id_usuario) JOIN usuario_pin_salon pin USING(id_usuario)
     WHERE u.id_usuario=p_id AND ul.id_local=p_local AND ul.estado_registro=1 AND u.estado_registro=1 AND public.salon_usuario_miembro(u.id_usuario) FOR SHARE OF u,ul,pin
$$;


--
-- Name: salon_meseros(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_meseros(p_local bigint) RETURNS TABLE(id_usuario integer, nombre text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) AS nombre
 FROM usuario u JOIN usuario_local ul USING(id_usuario) JOIN usuario_pin_salon pin USING(id_usuario)
 WHERE ul.id_local=p_local AND ul.estado_registro=1 AND u.estado_registro=1 AND public.salon_usuario_miembro(u.id_usuario) ORDER BY nombre
$$;


--
-- Name: salon_nombre_presentacion(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_nombre_presentacion(p_id bigint) RETURNS character varying
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT ic.nombre FROM presentacion_venta pv
            JOIN item_carta ic USING(id_item_carta) WHERE pv.id_presentacion_venta=p_id
$$;


--
-- Name: salon_opciones_promocion(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_opciones_promocion(p_promo bigint, p_grupo bigint) RETURNS TABLE(id_presentacion_venta integer, reponible boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT po.id_presentacion_venta,
              EXISTS(SELECT 1 FROM promocion_reposicion r WHERE r.id_promocion=p_promo
                AND r.id_presentacion_venta=po.id_presentacion_venta) AS reponible
              FROM promocion_opcion po WHERE po.id_promocion_grupo=p_grupo
              ORDER BY po.id_presentacion_venta
$$;


--
-- Name: salon_pedidos(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_pedidos(p_local bigint, p_mesa text) RETURNS TABLE(id_pedido bigint, id_local integer, mesa character varying, id_usuario integer, estado character varying, version integer, creado_en timestamp with time zone, enviado_en timestamp with time zone, envio_clave uuid, envio_hash character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM salon_pedido_actual WHERE id_local=p_local AND mesa=p_mesa ORDER BY id_pedido
$$;


--
-- Name: salon_pedidos_cobro(bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_pedidos_cobro(p_local bigint, p_mesa text) RETURNS TABLE(id_pedido bigint, version integer, estado character varying, id_usuario integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_pedido,version,estado,id_usuario
        FROM salon_pedido_actual WHERE id_local=p_local AND mesa=p_mesa ORDER BY id_pedido
$$;


--
-- Name: salon_pedidos_instalados(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_pedidos_instalados() RETURNS regclass
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_pedido')
$$;


--
-- Name: salon_pedidos_instalados_existe(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_pedidos_instalados_existe() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.salon_pedido') IS NOT NULL
$$;


--
-- Name: salon_perfil(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_perfil(p_id bigint) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT min(up.id_perfil) FROM usuario_perfiles up JOIN perfiles p USING(id_perfil) WHERE up.id_usuario=p_id AND (public.perfil_tiene_capacidad(up.id_perfil, 'atender_salon') OR public.perfil_tiene_capacidad(up.id_perfil, 'supervisar_salon')) AND up.estado_registro=1 AND p.estado_registro=1
$$;


--
-- Name: salon_pin_instalado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_pin_instalado() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.usuario_pin_salon') IS NOT NULL
$$;


--
-- Name: salon_pin_vigente(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_pin_vigente(p_id bigint) RETURNS TABLE(version integer, actualizado_en timestamp with time zone)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT version,actualizado_en FROM usuario_pin_salon WHERE id_usuario=p_id FOR SHARE
$$;


--
-- Name: salon_producto_consumo(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_producto_consumo(p_id bigint) RETURNS TABLE(nombre character varying, unidad character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT nombre,unidad FROM producto WHERE id_producto=p_id
$$;


--
-- Name: salon_producto_salsa(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_producto_salsa(p_id bigint, p_presentacion bigint) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT o.id_producto FROM grupo_salsa_opcion o
                    JOIN grupo_salsa g USING(id_grupo_salsa)
                    WHERE o.id_grupo_salsa_opcion=p_id AND g.id_presentacion_venta=p_presentacion
$$;


--
-- Name: salon_promocion_padre(bigint, bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_promocion_padre(p_id bigint, p_local bigint, p_mesa text) RETURNS TABLE(id_promocion integer, selecciones_promocion jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT l.id_promocion,l.selecciones_promocion FROM salon_pedido_linea l
              JOIN salon_pedido_actual actual USING(id_pedido)
              WHERE l.id_linea=p_id AND l.id_promocion IS NOT NULL AND actual.id_local=p_local
              AND actual.mesa=p_mesa AND actual.estado='ENVIADO'
              AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea)
$$;


--
-- Name: salon_promociones_activas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_promociones_activas() RETURNS TABLE(id_promocion integer, nombre character varying, precio numeric)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
WITH reloj AS (SELECT (clock_timestamp() AT TIME ZONE 'America/Lima')::time AS hora)
SELECT p.id_promocion,p.nombre,p.precio FROM promocion p CROSS JOIN reloj
WHERE p.activo AND (p.hora_inicio IS NULL OR p.hora_fin IS NULL OR
  CASE WHEN p.hora_inicio<p.hora_fin THEN reloj.hora>=p.hora_inicio AND reloj.hora<p.hora_fin
  ELSE reloj.hora>=p.hora_inicio OR reloj.hora<p.hora_fin END)
ORDER BY p.nombre,p.id_promocion
$$;


--
-- Name: salon_promociones_instaladas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_promociones_instaladas() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT to_regclass('public.promocion_reposicion') IS NOT NULL AND EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='salon_pedido_linea' AND column_name='id_promocion')
$$;


--
-- Name: salon_receta_activa(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_receta_activa(p_id bigint) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_receta FROM receta
            WHERE id_presentacion_venta=p_id AND activo
$$;


--
-- Name: salon_reiniciar_pin(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_reiniciar_pin(p_id bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE usuario_pin_salon SET fallos=0,bloqueado_hasta=NULL WHERE id_usuario=p_id
$$;


--
-- Name: salon_reloj(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_reloj() RETURNS timestamp with time zone
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT clock_timestamp()
$$;


--
-- Name: salon_reposiciones_anulables(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_reposiciones_anulables(p_ids bigint[]) RETURNS TABLE(id_linea bigint, nombre text, cantidad integer)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_linea,nombre,cantidad FROM salon_pedido_linea
    WHERE id_barra_libre=ANY(p_ids) AND NOT EXISTS(
     SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=salon_pedido_linea.id_linea)
$$;


--
-- Name: salon_sesion(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_sesion(p_usuario bigint, p_local bigint) RETURNS TABLE(nombres character varying, local character varying, version integer, actualizado_en timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT u.nombres,l.nombre AS local,pin.version,pin.actualizado_en
        FROM usuario u JOIN usuario_pin_salon pin USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.id_usuario=p_usuario AND ul.id_local=p_local AND ul.estado_registro=1
          AND u.estado_registro=1 AND l.estado_registro=1 AND public.salon_usuario_elegible(u.id_usuario)
$$;


--
-- Name: salon_siguiente_movimiento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_siguiente_movimiento() RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
SELECT coalesce(max(CASE WHEN codigo ~ '^MI-[0-9]+$'
            THEN substring(codigo FROM 4)::integer END),0)+1 FROM movimiento_inventario
$_$;


--
-- Name: salon_subproducto(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_subproducto(p_id bigint) RETURNS TABLE(id_subproducto integer, codigo character varying, nombre character varying, rendimiento numeric, unidad character varying, instruccion text, activo boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT * FROM subproducto WHERE id_subproducto=p_id
$$;


--
-- Name: salon_usuario_elegible(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_usuario_elegible(p_usuario integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT public.salon_usuario_miembro(p_usuario) OR EXISTS (
    SELECT 1 FROM usuario_perfiles up JOIN perfiles pf USING (id_perfil)
    WHERE up.id_usuario = p_usuario AND public.perfil_tiene_capacidad(up.id_perfil, 'supervisar_salon')
      AND up.estado_registro = 1 AND pf.estado_registro = 1
)
$$;


--
-- Name: salon_usuario_miembro(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_usuario_miembro(p_usuario integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1 FROM usuario_perfiles up JOIN perfiles pf USING (id_perfil)
    WHERE up.id_usuario = p_usuario AND public.perfil_tiene_capacidad(up.id_perfil, 'atender_salon')
      AND up.estado_registro = 1 AND pf.estado_registro = 1
) AND EXISTS (
    SELECT 1 FROM usuario_puestos_laborales up JOIN puesto_laboral p USING (id_puesto_laboral)
    WHERE up.id_usuario = p_usuario AND up.estado_registro = 1 AND p.estado_registro = 1
      AND lower(trim(p.nombre)) IN ('mesero', 'bartender')
)
$$;


--
-- Name: salon_usuarios(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_usuarios(p_local bigint) RETURNS TABLE(id_usuario integer, nombre text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) AS nombre
        FROM usuario u JOIN usuario_pin_salon pin USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.estado_registro=1 AND ul.estado_registro=1 AND l.estado_registro=1
          AND ul.id_local=p_local AND public.salon_usuario_elegible(u.id_usuario) ORDER BY nombre
$$;


--
-- Name: salon_verificar_pin(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_verificar_pin(p_usuario bigint, p_local bigint) RETURNS TABLE(id_usuario integer, pin_hash text, version integer, fallos integer, bloqueado_hasta timestamp with time zone, actualizado_en timestamp with time zone, nombres character varying, local character varying, bloqueado boolean)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT pin.*,u.nombres,l.nombre AS local,
        pin.bloqueado_hasta>clock_timestamp() AS bloqueado
        FROM usuario_pin_salon pin JOIN usuario u USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.id_usuario=p_usuario AND ul.id_local=p_local AND u.estado_registro=1
          AND ul.estado_registro=1 AND l.estado_registro=1 AND public.salon_usuario_elegible(u.id_usuario) FOR UPDATE OF pin
$$;


--
-- Name: salon_vincular_pedido(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salon_vincular_pedido(p_cobro bigint, p_pedido bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO salon_cobro_pedido(id_cobro,id_pedido) VALUES(p_cobro,p_pedido)
$$;


--
-- Name: stock_minimo_por_local(integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stock_minimo_por_local(p_producto integer, p_local integer, p_minimo_general numeric) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
    IF to_regclass('public.producto_stock_local') IS NULL THEN
        RETURN p_minimo_general;
    END IF;
    RETURN COALESCE((
        SELECT s.stock_minimo FROM public.producto_stock_local s
        WHERE s.id_producto=p_producto AND s.id_local=p_local
    ), 0);
END;
$$;


--
-- Name: usuarios_actualizar(text, text, text, text, text, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_actualizar(p_dni text, p_nombres text, p_apellido_paterno text, p_apellido_materno text, p_celular text, p_correo text, p_clave text, p_id_gestor integer, p_id_usuario integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE usuario
SET
    dni = p_dni,
    nombres = p_nombres,
    apellido_paterno = p_apellido_paterno,
    apellido_materno = p_apellido_materno,
    celular = p_celular,
    correo_electronico = p_correo,
    clave = CASE
        WHEN p_clave IS NULL THEN clave
        ELSE crypt(p_clave, gen_salt('bf'))
    END,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
WHERE id_usuario = p_id_usuario
$$;


--
-- Name: usuarios_asignar_local(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_asignar_local(p_id_usuario integer, p_id_local integer, p_id_gestor integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO usuario_local (
    id_usuario,
    id_local,
    usuario_asignacion,
    estado_registro
) VALUES (
    p_id_usuario,
    p_id_local,
    p_id_gestor,
    1
)
ON CONFLICT (id_usuario, id_local)
DO UPDATE SET
    estado_registro = 1,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_TIMESTAMP
$$;


--
-- Name: usuarios_asignar_perfil(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_asignar_perfil(p_id_usuario integer, p_id_perfil integer, p_id_gestor integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO usuario_perfiles (
    id_usuario,
    id_perfil,
    usuario_asignacion,
    estado_registro
) VALUES (
    p_id_usuario,
    p_id_perfil,
    p_id_gestor,
    1
)
ON CONFLICT (id_usuario, id_perfil)
DO UPDATE SET
    estado_registro = 1,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
$$;


--
-- Name: usuarios_asignar_puesto(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_asignar_puesto(p_id_usuario integer, p_id_puesto_laboral integer, p_id_gestor integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO usuario_puestos_laborales (
    id_usuario,
    id_puesto_laboral,
    usuario_asignacion,
    estado_registro
) VALUES (
    p_id_usuario,
    p_id_puesto_laboral,
    p_id_gestor,
    1
)
ON CONFLICT (id_usuario, id_puesto_laboral)
DO UPDATE SET
    estado_registro = 1,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
$$;


--
-- Name: local; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.local (
    id_local integer NOT NULL,
    codigo character varying(30) NOT NULL,
    nombre character varying(100) NOT NULL,
    direccion character varying(250),
    estado_registro smallint DEFAULT 1 NOT NULL,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_creacion integer,
    fecha_modificacion timestamp without time zone,
    usuario_modificacion integer,
    CONSTRAINT chk_local_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: usuarios_bloquear_local(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_bloquear_local(p_id integer) RETURNS SETOF public.local
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT l.* FROM local l WHERE l.id_local = p_id FOR UPDATE
$$;


--
-- Name: usuarios_bloquear_locales(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_bloquear_locales() RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    LOCK TABLE local IN SHARE ROW EXCLUSIVE MODE
$$;


--
-- Name: usuarios_buscar(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_buscar(p_id_usuario integer, p_id_perfil_gestor integer, p_id_local integer) RETURNS TABLE(id_usuario integer, id integer, ids_perfiles integer[])
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    u.id_usuario,
    u.id_usuario AS id,
    COALESCE(
        ARRAY_AGG(
            up.id_perfil
            ORDER BY up.id_perfil
        ) FILTER (
            WHERE up.estado_registro = 1
        ),
        ARRAY[]::INTEGER[]
    ) AS ids_perfiles
FROM usuario u
INNER JOIN usuario_perfiles up
    ON up.id_usuario = u.id_usuario
WHERE u.id_usuario = p_id_usuario
  AND (public.perfil_tiene_capacidad(p_id_perfil_gestor, 'administrar_globalmente') OR EXISTS (
      SELECT 1
      FROM usuario_local ul
      WHERE ul.id_usuario = u.id_usuario
        AND ul.id_local = p_id_local
        AND ul.estado_registro = 1
  ))
  AND EXISTS (
      SELECT 1
      FROM usuario_perfiles up_existente
      WHERE up_existente.id_usuario = u.id_usuario
        AND up_existente.estado_registro = 1
  )
  AND NOT EXISTS (
      SELECT 1
      FROM usuario_perfiles up_no_permitido
      WHERE up_no_permitido.id_usuario = u.id_usuario
        AND up_no_permitido.estado_registro = 1
        AND NOT EXISTS (
            SELECT 1
            FROM perfil_gestion_usuario pgu
            WHERE pgu.id_perfil_gestor = p_id_perfil_gestor
              AND pgu.id_perfil_objetivo =
                  up_no_permitido.id_perfil
              AND pgu.puede_editar = TRUE
              AND pgu.estado_registro = 1
        )
  )
GROUP BY u.id_usuario
$$;


--
-- Name: usuarios_cambiar_estado(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_cambiar_estado(p_estado integer, p_id_gestor integer, p_id_usuario integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE usuario
SET
    estado_registro = p_estado,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
WHERE id_usuario = p_id_usuario
$$;


--
-- Name: usuarios_contar_locales(integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_contar_locales(p_ids_locales integer[]) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT COUNT(*)
FROM local
WHERE id_local = ANY(p_ids_locales)
  AND estado_registro = 1
$$;


--
-- Name: usuarios_correo_existe(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_correo_existe(p_correo text, p_excluir_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM usuario
    WHERE LOWER(correo_electronico) = LOWER(p_correo)
      AND (
          p_excluir_id IS NULL
          OR id_usuario <> p_excluir_id
      )
)
$$;


--
-- Name: usuarios_crear(text, text, text, text, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_crear(p_dni text, p_nombres text, p_apellido_paterno text, p_apellido_materno text, p_celular text, p_correo text, p_clave text, p_id_gestor integer) RETURNS integer
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
INSERT INTO usuario (
    dni,
    nombres,
    apellido_paterno,
    apellido_materno,
    celular,
    correo_electronico,
    clave,
    usuario_creacion,
    estado_registro
) VALUES (
    p_dni,
    p_nombres,
    p_apellido_paterno,
    p_apellido_materno,
    p_celular,
    p_correo,
    crypt(p_clave, gen_salt('bf')),
    p_id_gestor,
    1
)
RETURNING id_usuario
$$;


--
-- Name: usuarios_crear_local(text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_crear_local(p_codigo text, p_nombre text, p_direccion text, p_usuario integer) RETURNS TABLE(id_local integer, codigo character varying, nombre character varying, direccion character varying, estado_registro smallint)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    INSERT INTO local AS l (codigo, nombre, direccion, usuario_creacion)
    VALUES (p_codigo, p_nombre, p_direccion, p_usuario)
    RETURNING l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
$$;


--
-- Name: usuarios_desactivar_locales(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_desactivar_locales(p_id_gestor integer, p_id_usuario integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE usuario_local
SET
    estado_registro = 0,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_TIMESTAMP
WHERE id_usuario = p_id_usuario
  AND estado_registro = 1
$$;


--
-- Name: usuarios_desactivar_perfiles(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_desactivar_perfiles(p_id_gestor integer, p_id_usuario integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE usuario_perfiles
SET
    estado_registro = 0,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
WHERE id_usuario = p_id_usuario
  AND estado_registro = 1
$$;


--
-- Name: usuarios_desactivar_puestos(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_desactivar_puestos(p_id_gestor integer, p_id_usuario integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
UPDATE usuario_puestos_laborales
SET estado_registro = 0,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
WHERE id_usuario = p_id_usuario
  AND estado_registro = 1
$$;


--
-- Name: usuarios_dni_existe(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_dni_existe(p_dni text, p_excluir_id integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM usuario
    WHERE dni = p_dni
      AND (
          p_excluir_id IS NULL
          OR id_usuario <> p_excluir_id
      )
)
$$;


--
-- Name: usuarios_editar_local(integer, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_editar_local(p_id integer, p_nombre text, p_direccion text, p_usuario integer) RETURNS TABLE(id_local integer, codigo character varying, nombre character varying, direccion character varying, estado_registro smallint)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE local AS l SET nombre = p_nombre, direccion = p_direccion,
        usuario_modificacion = p_usuario, fecha_modificacion = CURRENT_TIMESTAMP
    WHERE l.id_local = p_id
    RETURNING l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
$$;


--
-- Name: usuarios_eliminar_local(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_eliminar_local(p_id integer) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    DELETE FROM local WHERE id_local = p_id
$$;


--
-- Name: usuarios_estado_local(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_estado_local(p_id integer, p_estado integer, p_usuario integer) RETURNS TABLE(id_local integer, codigo character varying, nombre character varying, direccion character varying, estado_registro smallint)
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    UPDATE local AS l SET estado_registro = p_estado,
        usuario_modificacion = p_usuario, fecha_modificacion = CURRENT_TIMESTAMP
    WHERE l.id_local = p_id
    RETURNING l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
$$;


--
-- Name: usuarios_listar(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_listar(p_id_perfil_gestor integer, p_id_local integer) RETURNS TABLE(id_usuario integer, dni character varying, nombres character varying, apellido_paterno character varying, apellido_materno character varying, celular character varying, correo_electronico character varying, estado_registro smallint, fecha_creacion date, ids_puestos_laborales integer[], puestos_laborales jsonb, ids_perfiles integer[], perfiles jsonb, ids_locales integer[], locales jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    u.id_usuario,
    u.dni,
    u.nombres,
    u.apellido_paterno,
    u.apellido_materno,
    u.celular,
    u.correo_electronico,
    u.estado_registro,
    u.fecha_creacion,
    COALESCE(
        (
            SELECT ARRAY_AGG(
                upl.id_puesto_laboral
                ORDER BY upl.id_puesto_laboral
            )
            FROM usuario_puestos_laborales upl
            WHERE upl.id_usuario = u.id_usuario
              AND upl.estado_registro = 1
        ),
        ARRAY[]::INTEGER[]
    ) AS ids_puestos_laborales,
    COALESCE(
        (
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_puesto_laboral', pl.id_puesto_laboral,
                    'nombre', pl.nombre
                )
                ORDER BY pl.nombre
            )
            FROM usuario_puestos_laborales upl
            INNER JOIN puesto_laboral pl
                ON pl.id_puesto_laboral = upl.id_puesto_laboral
               AND pl.estado_registro = 1
            WHERE upl.id_usuario = u.id_usuario
              AND upl.estado_registro = 1
        ),
        '[]'::JSONB
    ) AS puestos_laborales,
    COALESCE(
        (
            SELECT ARRAY_AGG(
                up.id_perfil
                ORDER BY up.id_perfil
            )
            FROM usuario_perfiles up
            WHERE up.id_usuario = u.id_usuario
              AND up.estado_registro = 1
        ),
        ARRAY[]::INTEGER[]
    ) AS ids_perfiles,
    COALESCE(
        (
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_perfil', p.id_perfil,
                    'nombre', p.nombre
                )
                ORDER BY p.id_perfil
            )
            FROM usuario_perfiles up
            INNER JOIN perfiles p
                ON p.id_perfil = up.id_perfil
               AND p.estado_registro = 1
            WHERE up.id_usuario = u.id_usuario
              AND up.estado_registro = 1
        ),
        '[]'::JSONB
    ) AS perfiles,
    COALESCE(
        (
            SELECT ARRAY_AGG(
                ul2.id_local
                ORDER BY ul2.id_local
            )
            FROM usuario_local ul2
            WHERE ul2.id_usuario = u.id_usuario
              AND ul2.estado_registro = 1
        ),
        ARRAY[]::INTEGER[]
    ) AS ids_locales,
    COALESCE(
        (
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'id_local', l2.id_local,
                    'codigo', l2.codigo,
                    'nombre', l2.nombre
                )
                ORDER BY l2.nombre
            )
            FROM usuario_local ul2
            INNER JOIN local l2
                ON l2.id_local = ul2.id_local
               AND l2.estado_registro = 1
            WHERE ul2.id_usuario = u.id_usuario
              AND ul2.estado_registro = 1
        ),
        '[]'::JSONB
    ) AS locales
FROM usuario u
WHERE (public.perfil_tiene_capacidad(p_id_perfil_gestor, 'administrar_globalmente') OR EXISTS (
    SELECT 1 FROM usuario_local ul_filtro
    WHERE ul_filtro.id_usuario=u.id_usuario
      AND ul_filtro.id_local=p_id_local AND ul_filtro.estado_registro=1
)) AND EXISTS (
    SELECT 1
    FROM usuario_perfiles up
    INNER JOIN perfil_gestion_usuario pgu
        ON pgu.id_perfil_objetivo = up.id_perfil
       AND pgu.id_perfil_gestor = p_id_perfil_gestor
       AND pgu.estado_registro = 1
    WHERE up.id_usuario = u.id_usuario
      AND up.estado_registro = 1
)
  AND NOT EXISTS (
    SELECT 1
    FROM usuario_perfiles up_no_permitido
    WHERE up_no_permitido.id_usuario = u.id_usuario
      AND up_no_permitido.estado_registro = 1
      AND NOT EXISTS (
          SELECT 1
          FROM perfil_gestion_usuario pgu_permitido
          WHERE pgu_permitido.id_perfil_gestor = p_id_perfil_gestor
            AND pgu_permitido.id_perfil_objetivo =
                up_no_permitido.id_perfil
            AND pgu_permitido.puede_editar = TRUE
            AND pgu_permitido.estado_registro = 1
      )
  )
ORDER BY
    u.nombres,
    u.apellido_paterno,
    u.id_usuario
$$;


--
-- Name: usuarios_listar_locales(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_listar_locales() RETURNS TABLE(id_local integer, codigo character varying, nombre character varying, direccion character varying, estado_registro smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
    FROM local l ORDER BY length(l.codigo), l.codigo
$$;


--
-- Name: usuarios_local_tiene_datos(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_local_tiene_datos(p_id integer) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
DECLARE
    relacion record;
    tiene_datos boolean;
BEGIN
    FOR relacion IN
        SELECT ns.nspname AS esquema, cl.relname AS tabla,
               destino.attname AS columna, origen.attname AS referencia,
               cardinality(c.conkey) AS columnas
        FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        JOIN pg_namespace ns ON ns.oid = cl.relnamespace
        JOIN pg_attribute destino ON destino.attrelid = c.conrelid AND destino.attnum = c.conkey[1]
        JOIN pg_attribute origen ON origen.attrelid = c.confrelid AND origen.attnum = c.confkey[1]
        WHERE c.contype = 'f' AND c.confrelid = 'public.local'::regclass
    LOOP
        IF relacion.columnas <> 1 THEN
            RETURN true;
        END IF;

        EXECUTE format(
            'SELECT EXISTS (SELECT 1 FROM %I.%I AS dato JOIN public.local AS l ON dato.%I = l.%I WHERE l.id_local = $1)',
            relacion.esquema, relacion.tabla, relacion.columna, relacion.referencia
        ) INTO tiene_datos USING p_id;

        IF tiene_datos THEN
            RETURN true;
        END IF;
    END LOOP;

    RETURN false;
END
$_$;


--
-- Name: usuarios_locales_activos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_locales_activos() RETURNS TABLE(id_local integer, codigo character varying, nombre character varying, direccion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT id_local, codigo, nombre, direccion
FROM local
WHERE estado_registro = 1
ORDER BY nombre
$$;


--
-- Name: usuarios_perfil_gestionable(integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_perfil_gestionable(p_id_perfil_gestor integer, p_id_perfil_objetivo integer, p_crear boolean) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM perfil_gestion_usuario
    WHERE id_perfil_gestor = p_id_perfil_gestor
      AND id_perfil_objetivo = p_id_perfil_objetivo
      AND CASE WHEN p_crear THEN puede_crear ELSE puede_editar END = TRUE
      AND estado_registro = 1
)
$$;


--
-- Name: usuarios_perfiles_permitidos(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_perfiles_permitidos(p_id_perfil_gestor integer) RETURNS TABLE(id_perfil integer, nombre character varying, puede_crear boolean, puede_editar boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    p.id_perfil,
    p.nombre,
    pgu.puede_crear,
    pgu.puede_editar
FROM perfil_gestion_usuario pgu
INNER JOIN perfiles p
    ON p.id_perfil = pgu.id_perfil_objetivo
   AND p.estado_registro = 1
WHERE pgu.id_perfil_gestor = p_id_perfil_gestor
  AND pgu.estado_registro = 1
ORDER BY p.id_perfil
$$;


--
-- Name: usuarios_puestos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_puestos() RETURNS TABLE(id_puesto_laboral integer, nombre character varying, descripcion character varying)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT
    id_puesto_laboral,
    nombre,
    descripcion
FROM puesto_laboral
WHERE estado_registro = 1
ORDER BY nombre
$$;


--
-- Name: usuarios_puestos_existen(integer, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_puestos_existen(p_cantidad integer, p_ids_puestos_laborales integer[]) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
SELECT COUNT(*) = p_cantidad
FROM puesto_laboral
WHERE id_puesto_laboral = ANY(p_ids_puestos_laborales)
  AND estado_registro = 1
$$;


--
-- Name: usuarios_siguiente_codigo_local(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_siguiente_codigo_local() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
    WITH usados AS (
        SELECT substring(codigo FROM 5)::bigint AS numero FROM local
        WHERE codigo ~ '^TDA-[0-9]+$'
    ), candidatos AS (
        SELECT 1::bigint AS numero UNION SELECT numero + 1 FROM usados
    ), libre AS (
        SELECT min(c.numero)::text AS numero FROM candidatos c
        WHERE NOT EXISTS (SELECT 1 FROM usados u WHERE u.numero = c.numero)
    )
    SELECT 'TDA-' || lpad(numero, greatest(3, length(numero)), '0') FROM libre
$_$;


--
-- Name: usuarios_total_locales_activos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuarios_total_locales_activos() RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
    SELECT count(*) FROM local WHERE estado_registro = 1
$$;


--
-- Name: validar_movimiento_motivo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_movimiento_motivo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.movimiento_motivo AS regla
        WHERE regla.codigo = NEW.motivo_movimiento
          AND regla.tipo_movimiento = NEW.tipo_movimiento
          AND regla.requiere_local = (NEW.local_relacionado IS NOT NULL)
          AND regla.requiere_proveedor = (NEW.id_proveedor IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'El motivo no coincide con el tipo, local o proveedor del movimiento'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;


--
-- Name: validar_unidad_grupo_salsa_opcion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_unidad_grupo_salsa_opcion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE unidad_producto VARCHAR(10);
BEGIN
    SELECT unidad INTO unidad_producto
    FROM producto
    WHERE id_producto=NEW.id_producto;

    IF unidad_producto IS NULL THEN
        RAISE EXCEPTION 'No existe el producto con ID %',NEW.id_producto;
    END IF;

    IF NEW.unidad<>unidad_producto THEN
        RAISE EXCEPTION 'La unidad % no coincide con la unidad % del producto ID %',
            NEW.unidad,unidad_producto,NEW.id_producto;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: validar_unidad_medida_contexto(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_unidad_medida_contexto() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: validar_unidad_receta_detalle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_unidad_receta_detalle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    unidad_esperada VARCHAR(10);
BEGIN
    IF NEW.tipo_componente = 'PRODUCTO' THEN
        SELECT unidad INTO unidad_esperada
        FROM producto
        WHERE id_producto = NEW.id_producto;
    ELSE
        SELECT unidad INTO unidad_esperada
        FROM subproducto
        WHERE id_subproducto = NEW.id_subproducto;
    END IF;

    IF unidad_esperada IS NULL THEN
        RAISE EXCEPTION 'No se encontró el componente indicado';
    END IF;

    IF NEW.unidad <> unidad_esperada THEN
        RAISE EXCEPTION
            'La unidad % no coincide con la unidad esperada %',
            NEW.unidad, unidad_esperada;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: validar_unidad_subproducto_detalle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_unidad_subproducto_detalle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    unidad_producto VARCHAR(10);
BEGIN
    SELECT unidad
    INTO unidad_producto
    FROM producto
    WHERE id_producto = NEW.id_producto;

    IF unidad_producto IS NULL THEN
        RAISE EXCEPTION
            'No existe el producto con ID %',
            NEW.id_producto;
    END IF;

    IF NEW.unidad <> unidad_producto THEN
        RAISE EXCEPTION
            'La unidad % no coincide con la unidad % del producto ID %',
            NEW.unidad,
            unidad_producto,
            NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: actividad_usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actividad_usuario (
    id_actividad_usuario bigint NOT NULL,
    id_usuario integer NOT NULL,
    modulo character varying(60) NOT NULL,
    accion character varying(40) NOT NULL,
    id_registro_afectado integer,
    descripcion character varying(500) NOT NULL,
    fecha_actividad timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    id_perfil_utilizado integer,
    id_puesto_laboral integer,
    id_local integer,
    CONSTRAINT ck_actividad_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: actividad_usuario_id_actividad_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.actividad_usuario ALTER COLUMN id_actividad_usuario ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.actividad_usuario_id_actividad_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asistente_ia_borrador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistente_ia_borrador (
    id uuid NOT NULL,
    id_usuario integer NOT NULL,
    id_perfil integer NOT NULL,
    id_local integer NOT NULL,
    plan jsonb NOT NULL,
    estado character varying(16) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    resultado jsonb,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    vence_en timestamp with time zone DEFAULT (now() + '00:20:00'::interval) NOT NULL,
    CONSTRAINT asistente_ia_borrador_estado_check CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'EJECUTANDO'::character varying, 'REALIZADO'::character varying, 'FALLIDO'::character varying, 'CANCELADO'::character varying])::text[])))
);


--
-- Name: asistente_ia_workspace; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistente_ia_workspace (
    id_usuario integer NOT NULL,
    id_perfil integer NOT NULL,
    id_local integer NOT NULL,
    snapshot jsonb,
    revision bigint DEFAULT 0 NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    vence_en timestamp with time zone DEFAULT (now() + '02:00:00'::interval) NOT NULL,
    CONSTRAINT asistente_ia_workspace_revision_check CHECK ((revision >= 0)),
    CONSTRAINT asistente_ia_workspace_snapshot_check CHECK (((snapshot IS NULL) OR (jsonb_typeof(snapshot) = 'object'::text))),
    CONSTRAINT asistente_ia_workspace_snapshot_check1 CHECK (((snapshot IS NULL) OR (octet_length((snapshot)::text) <= 200000)))
);


--
-- Name: TABLE asistente_ia_workspace; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.asistente_ia_workspace IS 'Interfaz recuperable. Conservar revisiones al limpiar o vencer para impedir escrituras tardías.';


--
-- Name: auditoria_cambio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria_cambio (
    id_auditoria_cambio bigint NOT NULL,
    id_usuario integer NOT NULL,
    modulo character varying(60) NOT NULL,
    accion character varying(40) NOT NULL,
    tabla_afectada character varying(80) NOT NULL,
    id_registro_afectado integer,
    datos_anteriores jsonb,
    datos_nuevos jsonb,
    motivo character varying(500),
    fecha_cambio timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    id_perfil_utilizado integer,
    id_puesto_laboral integer,
    id_local integer,
    CONSTRAINT ck_auditoria_cambio_accion CHECK ((length(btrim((accion)::text)) > 0)),
    CONSTRAINT ck_auditoria_cambio_modulo CHECK ((length(btrim((modulo)::text)) > 0)),
    CONSTRAINT ck_auditoria_cambio_tabla CHECK ((length(btrim((tabla_afectada)::text)) > 0))
);


--
-- Name: auditoria_cambio_id_auditoria_cambio_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditoria_cambio ALTER COLUMN id_auditoria_cambio ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditoria_cambio_id_auditoria_cambio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: categoria_carta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categoria_carta (
    id_categoria_carta integer NOT NULL,
    nombre character varying(100) NOT NULL,
    prefijo character varying(5) NOT NULL,
    siguiente_numero integer DEFAULT 1 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_categoria_carta_prefijo CHECK (((prefijo)::text ~ '^[A-Z]{1,3}$'::text)),
    CONSTRAINT ck_categoria_carta_siguiente_numero CHECK ((siguiente_numero >= 1))
);


--
-- Name: categoria_carta_id_categoria_carta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.categoria_carta ALTER COLUMN id_categoria_carta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.categoria_carta_id_categoria_carta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: categoria_producto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categoria_producto (
    id_categoria integer NOT NULL,
    nombre character varying(100) NOT NULL,
    prefijo character varying(5) NOT NULL,
    siguiente_numero integer DEFAULT 1 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_categoria_producto_prefijo CHECK (((prefijo)::text ~ '^[A-Z]{1,3}$'::text)),
    CONSTRAINT ck_categoria_producto_siguiente_numero CHECK ((siguiente_numero >= 1))
);


--
-- Name: categoria_producto_id_categoria_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.categoria_producto ALTER COLUMN id_categoria ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.categoria_producto_id_categoria_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cliente_comercial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cliente_comercial (
    id_cliente uuid NOT NULL,
    id_local integer NOT NULL,
    tipo_persona character varying(8) DEFAULT 'NATURAL'::character varying NOT NULL,
    tipo_documento character varying(9),
    numero_documento character varying(30),
    nombre character varying(200) NOT NULL,
    direccion character varying(300),
    email character varying(200),
    telefono character varying(40),
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cliente_comercial_check CHECK (((numero_documento IS NULL) OR (tipo_documento IS NOT NULL))),
    CONSTRAINT cliente_comercial_check1 CHECK ((((tipo_persona)::text <> 'JURIDICA'::text) OR (tipo_documento IS NULL) OR ((tipo_documento)::text = 'RUC'::text))),
    CONSTRAINT cliente_comercial_nombre_check CHECK ((btrim((nombre)::text) <> ''::text)),
    CONSTRAINT cliente_comercial_tipo_documento_check CHECK (((tipo_documento)::text = ANY ((ARRAY['DNI'::character varying, 'RUC'::character varying, 'CE'::character varying, 'PASAPORTE'::character varying])::text[]))),
    CONSTRAINT cliente_comercial_tipo_persona_check CHECK (((tipo_persona)::text = ANY ((ARRAY['NATURAL'::character varying, 'JURIDICA'::character varying])::text[])))
);


--
-- Name: TABLE cliente_comercial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cliente_comercial IS 'Clientes del restaurante, registrados manualmente por local; sin validacion externa de identidad.';


--
-- Name: configuracion_operativa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.configuracion_operativa (
    unica boolean DEFAULT true NOT NULL,
    hora_limite_borrador time without time zone NOT NULL,
    distribucion_salon jsonb NOT NULL,
    CONSTRAINT configuracion_operativa_distribucion_salon_check CHECK ((jsonb_typeof(distribucion_salon) = 'array'::text)),
    CONSTRAINT configuracion_operativa_unica_check CHECK (unica)
);


--
-- Name: fact_api_adjunto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_adjunto (
    id_adjunto uuid NOT NULL,
    id_local integer NOT NULL,
    id_factura_recepcion integer NOT NULL,
    formato text NOT NULL,
    ruta text NOT NULL,
    sha256 character(64) NOT NULL,
    bytes integer NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fact_api_adjunto_bytes_check CHECK (((bytes > 0) AND (bytes <= 5242880))),
    CONSTRAINT fact_api_adjunto_formato_check CHECK ((formato = ANY (ARRAY['PDF'::text, 'XML'::text])))
);


--
-- Name: fact_api_archivo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_archivo (
    id_archivo uuid NOT NULL,
    id_documento uuid NOT NULL,
    formato text NOT NULL,
    ruta text NOT NULL,
    sha256 character(64) NOT NULL,
    bytes integer NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fact_api_archivo_bytes_check CHECK ((bytes > 0)),
    CONSTRAINT fact_api_archivo_formato_check CHECK ((formato = ANY (ARRAY['A4'::text, '80mm'::text])))
);


--
-- Name: fact_api_circuito; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_circuito (
    id integer NOT NULL,
    fallos integer DEFAULT 0 NOT NULL,
    abierto_hasta timestamp with time zone,
    CONSTRAINT fact_api_circuito_id_check CHECK ((id = 1))
);


--
-- Name: fact_api_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_config (
    id_local integer NOT NULL,
    activo boolean DEFAULT false NOT NULL,
    ambiente text DEFAULT 'DEMO'::text NOT NULL,
    empresa jsonb NOT NULL,
    serie_factura character varying(4) NOT NULL,
    serie_boleta character varying(4) NOT NULL,
    tasa_igv numeric(5,2) NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fact_api_config_ambiente_check CHECK ((ambiente = 'DEMO'::text)),
    CONSTRAINT fact_api_config_tasa_igv_check CHECK (((tasa_igv >= (0)::numeric) AND (tasa_igv <= (100)::numeric)))
);


--
-- Name: fact_api_documento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_documento (
    id_documento uuid NOT NULL,
    id_operacion uuid NOT NULL,
    id_local integer NOT NULL,
    id_externo uuid NOT NULL,
    numero text NOT NULL,
    estado text NOT NULL,
    subtotal numeric(14,2) NOT NULL,
    igv numeric(14,2) NOT NULL,
    total numeric(14,2) NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fact_api_documento_estado_check CHECK ((estado = 'DEMO_GENERADO'::text))
);


--
-- Name: fact_api_escalado; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_escalado (
    id integer NOT NULL,
    supervisor uuid NOT NULL,
    pid integer NOT NULL,
    minimo integer NOT NULL,
    maximo integer NOT NULL,
    activos integer NOT NULL,
    objetivo integer NOT NULL,
    listos integer NOT NULL,
    ocupados integer NOT NULL,
    espera_segundos numeric NOT NULL,
    pausado boolean NOT NULL,
    workers jsonb NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fact_api_escalado_activos_check CHECK ((activos >= 0)),
    CONSTRAINT fact_api_escalado_check CHECK ((((maximo >= 1) AND (maximo <= 4)) AND (maximo >= minimo))),
    CONSTRAINT fact_api_escalado_id_check CHECK ((id = 1)),
    CONSTRAINT fact_api_escalado_minimo_check CHECK ((minimo >= 1)),
    CONSTRAINT fact_api_escalado_objetivo_check CHECK ((objetivo >= 0))
);


--
-- Name: fact_api_intento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_api_intento (
    id_intento bigint NOT NULL,
    id_operacion uuid NOT NULL,
    numero integer NOT NULL,
    inicio timestamp with time zone DEFAULT now() NOT NULL,
    fin timestamp with time zone,
    duracion_ms numeric,
    http_status integer,
    resultado text DEFAULT 'INICIADO'::text NOT NULL
);


--
-- Name: fact_api_intento_id_intento_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fact_api_intento_id_intento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fact_api_intento_id_intento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fact_api_intento_id_intento_seq OWNED BY public.fact_api_intento.id_intento;


--
-- Name: fact_api_seguimiento; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.fact_api_seguimiento AS
 SELECT o.id_operacion,
    o.id_local,
    l.nombre AS local,
    o.origen,
    o.id_origen,
    o.version,
    o.estado,
    o.intentos,
    o.ultimo_http,
    o.ultimo_error,
    o.creado_en,
    o.actualizado_en,
    d.numero,
    d.estado AS estado_documento,
    d.total,
    d.id_documento
   FROM ((public.fact_api_operacion o
     JOIN public.local l USING (id_local))
     LEFT JOIN public.fact_api_documento d USING (id_operacion));


--
-- Name: factura_recepcion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion (
    id_factura_recepcion integer NOT NULL,
    id_orden_compra integer NOT NULL,
    id_proveedor integer NOT NULL,
    numero_factura character varying(40) NOT NULL,
    fecha_recepcion date NOT NULL,
    usuario_recepcion integer NOT NULL,
    datos_factura jsonb,
    entregas jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: factura_recepcion_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion_detalle (
    id_factura_recepcion_detalle integer NOT NULL,
    id_factura_recepcion integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad_recibida numeric(12,3) NOT NULL,
    CONSTRAINT ck_factura_cantidad CHECK ((cantidad_recibida > (0)::numeric))
);


--
-- Name: factura_recepcion_detalle_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion_detalle_historial (
    id_factura_recepcion_detalle_historial bigint CONSTRAINT factura_recepcion_detalle_h_id_factura_recepcion_detal_not_null NOT NULL,
    id_factura_recepcion_historial bigint CONSTRAINT factura_recepcion_detalle_h_id_factura_recepcion_histo_not_null NOT NULL,
    id_producto integer NOT NULL,
    cantidad_anterior numeric(14,3),
    cantidad_nueva numeric(14,3),
    CONSTRAINT ck_frdh_cantidad_anterior CHECK (((cantidad_anterior IS NULL) OR (cantidad_anterior >= (0)::numeric))),
    CONSTRAINT ck_frdh_cantidad_nueva CHECK (((cantidad_nueva IS NULL) OR (cantidad_nueva >= (0)::numeric))),
    CONSTRAINT ck_frdh_valores_diferentes CHECK ((cantidad_anterior IS DISTINCT FROM cantidad_nueva))
);


--
-- Name: factura_recepcion_detalle_his_id_factura_recepcion_detalle__seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion_detalle_historial ALTER COLUMN id_factura_recepcion_detalle_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_detalle_his_id_factura_recepcion_detalle__seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: factura_recepcion_detalle_id_factura_recepcion_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion_detalle ALTER COLUMN id_factura_recepcion_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_detalle_id_factura_recepcion_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: factura_recepcion_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion_historial (
    id_factura_recepcion_historial bigint CONSTRAINT factura_recepcion_historial_id_factura_recepcion_histo_not_null NOT NULL,
    id_factura_recepcion integer NOT NULL,
    numero_factura_anterior character varying(40) NOT NULL,
    numero_factura_nuevo character varying(40) NOT NULL,
    fecha_recepcion_anterior date NOT NULL,
    fecha_recepcion_nueva date NOT NULL,
    usuario_correccion integer NOT NULL,
    motivo_correccion character varying(100) NOT NULL,
    observacion character varying(500) NOT NULL,
    fecha_correccion timestamp without time zone DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'::text) NOT NULL,
    CONSTRAINT ck_frh_motivo CHECK ((btrim((motivo_correccion)::text) <> ''::text)),
    CONSTRAINT ck_frh_observacion CHECK ((btrim((observacion)::text) <> ''::text))
);


--
-- Name: factura_recepcion_historial_id_factura_recepcion_historial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion_historial ALTER COLUMN id_factura_recepcion_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_historial_id_factura_recepcion_historial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: factura_recepcion_id_factura_recepcion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion ALTER COLUMN id_factura_recepcion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_id_factura_recepcion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: facturacion_comprobante; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facturacion_comprobante (
    id uuid NOT NULL,
    id_cobro bigint NOT NULL,
    id_local integer NOT NULL,
    estado character varying(30) DEFAULT 'PREPARADO'::character varying NOT NULL,
    solicitud jsonb NOT NULL,
    proveedor_id character varying(80),
    recurso character varying(10) NOT NULL,
    traza uuid NOT NULL,
    error_codigo character varying(80),
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: grupo_salsa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupo_salsa (
    id_grupo_salsa integer NOT NULL,
    id_presentacion_venta integer NOT NULL,
    cantidad_maxima smallint NOT NULL,
    permite_repetir boolean DEFAULT false NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT grupo_salsa_cantidad_maxima_check CHECK ((cantidad_maxima > 0))
);


--
-- Name: grupo_salsa_id_grupo_salsa_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grupo_salsa ALTER COLUMN id_grupo_salsa ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.grupo_salsa_id_grupo_salsa_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grupo_salsa_opcion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupo_salsa_opcion (
    id_grupo_salsa_opcion integer NOT NULL,
    id_grupo_salsa integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT grupo_salsa_opcion_cantidad_check CHECK ((cantidad > (0)::numeric))
);


--
-- Name: grupo_salsa_opcion_id_grupo_salsa_opcion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grupo_salsa_opcion ALTER COLUMN id_grupo_salsa_opcion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.grupo_salsa_opcion_id_grupo_salsa_opcion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ia_consumo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ia_consumo (
    id uuid NOT NULL,
    id_usuario integer NOT NULL,
    id_perfil integer NOT NULL,
    id_local integer NOT NULL,
    dia date NOT NULL,
    mes date NOT NULL,
    modelo character varying(150) NOT NULL,
    reservado bigint NOT NULL,
    entrada bigint,
    salida bigint,
    total bigint NOT NULL,
    estado character varying(16) NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    terminado_en timestamp with time zone,
    CONSTRAINT ia_consumo_estado_check CHECK (((estado)::text = ANY ((ARRAY['RESERVADO'::character varying, 'CONFIRMADO'::character varying, 'INCIERTO'::character varying, 'LIBERADO'::character varying])::text[]))),
    CONSTRAINT ia_consumo_reservado_check CHECK ((reservado >= 0)),
    CONSTRAINT ia_consumo_total_check CHECK ((total >= 0))
);


--
-- Name: ia_cuota_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ia_cuota_auditoria (
    id bigint NOT NULL,
    administrador integer NOT NULL,
    id_usuario integer,
    anterior jsonb NOT NULL,
    nuevo jsonb NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ia_cuota_auditoria_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ia_cuota_auditoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ia_cuota_auditoria_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ia_cuota_auditoria_id_seq OWNED BY public.ia_cuota_auditoria.id;


--
-- Name: ia_cuota_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ia_cuota_config (
    id integer NOT NULL,
    activo boolean DEFAULT false NOT NULL,
    diario bigint,
    mensual bigint,
    global_diario bigint,
    global_mensual bigint,
    actualizado_por integer,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    consultas_habilitadas boolean DEFAULT true NOT NULL,
    CONSTRAINT ia_cuota_config_diario_check CHECK ((diario >= 0)),
    CONSTRAINT ia_cuota_config_global_diario_check CHECK ((global_diario >= 0)),
    CONSTRAINT ia_cuota_config_global_mensual_check CHECK ((global_mensual >= 0)),
    CONSTRAINT ia_cuota_config_id_check CHECK ((id = 1)),
    CONSTRAINT ia_cuota_config_mensual_check CHECK ((mensual >= 0))
);


--
-- Name: ia_cuota_usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ia_cuota_usuario (
    id_usuario integer NOT NULL,
    diario bigint,
    mensual bigint,
    actualizado_por integer NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ia_cuota_usuario_diario_check CHECK ((diario >= 0)),
    CONSTRAINT ia_cuota_usuario_mensual_check CHECK ((mensual >= 0))
);


--
-- Name: inventario_asignacion_puesto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_asignacion_puesto (
    id_local integer NOT NULL,
    id_producto integer NOT NULL,
    id_puesto_laboral integer NOT NULL,
    actualizado_por integer NOT NULL,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: inventario_cierre; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre (
    id_inventario_cierre integer NOT NULL,
    fecha_inventario date NOT NULL,
    estado_inventario character varying(20) DEFAULT 'BORRADOR'::character varying NOT NULL,
    usuario_registro integer NOT NULL,
    fecha_registro timestamp without time zone,
    usuario_revision integer,
    motivo_revision character varying(150),
    observacion character varying(500),
    id_local integer NOT NULL,
    CONSTRAINT ck_inventario_estado CHECK (((estado_inventario)::text = ANY ((ARRAY['BORRADOR'::character varying, 'CERRADO'::character varying, 'INCOMPLETO'::character varying])::text[]))),
    CONSTRAINT ck_inventario_fecha_registro CHECK (((((estado_inventario)::text = 'CERRADO'::text) AND (fecha_registro IS NOT NULL)) OR (((estado_inventario)::text = ANY (ARRAY[('BORRADOR'::character varying)::text, ('INCOMPLETO'::character varying)::text])) AND (fecha_registro IS NULL)))),
    CONSTRAINT ck_inventario_revision CHECK ((((usuario_revision IS NULL) AND (motivo_revision IS NULL) AND (observacion IS NULL)) OR ((usuario_revision IS NOT NULL) AND (motivo_revision IS NOT NULL) AND (observacion IS NOT NULL))))
);


--
-- Name: COLUMN inventario_cierre.id_local; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventario_cierre.id_local IS 'Local propietario. Obligatorio tras completar la migracion por local.';


--
-- Name: inventario_cierre_correccion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre_correccion (
    id_inventario_cierre_correccion bigint CONSTRAINT inventario_cierre_correccio_id_inventario_cierre_corre_not_null NOT NULL,
    id_inventario_cierre integer NOT NULL,
    usuario_correccion integer NOT NULL,
    motivo_correccion character varying(100) NOT NULL,
    observacion character varying(500) NOT NULL,
    fecha_correccion timestamp without time zone DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'::text) NOT NULL,
    CONSTRAINT ck_correccion_motivo CHECK ((btrim((motivo_correccion)::text) <> ''::text)),
    CONSTRAINT ck_correccion_observacion CHECK ((btrim((observacion)::text) <> ''::text))
);


--
-- Name: inventario_cierre_correccion_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre_correccion_detalle (
    id_inventario_cierre_correccion_detalle bigint CONSTRAINT inventario_cierre_correcci_id_inventario_cierre_corre_not_null1 NOT NULL,
    id_inventario_cierre_correccion bigint CONSTRAINT inventario_cierre_correcci_id_inventario_cierre_corre_not_null2 NOT NULL,
    id_producto integer NOT NULL,
    stock_anterior numeric,
    stock_nuevo numeric,
    CONSTRAINT ck_correccion_stock_anterior CHECK (((stock_anterior IS NULL) OR (stock_anterior >= (0)::numeric))),
    CONSTRAINT ck_correccion_stock_nuevo CHECK (((stock_nuevo IS NULL) OR (stock_nuevo >= (0)::numeric))),
    CONSTRAINT ck_correccion_valores_diferentes CHECK ((stock_anterior IS DISTINCT FROM stock_nuevo))
);


--
-- Name: inventario_cierre_correccion__id_inventario_cierre_correcci_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre_correccion_detalle ALTER COLUMN id_inventario_cierre_correccion_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_correccion__id_inventario_cierre_correcci_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_cierre_correccion_id_inventario_cierre_correccio_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre_correccion ALTER COLUMN id_inventario_cierre_correccion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_correccion_id_inventario_cierre_correccio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_cierre_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre_detalle (
    id_inventario_cierre_detalle integer NOT NULL,
    id_inventario_cierre integer NOT NULL,
    id_producto integer NOT NULL,
    stock_contado numeric(12,3) NOT NULL,
    CONSTRAINT ck_inventario_stock CHECK ((stock_contado >= (0)::numeric))
);


--
-- Name: inventario_cierre_detalle_id_inventario_cierre_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre_detalle ALTER COLUMN id_inventario_cierre_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_detalle_id_inventario_cierre_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_cierre_id_inventario_cierre_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre ALTER COLUMN id_inventario_cierre ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_id_inventario_cierre_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_conteo_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_conteo_historial (
    id_historial bigint NOT NULL,
    id_ronda bigint NOT NULL,
    id_producto integer NOT NULL,
    id_usuario integer NOT NULL,
    accion character varying(20) NOT NULL,
    anterior jsonb NOT NULL,
    nuevo jsonb NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: inventario_conteo_historial_id_historial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_conteo_historial ALTER COLUMN id_historial ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_conteo_historial_id_historial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_evento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_evento (
    id_evento bigint NOT NULL,
    id_local integer NOT NULL,
    id_jornada bigint NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(18,3) NOT NULL,
    motivo character varying(40) NOT NULL,
    origen character varying(30) NOT NULL,
    id_origen bigint NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT inventario_evento_cantidad_check CHECK ((cantidad <> (0)::numeric))
);


--
-- Name: inventario_evento_id_evento_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_evento ALTER COLUMN id_evento ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_evento_id_evento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_jornada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_jornada (
    id_jornada bigint NOT NULL,
    id_local integer NOT NULL,
    fecha date NOT NULL,
    abierto_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    cerrado_en timestamp with time zone,
    abierto_por integer,
    cerrado_por integer,
    reporte jsonb,
    CONSTRAINT inventario_jornada_check CHECK ((((cerrado_en IS NULL) AND (reporte IS NULL)) OR ((cerrado_en IS NOT NULL) AND (reporte IS NOT NULL))))
);


--
-- Name: inventario_jornada_id_jornada_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_jornada ALTER COLUMN id_jornada ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_jornada_id_jornada_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_jornada_inicio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_jornada_inicio (
    id_jornada bigint NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(18,3) NOT NULL
);


--
-- Name: inventario_ronda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_ronda (
    id_ronda bigint NOT NULL,
    id_local integer NOT NULL,
    nombre character varying(120) NOT NULL,
    creado_por integer NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    cerrado_en timestamp with time zone,
    por_puesto boolean DEFAULT false NOT NULL
);


--
-- Name: inventario_ronda_id_ronda_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_ronda ALTER COLUMN id_ronda ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_ronda_id_ronda_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_saldo_inicial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_saldo_inicial (
    id_local integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(18,3) NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: producto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto (
    id_producto integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(200) NOT NULL,
    id_categoria integer NOT NULL,
    id_proveedor integer NOT NULL,
    unidad character varying(10) NOT NULL,
    stock_minimo numeric(12,3) DEFAULT 0 NOT NULL,
    presentacion numeric(12,3) DEFAULT 1 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_producto_codigo CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT ck_producto_presentacion CHECK ((presentacion > (0)::numeric)),
    CONSTRAINT ck_producto_stock_minimo CHECK ((stock_minimo >= (0)::numeric))
);


--
-- Name: inventario_stock_teorico; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.inventario_stock_teorico AS
 SELECT l.id_local,
    p.id_producto,
    COALESCE(b.cantidad, (0)::numeric) AS inicial,
    COALESCE(e.cantidad, (0)::numeric) AS variacion,
    (COALESCE(b.cantidad, (0)::numeric) + COALESCE(e.cantidad, (0)::numeric)) AS stock_actual
   FROM (((public.local l
     CROSS JOIN public.producto p)
     LEFT JOIN public.inventario_saldo_inicial b USING (id_local, id_producto))
     LEFT JOIN ( SELECT inventario_evento.id_local,
            inventario_evento.id_producto,
            sum(inventario_evento.cantidad) AS cantidad
           FROM public.inventario_evento
          GROUP BY inventario_evento.id_local, inventario_evento.id_producto) e USING (id_local, id_producto));


--
-- Name: item_carta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_carta (
    id_item_carta integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(200) NOT NULL,
    id_categoria_carta integer NOT NULL,
    tipo character varying(15) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_item_carta_codigo CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT ck_item_carta_tipo CHECK (((tipo)::text = ANY ((ARRAY['DIRECTO'::character varying, 'PORCIONADO'::character varying, 'PREPARADO'::character varying])::text[])))
);


--
-- Name: item_carta_id_item_carta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.item_carta ALTER COLUMN id_item_carta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.item_carta_id_item_carta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: local_id_local_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.local_id_local_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: local_id_local_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.local_id_local_seq OWNED BY public.local.id_local;


--
-- Name: menaje; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menaje (
    id_menaje integer NOT NULL,
    nombre character varying(100) NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: menaje_id_menaje_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.menaje ALTER COLUMN id_menaje ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.menaje_id_menaje_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: menaje_medida; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menaje_medida (
    id_menaje integer NOT NULL,
    capacidad numeric,
    unidad_capacidad character varying(16),
    diametro_cm numeric,
    altura_cm numeric,
    largo_cm numeric,
    ancho_cm numeric,
    origen_medidas character varying(16),
    CONSTRAINT ck_menaje_medidas CHECK (((capacidad IS NULL) = (unidad_capacidad IS NULL))),
    CONSTRAINT ck_menaje_rectangular CHECK (((origen_medidas)::text = ANY ((ARRAY['DEMO'::character varying, 'REGISTRADO'::character varying])::text[])))
);


--
-- Name: menaje_regla_medida; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menaje_regla_medida (
    campo text NOT NULL,
    etiqueta text NOT NULL,
    maximo numeric NOT NULL,
    decimales smallint NOT NULL,
    CONSTRAINT menaje_regla_medida_decimales_check CHECK (((decimales >= 0) AND (decimales <= 12))),
    CONSTRAINT menaje_regla_medida_maximo_check CHECK (((maximo > (0)::numeric) AND (maximo < 'Infinity'::numeric)))
);


--
-- Name: menaje_unidad_capacidad; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menaje_unidad_capacidad (
    codigo character varying(16) NOT NULL,
    nombre text NOT NULL,
    factor numeric NOT NULL,
    visible boolean DEFAULT true NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    alias text,
    CONSTRAINT menaje_unidad_capacidad_factor_check CHECK ((factor > (0)::numeric))
);


--
-- Name: menu_requiere_perfil_operativo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_requiere_perfil_operativo (
    id_opcion_menu integer NOT NULL
);


--
-- Name: movimiento_inventario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_inventario (
    id_movimiento_inventario integer NOT NULL,
    codigo character varying(20) NOT NULL,
    tipo_movimiento character varying(10) NOT NULL,
    motivo_movimiento character varying(30) NOT NULL,
    fecha_movimiento date NOT NULL,
    usuario_registro integer NOT NULL,
    local_relacionado character varying(150),
    id_proveedor integer,
    observacion character varying(500),
    id_local integer NOT NULL,
    registrado_en timestamp without time zone DEFAULT (clock_timestamp() AT TIME ZONE 'America/Lima'::text),
    CONSTRAINT ck_movimiento_local CHECK (((local_relacionado IS NULL) OR (btrim((local_relacionado)::text) <> ''::text))),
    CONSTRAINT ck_movimiento_tipo CHECK (((tipo_movimiento)::text = ANY ((ARRAY['ENTRADA'::character varying, 'SALIDA'::character varying])::text[])))
);


--
-- Name: COLUMN movimiento_inventario.id_local; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.movimiento_inventario.id_local IS 'Local propietario, distinto de la contraparte local_relacionado.';


--
-- Name: movimiento_inventario_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_inventario_detalle (
    id_movimiento_inventario_detalle integer CONSTRAINT movimiento_inventario_detal_id_movimiento_inventario_d_not_null NOT NULL,
    id_movimiento_inventario integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(12,3) NOT NULL,
    CONSTRAINT ck_movimiento_cantidad CHECK ((cantidad > (0)::numeric))
);


--
-- Name: movimiento_inventario_detalle_id_movimiento_inventario_deta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.movimiento_inventario_detalle ALTER COLUMN id_movimiento_inventario_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.movimiento_inventario_detalle_id_movimiento_inventario_deta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimiento_inventario_id_movimiento_inventario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.movimiento_inventario ALTER COLUMN id_movimiento_inventario ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.movimiento_inventario_id_movimiento_inventario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimiento_motivo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_motivo (
    codigo character varying(30) NOT NULL,
    etiqueta text NOT NULL,
    tipo_movimiento character varying(10) NOT NULL,
    requiere_local boolean DEFAULT false NOT NULL,
    requiere_proveedor boolean DEFAULT false NOT NULL,
    registrable boolean DEFAULT true NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    motivo_recepcion character varying(30),
    CONSTRAINT movimiento_motivo_check CHECK ((NOT (requiere_local AND requiere_proveedor))),
    CONSTRAINT movimiento_motivo_check1 CHECK (((motivo_recepcion IS NULL) OR (((tipo_movimiento)::text = 'SALIDA'::text) AND (requiere_local OR requiere_proveedor)))),
    CONSTRAINT movimiento_motivo_codigo_check CHECK ((((codigo)::text <> ''::text) AND ((codigo)::text = upper(btrim((codigo)::text))))),
    CONSTRAINT movimiento_motivo_tipo_movimiento_check CHECK (((tipo_movimiento)::text = ANY ((ARRAY['ENTRADA'::character varying, 'SALIDA'::character varying])::text[])))
);


--
-- Name: movimiento_reintegro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_reintegro (
    id_movimiento integer NOT NULL,
    id_salida integer NOT NULL,
    guia_proveedor character varying(100),
    registrado_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: movimiento_seguimiento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_seguimiento (
    id_movimiento integer NOT NULL,
    id_local_destino integer,
    estado character varying(30) NOT NULL,
    CONSTRAINT movimiento_seguimiento_check CHECK ((((id_local_destino IS NOT NULL) AND ((estado)::text = ANY ((ARRAY['PENDIENTE_RECEPCION'::character varying, 'ACEPTADO'::character varying])::text[]))) OR ((id_local_destino IS NULL) AND ((estado)::text = ANY ((ARRAY['DEVUELTO'::character varying, 'REINTEGRO_PARCIAL'::character varying, 'REINTEGRADO'::character varying])::text[]))))),
    CONSTRAINT movimiento_seguimiento_estado_check CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE_RECEPCION'::character varying, 'ACEPTADO'::character varying, 'DEVUELTO'::character varying, 'REINTEGRO_PARCIAL'::character varying, 'REINTEGRADO'::character varying])::text[])))
);


--
-- Name: opcion_menu; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opcion_menu (
    id_opcion_menu integer NOT NULL,
    nombre character varying(100) NOT NULL,
    url_menu character varying(180),
    descripcion character varying(500) NOT NULL,
    id_padre integer,
    estado_registro smallint DEFAULT 1 NOT NULL,
    codigo character varying(60) NOT NULL,
    icono character varying(80),
    tipo_opcion character varying(15) DEFAULT 'ENLACE'::character varying NOT NULL,
    es_configurable boolean DEFAULT true NOT NULL,
    usuario_creacion integer,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    CONSTRAINT ck_opcion_menu_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_opcion_menu_tipo CHECK (((tipo_opcion)::text = ANY ((ARRAY['GRUPO'::character varying, 'ENLACE'::character varying])::text[])))
);


--
-- Name: opcion_menu_id_opcion_menu_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opcion_menu ALTER COLUMN id_opcion_menu ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opcion_menu_id_opcion_menu_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orden_compra; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orden_compra (
    id_orden_compra integer NOT NULL,
    codigo character varying(20) NOT NULL,
    estado_orden_compra character varying(25) DEFAULT 'BORRADOR'::character varying NOT NULL,
    usuario_registro integer NOT NULL,
    fecha_registro date,
    motivo_cierre character varying(500),
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    id_local integer NOT NULL,
    CONSTRAINT ck_orden_estado CHECK (((estado_orden_compra)::text = ANY ((ARRAY['BORRADOR'::character varying, 'ENVIADA'::character varying, 'RECEPCION_PARCIAL'::character varying, 'RECEPCIONADA'::character varying, 'CERRADA_INCOMPLETA'::character varying, 'CANCELADA'::character varying])::text[]))),
    CONSTRAINT ck_orden_fecha CHECK (((((estado_orden_compra)::text = 'BORRADOR'::text) AND (fecha_registro IS NULL)) OR (((estado_orden_compra)::text <> 'BORRADOR'::text) AND (fecha_registro IS NOT NULL))))
);


--
-- Name: COLUMN orden_compra.id_local; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orden_compra.id_local IS 'Local propietario; las recepciones heredan el local de esta orden.';


--
-- Name: orden_compra_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orden_compra_detalle (
    id_orden_compra_detalle integer NOT NULL,
    id_orden_compra integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad_solicitada numeric(12,3) NOT NULL,
    id_proveedor integer NOT NULL,
    CONSTRAINT ck_orden_cantidad CHECK ((cantidad_solicitada > (0)::numeric))
);


--
-- Name: COLUMN orden_compra_detalle.id_proveedor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orden_compra_detalle.id_proveedor IS 'Proveedor pactado en esta linea, independiente del proveedor actual del producto.';


--
-- Name: orden_compra_detalle_id_orden_compra_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orden_compra_detalle ALTER COLUMN id_orden_compra_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orden_compra_detalle_id_orden_compra_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orden_compra_estado_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orden_compra_estado_historial (
    id_orden_compra_estado_historial bigint CONSTRAINT orden_compra_estado_histori_id_orden_compra_estado_his_not_null NOT NULL,
    id_orden_compra integer NOT NULL,
    estado_anterior character varying(30) NOT NULL,
    estado_nuevo character varying(30) NOT NULL,
    motivo character varying(500) NOT NULL,
    usuario_modificacion integer NOT NULL,
    fecha_modificacion timestamp without time zone DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'::text) NOT NULL,
    CONSTRAINT ck_oceh_estados_diferentes CHECK (((estado_anterior)::text <> (estado_nuevo)::text)),
    CONSTRAINT ck_oceh_motivo CHECK ((btrim((motivo)::text) <> ''::text))
);


--
-- Name: orden_compra_estado_historial_id_orden_compra_estado_histor_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orden_compra_estado_historial ALTER COLUMN id_orden_compra_estado_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orden_compra_estado_historial_id_orden_compra_estado_histor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orden_compra_id_orden_compra_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orden_compra ALTER COLUMN id_orden_compra ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orden_compra_id_orden_compra_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: perfil_capacidad; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfil_capacidad (
    id_perfil integer NOT NULL,
    capacidad text NOT NULL
);


--
-- Name: perfil_gestion_usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfil_gestion_usuario (
    id_perfil_gestor integer NOT NULL,
    id_perfil_objetivo integer NOT NULL,
    puede_crear boolean DEFAULT false NOT NULL,
    puede_editar boolean DEFAULT false NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    CONSTRAINT ck_perfil_gestion_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: perfil_opcion_menu; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfil_opcion_menu (
    id_perfil integer NOT NULL,
    id_opcion_menu integer NOT NULL,
    puede_consultar boolean DEFAULT false NOT NULL,
    puede_crear boolean DEFAULT false NOT NULL,
    puede_editar boolean DEFAULT false NOT NULL,
    puede_revisar boolean DEFAULT false NOT NULL,
    puede_cerrar boolean DEFAULT false NOT NULL,
    orden smallint NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    puede_desactivar boolean DEFAULT false NOT NULL,
    puede_reactivar boolean DEFAULT false NOT NULL,
    puede_eliminar boolean DEFAULT false NOT NULL,
    puede_configurar boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_perfil_opcion_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_perfil_opcion_orden CHECK ((orden > 0))
);


--
-- Name: perfiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfiles (
    id_perfil integer NOT NULL,
    nombre character varying(60) NOT NULL,
    descripcion character varying(500) NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    acceso_todos_locales boolean DEFAULT false NOT NULL,
    requiere_puesto_activo boolean DEFAULT false NOT NULL,
    puede_cambiar_local boolean DEFAULT false NOT NULL,
    administra_catalogos_carta boolean DEFAULT false NOT NULL,
    administra_limites_stock boolean DEFAULT false NOT NULL,
    accede_directorio_clientes boolean DEFAULT false NOT NULL,
    accede_clientes_salon boolean DEFAULT false NOT NULL,
    ve_escalado_fact_api boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_perfiles_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: perfiles_id_perfil_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.perfiles ALTER COLUMN id_perfil ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.perfiles_id_perfil_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: permiso_accion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permiso_accion (
    accion text NOT NULL,
    campo text NOT NULL
);


--
-- Name: permiso_recurso; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permiso_recurso (
    recurso text NOT NULL,
    id_opcion_menu integer NOT NULL
);


--
-- Name: presentacion_venta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.presentacion_venta (
    id_presentacion_venta integer NOT NULL,
    id_item_carta integer NOT NULL,
    id_menaje integer NOT NULL,
    contenido numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    precio numeric(10,2) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_presentacion_venta_contenido CHECK ((contenido > (0)::numeric)),
    CONSTRAINT ck_presentacion_venta_precio CHECK ((precio >= (0)::numeric))
);


--
-- Name: presentacion_venta_id_presentacion_venta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.presentacion_venta ALTER COLUMN id_presentacion_venta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.presentacion_venta_id_presentacion_venta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_categoria_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto_categoria_historial (
    id_producto_categoria_historial bigint CONSTRAINT producto_categoria_historia_id_producto_categoria_hist_not_null NOT NULL,
    id_producto integer NOT NULL,
    id_categoria_anterior integer NOT NULL,
    id_categoria_nueva integer NOT NULL,
    usuario_cambio integer NOT NULL,
    fecha_cambio timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    motivo character varying(500) NOT NULL,
    CONSTRAINT ck_producto_categoria_historial_diferentes CHECK ((id_categoria_anterior <> id_categoria_nueva)),
    CONSTRAINT ck_producto_categoria_historial_motivo CHECK (((length(btrim((motivo)::text)) >= 10) AND (length(btrim((motivo)::text)) <= 500)))
);


--
-- Name: producto_categoria_historial_id_producto_categoria_historia_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.producto_categoria_historial ALTER COLUMN id_producto_categoria_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.producto_categoria_historial_id_producto_categoria_historia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_id_producto_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.producto ALTER COLUMN id_producto ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.producto_id_producto_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_proveedor_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto_proveedor_historial (
    id_producto_proveedor_historial bigint CONSTRAINT producto_proveedor_historia_id_producto_proveedor_hist_not_null NOT NULL,
    id_producto integer NOT NULL,
    id_proveedor_anterior integer NOT NULL,
    id_proveedor_nuevo integer NOT NULL,
    usuario_cambio integer NOT NULL,
    fecha_cambio timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    motivo character varying(500) NOT NULL,
    CONSTRAINT ck_producto_proveedor_historial_diferentes CHECK ((id_proveedor_anterior <> id_proveedor_nuevo)),
    CONSTRAINT ck_producto_proveedor_historial_motivo CHECK (((length(btrim((motivo)::text)) >= 10) AND (length(btrim((motivo)::text)) <= 500)))
);


--
-- Name: producto_proveedor_historial_id_producto_proveedor_historia_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.producto_proveedor_historial ALTER COLUMN id_producto_proveedor_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.producto_proveedor_historial_id_producto_proveedor_historia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_stock_local; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto_stock_local (
    id_producto integer NOT NULL,
    id_local integer NOT NULL,
    stock_minimo numeric(12,3) DEFAULT 0 NOT NULL,
    stock_maximo numeric(12,3),
    CONSTRAINT ck_stock_local_minimo CHECK ((stock_minimo >= (0)::numeric))
);


--
-- Name: promocion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promocion (
    id_promocion integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(150) NOT NULL,
    precio numeric(10,2) NOT NULL,
    hora_inicio time without time zone,
    hora_fin time without time zone,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_promocion_horario CHECK ((((hora_inicio IS NULL) AND (hora_fin IS NULL)) OR ((hora_inicio IS NOT NULL) AND (hora_fin IS NOT NULL)))),
    CONSTRAINT promocion_codigo_check CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT promocion_precio_check CHECK ((precio >= (0)::numeric))
);


--
-- Name: promocion_grupo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promocion_grupo (
    id_promocion_grupo integer NOT NULL,
    id_promocion integer NOT NULL,
    cantidad_elegir smallint NOT NULL,
    permite_repetir boolean DEFAULT false NOT NULL,
    CONSTRAINT promocion_grupo_cantidad_elegir_check CHECK ((cantidad_elegir > 0))
);


--
-- Name: promocion_grupo_id_promocion_grupo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.promocion_grupo ALTER COLUMN id_promocion_grupo ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promocion_grupo_id_promocion_grupo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: promocion_id_promocion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.promocion ALTER COLUMN id_promocion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promocion_id_promocion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: promocion_opcion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promocion_opcion (
    id_promocion_opcion integer NOT NULL,
    id_promocion_grupo integer NOT NULL,
    id_presentacion_venta integer NOT NULL
);


--
-- Name: promocion_opcion_id_promocion_opcion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.promocion_opcion ALTER COLUMN id_promocion_opcion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promocion_opcion_id_promocion_opcion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: promocion_reposicion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promocion_reposicion (
    id_promocion integer NOT NULL,
    id_presentacion_venta integer NOT NULL
);


--
-- Name: proveedor; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proveedor (
    id_proveedor integer NOT NULL,
    nombre character varying(200) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    datos_comerciales jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: proveedor_campo_comercial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proveedor_campo_comercial (
    campo text NOT NULL,
    longitud_maxima integer NOT NULL,
    CONSTRAINT proveedor_campo_comercial_longitud_maxima_check CHECK ((longitud_maxima > 0))
);


--
-- Name: proveedor_categoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proveedor_categoria (
    id_proveedor integer NOT NULL,
    id_categoria integer NOT NULL
);


--
-- Name: proveedor_id_proveedor_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.proveedor ALTER COLUMN id_proveedor ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.proveedor_id_proveedor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: puesto_laboral; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.puesto_laboral (
    id_puesto_laboral integer NOT NULL,
    nombre character varying(80) NOT NULL,
    descripcion character varying(250),
    estado_registro smallint DEFAULT 1 NOT NULL,
    usuario_creacion integer,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    CONSTRAINT ck_puesto_laboral_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: puesto_laboral_id_puesto_laboral_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.puesto_laboral ALTER COLUMN id_puesto_laboral ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.puesto_laboral_id_puesto_laboral_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recepcion_motivo_correccion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recepcion_motivo_correccion (
    codigo text NOT NULL,
    etiqueta text NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_recepcion_motivo_codigo_longitud CHECK ((char_length(codigo) <= 100)),
    CONSTRAINT recepcion_motivo_correccion_codigo_check CHECK (((codigo <> ''::text) AND (codigo = upper(btrim(codigo)))))
);


--
-- Name: receta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receta (
    id_receta integer NOT NULL,
    id_presentacion_venta integer NOT NULL,
    instrucciones text DEFAULT 'Pendiente de registrar.'::text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_receta_instrucciones CHECK ((length(btrim(instrucciones)) > 0))
);


--
-- Name: receta_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receta_detalle (
    id_receta_detalle integer NOT NULL,
    id_receta integer NOT NULL,
    tipo_componente character varying(15) NOT NULL,
    id_producto integer,
    id_subproducto integer,
    cantidad numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    CONSTRAINT ck_receta_detalle_cantidad CHECK ((cantidad > (0)::numeric)),
    CONSTRAINT ck_receta_detalle_componente CHECK (((((tipo_componente)::text = 'PRODUCTO'::text) AND (id_producto IS NOT NULL) AND (id_subproducto IS NULL)) OR (((tipo_componente)::text = 'SUBPRODUCTO'::text) AND (id_producto IS NULL) AND (id_subproducto IS NOT NULL)))),
    CONSTRAINT ck_receta_detalle_tipo CHECK (((tipo_componente)::text = ANY ((ARRAY['PRODUCTO'::character varying, 'SUBPRODUCTO'::character varying])::text[])))
);


--
-- Name: receta_detalle_id_receta_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.receta_detalle ALTER COLUMN id_receta_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.receta_detalle_id_receta_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: receta_id_receta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.receta ALTER COLUMN id_receta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.receta_id_receta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salon_autorizacion_usada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_autorizacion_usada (
    clave uuid NOT NULL,
    fecha timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: salon_cierre_diario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_cierre_diario (
    id_local integer NOT NULL,
    fecha date NOT NULL,
    registrado_en timestamp with time zone DEFAULT now() NOT NULL,
    simulacion boolean DEFAULT false NOT NULL,
    cantidad integer NOT NULL,
    efectivo numeric(14,2) NOT NULL,
    tarjeta numeric(14,2) NOT NULL,
    CONSTRAINT salon_cierre_diario_cantidad_check CHECK ((cantidad >= 0)),
    CONSTRAINT salon_cierre_diario_efectivo_check CHECK ((efectivo >= (0)::numeric)),
    CONSTRAINT salon_cierre_diario_id_local_check CHECK ((id_local > 0)),
    CONSTRAINT salon_cierre_diario_tarjeta_check CHECK ((tarjeta >= (0)::numeric))
);


--
-- Name: salon_cobro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_cobro (
    id_cobro bigint NOT NULL,
    id_local integer NOT NULL,
    id_usuario integer NOT NULL,
    mesa character varying(4) NOT NULL,
    clave uuid NOT NULL,
    solicitud_hash character varying(64) NOT NULL,
    tipo character varying(20) NOT NULL,
    metodo character varying(10) NOT NULL,
    documento character varying(11) DEFAULT ''::character varying NOT NULL,
    cliente character varying(200) DEFAULT ''::character varying NOT NULL,
    total numeric(12,2) NOT NULL,
    comprobante jsonb NOT NULL,
    id_movimiento integer NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    id_jornada bigint,
    id_cliente uuid,
    CONSTRAINT salon_cobro_check CHECK (((((tipo)::text = 'BOLETA'::text) AND ((documento)::text = ''::text) AND ((cliente)::text = ''::text)) OR (((tipo)::text = 'BOLETA_ELECTRONICA'::text) AND ((documento)::text ~ '^[0-9]{8}$'::text) AND (length(btrim((cliente)::text)) > 0)) OR (((tipo)::text = 'FACTURA'::text) AND ((documento)::text ~ '^[0-9]{11}$'::text) AND (length(btrim((cliente)::text)) > 0)))),
    CONSTRAINT salon_cobro_metodo_check CHECK (((metodo)::text = ANY ((ARRAY['EFECTIVO'::character varying, 'TARJETA'::character varying])::text[]))),
    CONSTRAINT salon_cobro_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['BOLETA'::character varying, 'BOLETA_ELECTRONICA'::character varying, 'FACTURA'::character varying])::text[]))),
    CONSTRAINT salon_cobro_total_check CHECK ((total >= (0)::numeric))
);


--
-- Name: salon_cobro_id_cobro_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.salon_cobro ALTER COLUMN id_cobro ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salon_cobro_id_cobro_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salon_cobro_pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_cobro_pedido (
    id_pedido bigint NOT NULL,
    id_cobro bigint NOT NULL
);


--
-- Name: salon_distribucion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_distribucion (
    id_local integer NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    elementos jsonb NOT NULL,
    CONSTRAINT salon_distribucion_elementos_check CHECK ((jsonb_typeof(elementos) = 'array'::text)),
    CONSTRAINT salon_distribucion_version_check CHECK ((version > 0))
);


--
-- Name: salon_intentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_intentos (
    origen character varying(64) NOT NULL,
    inicio timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    intentos integer DEFAULT 0 NOT NULL
);


--
-- Name: salon_linea_anulada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_linea_anulada (
    id_linea bigint NOT NULL,
    id_responsable integer NOT NULL,
    fecha timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: salon_pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_pedido (
    id_pedido bigint NOT NULL,
    id_local integer NOT NULL,
    mesa character varying(4) NOT NULL,
    id_usuario integer NOT NULL,
    estado character varying(10) DEFAULT 'BORRADOR'::character varying NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    creado_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    enviado_en timestamp with time zone,
    envio_clave uuid,
    envio_hash character varying(64),
    CONSTRAINT salon_pedido_check CHECK (((((estado)::text = 'BORRADOR'::text) AND (enviado_en IS NULL)) OR (((estado)::text = 'ENVIADO'::text) AND (enviado_en IS NOT NULL)))),
    CONSTRAINT salon_pedido_estado_check CHECK (((estado)::text = ANY ((ARRAY['BORRADOR'::character varying, 'ENVIADO'::character varying])::text[]))),
    CONSTRAINT salon_pedido_mesa_check CHECK (((mesa)::text ~ '^[MB][0-9]{2,3}$'::text))
);


--
-- Name: salon_pedido_asignacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_pedido_asignacion (
    id_pedido bigint NOT NULL,
    mesa character varying(4) NOT NULL,
    id_usuario integer NOT NULL,
    CONSTRAINT salon_pedido_asignacion_mesa_check CHECK (((mesa)::text ~ '^[MB][0-9]{2,3}$'::text))
);


--
-- Name: salon_pedido_actual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.salon_pedido_actual AS
 SELECT p.id_pedido,
    p.id_local,
    COALESCE(a.mesa, p.mesa) AS mesa,
    COALESCE(a.id_usuario, p.id_usuario) AS id_usuario,
    p.estado,
    p.version,
    p.creado_en,
    p.enviado_en,
    p.envio_clave,
    p.envio_hash
   FROM (public.salon_pedido p
     LEFT JOIN public.salon_pedido_asignacion a USING (id_pedido))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.salon_cobro_pedido c
          WHERE (c.id_pedido = p.id_pedido))));


--
-- Name: salon_pedido_id_pedido_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.salon_pedido ALTER COLUMN id_pedido ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salon_pedido_id_pedido_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salon_pedido_linea; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_pedido_linea (
    id_linea bigint NOT NULL,
    id_pedido bigint NOT NULL,
    posicion integer NOT NULL,
    id_presentacion integer,
    nombre text NOT NULL,
    precio numeric(10,2) NOT NULL,
    cantidad integer NOT NULL,
    comentario character varying(500) DEFAULT ''::character varying NOT NULL,
    opciones jsonb DEFAULT '[]'::jsonb NOT NULL,
    id_promocion integer,
    selecciones_promocion jsonb DEFAULT '[]'::jsonb NOT NULL,
    id_barra_libre bigint,
    CONSTRAINT ck_salon_linea_tipo CHECK ((((id_presentacion IS NOT NULL) AND (id_promocion IS NULL)) OR ((id_presentacion IS NULL) AND (id_promocion IS NOT NULL) AND (cantidad = 1) AND (id_barra_libre IS NULL)))),
    CONSTRAINT ck_salon_reposicion_gratis CHECK (((id_barra_libre IS NULL) OR ((id_presentacion IS NOT NULL) AND (id_promocion IS NULL) AND (precio = (0)::numeric)))),
    CONSTRAINT salon_pedido_linea_cantidad_check CHECK (((cantidad >= 1) AND (cantidad <= 99))),
    CONSTRAINT salon_pedido_linea_opciones_check CHECK ((jsonb_typeof(opciones) = 'array'::text)),
    CONSTRAINT salon_pedido_linea_precio_check CHECK ((precio >= (0)::numeric)),
    CONSTRAINT salon_pedido_linea_selecciones_promocion_check CHECK ((jsonb_typeof(selecciones_promocion) = 'array'::text))
);


--
-- Name: salon_pedido_linea_id_linea_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.salon_pedido_linea ALTER COLUMN id_linea ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salon_pedido_linea_id_linea_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subproducto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subproducto (
    id_subproducto integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(150) NOT NULL,
    rendimiento numeric(12,3) DEFAULT 1 NOT NULL,
    unidad character varying(10) NOT NULL,
    instruccion text,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_subproducto_codigo CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT ck_subproducto_rendimiento CHECK ((rendimiento > (0)::numeric))
);


--
-- Name: subproducto_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subproducto_detalle (
    id_subproducto_detalle integer NOT NULL,
    id_subproducto integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    CONSTRAINT ck_subproducto_detalle_cantidad CHECK ((cantidad > (0)::numeric))
);


--
-- Name: subproducto_detalle_id_subproducto_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.subproducto_detalle ALTER COLUMN id_subproducto_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.subproducto_detalle_id_subproducto_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subproducto_id_subproducto_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.subproducto ALTER COLUMN id_subproducto ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.subproducto_id_subproducto_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: unidad_medida; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unidad_medida (
    codigo character varying(10) NOT NULL,
    nombre character varying(40) NOT NULL,
    simbolo character varying(10) NOT NULL,
    dimension character varying(10) NOT NULL,
    codigo_unece character varying(3),
    codigo_base character varying(10) NOT NULL,
    factor_a_base numeric(12,6) NOT NULL,
    orden_catalogo integer DEFAULT 0 NOT NULL,
    simbolo_plural text,
    estandar text,
    CONSTRAINT unidad_medida_dimension_check CHECK (((dimension)::text = ANY ((ARRAY['MASA'::character varying, 'VOLUMEN'::character varying, 'CONTEO'::character varying])::text[]))),
    CONSTRAINT unidad_medida_factor_a_base_check CHECK ((factor_a_base > (0)::numeric))
);


--
-- Name: unidad_medida_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unidad_medida_alias (
    alias text NOT NULL,
    codigo character varying(10) NOT NULL
);


--
-- Name: unidad_medida_catalogo_inicializado; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.unidad_medida_catalogo_inicializado AS
 SELECT true AS inicializado;


--
-- Name: unidad_medida_contexto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unidad_medida_contexto (
    contexto text NOT NULL,
    codigo_base character varying(10) NOT NULL
);


--
-- Name: usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario (
    id_usuario integer NOT NULL,
    dni character varying(8) NOT NULL,
    nombres character varying(100) NOT NULL,
    apellido_paterno character varying(80) NOT NULL,
    apellido_materno character varying(80),
    celular character varying(15) NOT NULL,
    correo_electronico character varying(150) NOT NULL,
    clave character varying(255) NOT NULL,
    usuario_creacion integer,
    fecha_creacion date DEFAULT CURRENT_DATE NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion date,
    estado_registro smallint DEFAULT 1 NOT NULL,
    id_puesto_laboral integer,
    CONSTRAINT ck_usuario_celular CHECK (((celular)::text ~ '^[0-9]{9,15}$'::text)),
    CONSTRAINT ck_usuario_correo_corporativo CHECK ((lower(TRIM(BOTH FROM correo_electronico)) ~ '^[a-z0-9][a-z0-9._-]*@barbarian\.pe$'::text)),
    CONSTRAINT ck_usuario_dni CHECK (((dni)::text ~ '^[0-9]{8}$'::text)),
    CONSTRAINT ck_usuario_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_usuario_modificacion CHECK ((((usuario_modificacion IS NULL) AND (fecha_modificacion IS NULL)) OR ((usuario_modificacion IS NOT NULL) AND (fecha_modificacion IS NOT NULL))))
);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.usuario ALTER COLUMN id_usuario ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.usuario_id_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuario_local; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_local (
    id_usuario_local integer NOT NULL,
    id_usuario integer NOT NULL,
    id_local integer NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    fecha_asignacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_asignacion integer,
    fecha_modificacion timestamp without time zone,
    usuario_modificacion integer,
    CONSTRAINT chk_usuario_local_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: usuario_local_id_usuario_local_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuario_local_id_usuario_local_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuario_local_id_usuario_local_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuario_local_id_usuario_local_seq OWNED BY public.usuario_local.id_usuario_local;


--
-- Name: usuario_perfiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_perfiles (
    id_usuario integer NOT NULL,
    id_perfil integer NOT NULL,
    usuario_asignacion integer NOT NULL,
    fecha_asignacion date DEFAULT CURRENT_DATE NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion date,
    estado_registro smallint DEFAULT 1 NOT NULL,
    CONSTRAINT ck_usuario_perfiles_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_usuario_perfiles_modificacion CHECK ((((usuario_modificacion IS NULL) AND (fecha_modificacion IS NULL)) OR ((usuario_modificacion IS NOT NULL) AND (fecha_modificacion IS NOT NULL))))
);


--
-- Name: usuario_pin_salon; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_pin_salon (
    id_usuario integer NOT NULL,
    pin_hash text NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    fallos integer DEFAULT 0 NOT NULL,
    bloqueado_hasta timestamp with time zone,
    actualizado_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: usuario_puestos_laborales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_puestos_laborales (
    id_usuario integer NOT NULL,
    id_puesto_laboral integer NOT NULL,
    usuario_asignacion integer NOT NULL,
    fecha_asignacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    estado_registro smallint DEFAULT 1 NOT NULL,
    CONSTRAINT ck_upl_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: fact_api_intento id_intento; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_intento ALTER COLUMN id_intento SET DEFAULT nextval('public.fact_api_intento_id_intento_seq'::regclass);


--
-- Name: ia_cuota_auditoria id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ia_cuota_auditoria ALTER COLUMN id SET DEFAULT nextval('public.ia_cuota_auditoria_id_seq'::regclass);


--
-- Name: local id_local; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local ALTER COLUMN id_local SET DEFAULT nextval('public.local_id_local_seq'::regclass);


--
-- Name: usuario_local id_usuario_local; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local ALTER COLUMN id_usuario_local SET DEFAULT nextval('public.usuario_local_id_usuario_local_seq'::regclass);


--
-- Name: actividad_usuario actividad_usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT actividad_usuario_pkey PRIMARY KEY (id_actividad_usuario);


--
-- Name: asistente_ia_borrador asistente_ia_borrador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistente_ia_borrador
    ADD CONSTRAINT asistente_ia_borrador_pkey PRIMARY KEY (id);


--
-- Name: asistente_ia_workspace asistente_ia_workspace_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistente_ia_workspace
    ADD CONSTRAINT asistente_ia_workspace_pkey PRIMARY KEY (id_usuario, id_perfil, id_local);


--
-- Name: auditoria_cambio auditoria_cambio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT auditoria_cambio_pkey PRIMARY KEY (id_auditoria_cambio);


--
-- Name: producto_stock_local ck_stock_local_maximo; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.producto_stock_local
    ADD CONSTRAINT ck_stock_local_maximo CHECK (((stock_maximo IS NULL) OR (stock_maximo > stock_minimo))) NOT VALID;


--
-- Name: cliente_comercial cliente_comercial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_comercial
    ADD CONSTRAINT cliente_comercial_pkey PRIMARY KEY (id_cliente);


--
-- Name: configuracion_operativa configuracion_operativa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracion_operativa
    ADD CONSTRAINT configuracion_operativa_pkey PRIMARY KEY (unica);


--
-- Name: fact_api_adjunto fact_api_adjunto_id_local_id_factura_recepcion_sha256_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_adjunto
    ADD CONSTRAINT fact_api_adjunto_id_local_id_factura_recepcion_sha256_key UNIQUE (id_local, id_factura_recepcion, sha256);


--
-- Name: fact_api_adjunto fact_api_adjunto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_adjunto
    ADD CONSTRAINT fact_api_adjunto_pkey PRIMARY KEY (id_adjunto);


--
-- Name: fact_api_adjunto fact_api_adjunto_ruta_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_adjunto
    ADD CONSTRAINT fact_api_adjunto_ruta_key UNIQUE (ruta);


--
-- Name: fact_api_archivo fact_api_archivo_id_documento_formato_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_archivo
    ADD CONSTRAINT fact_api_archivo_id_documento_formato_key UNIQUE (id_documento, formato);


--
-- Name: fact_api_archivo fact_api_archivo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_archivo
    ADD CONSTRAINT fact_api_archivo_pkey PRIMARY KEY (id_archivo);


--
-- Name: fact_api_archivo fact_api_archivo_ruta_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_archivo
    ADD CONSTRAINT fact_api_archivo_ruta_key UNIQUE (ruta);


--
-- Name: fact_api_circuito fact_api_circuito_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_circuito
    ADD CONSTRAINT fact_api_circuito_pkey PRIMARY KEY (id);


--
-- Name: fact_api_config fact_api_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_config
    ADD CONSTRAINT fact_api_config_pkey PRIMARY KEY (id_local);


--
-- Name: fact_api_documento fact_api_documento_id_externo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_documento
    ADD CONSTRAINT fact_api_documento_id_externo_key UNIQUE (id_externo);


--
-- Name: fact_api_documento fact_api_documento_id_operacion_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_documento
    ADD CONSTRAINT fact_api_documento_id_operacion_key UNIQUE (id_operacion);


--
-- Name: fact_api_documento fact_api_documento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_documento
    ADD CONSTRAINT fact_api_documento_pkey PRIMARY KEY (id_documento);


--
-- Name: fact_api_escalado fact_api_escalado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_escalado
    ADD CONSTRAINT fact_api_escalado_pkey PRIMARY KEY (id);


--
-- Name: fact_api_intento fact_api_intento_id_operacion_numero_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_intento
    ADD CONSTRAINT fact_api_intento_id_operacion_numero_key UNIQUE (id_operacion, numero);


--
-- Name: fact_api_intento fact_api_intento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_intento
    ADD CONSTRAINT fact_api_intento_pkey PRIMARY KEY (id_intento);


--
-- Name: fact_api_operacion fact_api_operacion_origen_id_origen_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_operacion
    ADD CONSTRAINT fact_api_operacion_origen_id_origen_version_key UNIQUE (origen, id_origen, version);


--
-- Name: fact_api_operacion fact_api_operacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_operacion
    ADD CONSTRAINT fact_api_operacion_pkey PRIMARY KEY (id_operacion);


--
-- Name: factura_recepcion_detalle factura_recepcion_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT factura_recepcion_detalle_pkey PRIMARY KEY (id_factura_recepcion_detalle);


--
-- Name: factura_recepcion factura_recepcion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT factura_recepcion_pkey PRIMARY KEY (id_factura_recepcion);


--
-- Name: facturacion_comprobante facturacion_comprobante_id_cobro_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facturacion_comprobante
    ADD CONSTRAINT facturacion_comprobante_id_cobro_key UNIQUE (id_cobro);


--
-- Name: facturacion_comprobante facturacion_comprobante_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facturacion_comprobante
    ADD CONSTRAINT facturacion_comprobante_pkey PRIMARY KEY (id);


--
-- Name: grupo_salsa grupo_salsa_id_presentacion_venta_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa
    ADD CONSTRAINT grupo_salsa_id_presentacion_venta_key UNIQUE (id_presentacion_venta);


--
-- Name: grupo_salsa_opcion grupo_salsa_opcion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT grupo_salsa_opcion_pkey PRIMARY KEY (id_grupo_salsa_opcion);


--
-- Name: grupo_salsa grupo_salsa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa
    ADD CONSTRAINT grupo_salsa_pkey PRIMARY KEY (id_grupo_salsa);


--
-- Name: ia_consumo ia_consumo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ia_consumo
    ADD CONSTRAINT ia_consumo_pkey PRIMARY KEY (id);


--
-- Name: ia_cuota_auditoria ia_cuota_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ia_cuota_auditoria
    ADD CONSTRAINT ia_cuota_auditoria_pkey PRIMARY KEY (id);


--
-- Name: ia_cuota_config ia_cuota_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ia_cuota_config
    ADD CONSTRAINT ia_cuota_config_pkey PRIMARY KEY (id);


--
-- Name: ia_cuota_usuario ia_cuota_usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ia_cuota_usuario
    ADD CONSTRAINT ia_cuota_usuario_pkey PRIMARY KEY (id_usuario);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_pkey PRIMARY KEY (id_local, id_producto);


--
-- Name: inventario_cierre_detalle inventario_cierre_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT inventario_cierre_detalle_pkey PRIMARY KEY (id_inventario_cierre_detalle);


--
-- Name: inventario_cierre inventario_cierre_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT inventario_cierre_pkey PRIMARY KEY (id_inventario_cierre);


--
-- Name: inventario_conteo_historial inventario_conteo_historial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo_historial
    ADD CONSTRAINT inventario_conteo_historial_pkey PRIMARY KEY (id_historial);


--
-- Name: inventario_conteo inventario_conteo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_pkey PRIMARY KEY (id_ronda, id_producto);


--
-- Name: inventario_evento inventario_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_pkey PRIMARY KEY (id_evento);


--
-- Name: inventario_jornada inventario_jornada_id_local_fecha_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_id_local_fecha_key UNIQUE (id_local, fecha);


--
-- Name: inventario_jornada_inicio inventario_jornada_inicio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada_inicio
    ADD CONSTRAINT inventario_jornada_inicio_pkey PRIMARY KEY (id_jornada, id_producto);


--
-- Name: inventario_jornada inventario_jornada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_pkey PRIMARY KEY (id_jornada);


--
-- Name: inventario_ronda inventario_ronda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_ronda
    ADD CONSTRAINT inventario_ronda_pkey PRIMARY KEY (id_ronda);


--
-- Name: inventario_saldo_inicial inventario_saldo_inicial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_saldo_inicial
    ADD CONSTRAINT inventario_saldo_inicial_pkey PRIMARY KEY (id_local, id_producto);


--
-- Name: local local_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local
    ADD CONSTRAINT local_codigo_key UNIQUE (codigo);


--
-- Name: local local_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local
    ADD CONSTRAINT local_nombre_key UNIQUE (nombre);


--
-- Name: local local_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local
    ADD CONSTRAINT local_pkey PRIMARY KEY (id_local);


--
-- Name: menaje_medida menaje_medida_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menaje_medida
    ADD CONSTRAINT menaje_medida_pkey PRIMARY KEY (id_menaje);


--
-- Name: menaje_regla_medida menaje_regla_medida_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menaje_regla_medida
    ADD CONSTRAINT menaje_regla_medida_pkey PRIMARY KEY (campo);


--
-- Name: menaje_unidad_capacidad menaje_unidad_capacidad_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menaje_unidad_capacidad
    ADD CONSTRAINT menaje_unidad_capacidad_pkey PRIMARY KEY (codigo);


--
-- Name: menu_requiere_perfil_operativo menu_requiere_perfil_operativo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_requiere_perfil_operativo
    ADD CONSTRAINT menu_requiere_perfil_operativo_pkey PRIMARY KEY (id_opcion_menu);


--
-- Name: movimiento_inventario movimiento_inventario_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_codigo_key UNIQUE (codigo);


--
-- Name: movimiento_inventario_detalle movimiento_inventario_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT movimiento_inventario_detalle_pkey PRIMARY KEY (id_movimiento_inventario_detalle);


--
-- Name: movimiento_inventario movimiento_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_pkey PRIMARY KEY (id_movimiento_inventario);


--
-- Name: movimiento_motivo movimiento_motivo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_motivo
    ADD CONSTRAINT movimiento_motivo_pkey PRIMARY KEY (codigo);


--
-- Name: movimiento_reintegro movimiento_reintegro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_reintegro
    ADD CONSTRAINT movimiento_reintegro_pkey PRIMARY KEY (id_movimiento);


--
-- Name: movimiento_seguimiento movimiento_seguimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_seguimiento
    ADD CONSTRAINT movimiento_seguimiento_pkey PRIMARY KEY (id_movimiento);


--
-- Name: opcion_menu opcion_menu_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT opcion_menu_pkey PRIMARY KEY (id_opcion_menu);


--
-- Name: orden_compra orden_compra_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT orden_compra_codigo_key UNIQUE (codigo);


--
-- Name: orden_compra_detalle orden_compra_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT orden_compra_detalle_pkey PRIMARY KEY (id_orden_compra_detalle);


--
-- Name: orden_compra orden_compra_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT orden_compra_pkey PRIMARY KEY (id_orden_compra);


--
-- Name: perfil_capacidad perfil_capacidad_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_capacidad
    ADD CONSTRAINT perfil_capacidad_pkey PRIMARY KEY (id_perfil, capacidad);


--
-- Name: perfiles perfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_pkey PRIMARY KEY (id_perfil);


--
-- Name: permiso_accion permiso_accion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permiso_accion
    ADD CONSTRAINT permiso_accion_pkey PRIMARY KEY (accion);


--
-- Name: permiso_recurso permiso_recurso_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permiso_recurso
    ADD CONSTRAINT permiso_recurso_pkey PRIMARY KEY (recurso);


--
-- Name: categoria_carta pk_categoria_carta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_carta
    ADD CONSTRAINT pk_categoria_carta PRIMARY KEY (id_categoria_carta);


--
-- Name: categoria_producto pk_categoria_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_producto
    ADD CONSTRAINT pk_categoria_producto PRIMARY KEY (id_categoria);


--
-- Name: inventario_cierre_correccion_detalle pk_correccion_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT pk_correccion_detalle PRIMARY KEY (id_inventario_cierre_correccion_detalle);


--
-- Name: factura_recepcion_detalle_historial pk_factura_recepcion_detalle_historial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT pk_factura_recepcion_detalle_historial PRIMARY KEY (id_factura_recepcion_detalle_historial);


--
-- Name: factura_recepcion_historial pk_factura_recepcion_historial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_historial
    ADD CONSTRAINT pk_factura_recepcion_historial PRIMARY KEY (id_factura_recepcion_historial);


--
-- Name: inventario_cierre_correccion pk_inventario_cierre_correccion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion
    ADD CONSTRAINT pk_inventario_cierre_correccion PRIMARY KEY (id_inventario_cierre_correccion);


--
-- Name: item_carta pk_item_carta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_carta
    ADD CONSTRAINT pk_item_carta PRIMARY KEY (id_item_carta);


--
-- Name: menaje pk_menaje; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menaje
    ADD CONSTRAINT pk_menaje PRIMARY KEY (id_menaje);


--
-- Name: orden_compra_estado_historial pk_orden_compra_estado_historial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_estado_historial
    ADD CONSTRAINT pk_orden_compra_estado_historial PRIMARY KEY (id_orden_compra_estado_historial);


--
-- Name: perfil_gestion_usuario pk_perfil_gestion_usuario; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_gestion_usuario
    ADD CONSTRAINT pk_perfil_gestion_usuario PRIMARY KEY (id_perfil_gestor, id_perfil_objetivo);


--
-- Name: perfil_opcion_menu pk_perfil_opcion_menu; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_opcion_menu
    ADD CONSTRAINT pk_perfil_opcion_menu PRIMARY KEY (id_perfil, id_opcion_menu);


--
-- Name: presentacion_venta pk_presentacion_venta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT pk_presentacion_venta PRIMARY KEY (id_presentacion_venta);


--
-- Name: producto pk_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT pk_producto PRIMARY KEY (id_producto);


--
-- Name: proveedor pk_proveedor; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor
    ADD CONSTRAINT pk_proveedor PRIMARY KEY (id_proveedor);


--
-- Name: receta pk_receta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta
    ADD CONSTRAINT pk_receta PRIMARY KEY (id_receta);


--
-- Name: receta_detalle pk_receta_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT pk_receta_detalle PRIMARY KEY (id_receta_detalle);


--
-- Name: subproducto pk_subproducto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto
    ADD CONSTRAINT pk_subproducto PRIMARY KEY (id_subproducto);


--
-- Name: subproducto_detalle pk_subproducto_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT pk_subproducto_detalle PRIMARY KEY (id_subproducto_detalle);


--
-- Name: usuario_perfiles pk_usuario_perfiles; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT pk_usuario_perfiles PRIMARY KEY (id_usuario, id_perfil);


--
-- Name: usuario_puestos_laborales pk_usuario_puestos_laborales; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT pk_usuario_puestos_laborales PRIMARY KEY (id_usuario, id_puesto_laboral);


--
-- Name: producto_categoria_historial producto_categoria_historial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT producto_categoria_historial_pkey PRIMARY KEY (id_producto_categoria_historial);


--
-- Name: producto_proveedor_historial producto_proveedor_historial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT producto_proveedor_historial_pkey PRIMARY KEY (id_producto_proveedor_historial);


--
-- Name: producto_stock_local producto_stock_local_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_stock_local
    ADD CONSTRAINT producto_stock_local_pkey PRIMARY KEY (id_producto, id_local);


--
-- Name: promocion promocion_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion
    ADD CONSTRAINT promocion_codigo_key UNIQUE (codigo);


--
-- Name: promocion_grupo promocion_grupo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_grupo
    ADD CONSTRAINT promocion_grupo_pkey PRIMARY KEY (id_promocion_grupo);


--
-- Name: promocion_opcion promocion_opcion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT promocion_opcion_pkey PRIMARY KEY (id_promocion_opcion);


--
-- Name: promocion promocion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion
    ADD CONSTRAINT promocion_pkey PRIMARY KEY (id_promocion);


--
-- Name: promocion_reposicion promocion_reposicion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_reposicion
    ADD CONSTRAINT promocion_reposicion_pkey PRIMARY KEY (id_promocion, id_presentacion_venta);


--
-- Name: proveedor_campo_comercial proveedor_campo_comercial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor_campo_comercial
    ADD CONSTRAINT proveedor_campo_comercial_pkey PRIMARY KEY (campo);


--
-- Name: proveedor_categoria proveedor_categoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor_categoria
    ADD CONSTRAINT proveedor_categoria_pkey PRIMARY KEY (id_proveedor, id_categoria);


--
-- Name: puesto_laboral puesto_laboral_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT puesto_laboral_pkey PRIMARY KEY (id_puesto_laboral);


--
-- Name: recepcion_motivo_correccion recepcion_motivo_correccion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recepcion_motivo_correccion
    ADD CONSTRAINT recepcion_motivo_correccion_pkey PRIMARY KEY (codigo);


--
-- Name: salon_autorizacion_usada salon_autorizacion_usada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_autorizacion_usada
    ADD CONSTRAINT salon_autorizacion_usada_pkey PRIMARY KEY (clave);


--
-- Name: salon_cierre_diario salon_cierre_diario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cierre_diario
    ADD CONSTRAINT salon_cierre_diario_pkey PRIMARY KEY (id_local, fecha);


--
-- Name: salon_cobro salon_cobro_id_local_clave_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_local_clave_key UNIQUE (id_local, clave);


--
-- Name: salon_cobro salon_cobro_id_movimiento_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_movimiento_key UNIQUE (id_movimiento);


--
-- Name: salon_cobro_pedido salon_cobro_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro_pedido
    ADD CONSTRAINT salon_cobro_pedido_pkey PRIMARY KEY (id_pedido);


--
-- Name: salon_cobro salon_cobro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_pkey PRIMARY KEY (id_cobro);


--
-- Name: salon_distribucion salon_distribucion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_distribucion
    ADD CONSTRAINT salon_distribucion_pkey PRIMARY KEY (id_local);


--
-- Name: salon_intentos salon_intentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_intentos
    ADD CONSTRAINT salon_intentos_pkey PRIMARY KEY (origen);


--
-- Name: salon_linea_anulada salon_linea_anulada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_linea_anulada
    ADD CONSTRAINT salon_linea_anulada_pkey PRIMARY KEY (id_linea);


--
-- Name: salon_pedido_asignacion salon_pedido_asignacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_asignacion
    ADD CONSTRAINT salon_pedido_asignacion_pkey PRIMARY KEY (id_pedido);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_pedido_posicion_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_pedido_posicion_key UNIQUE (id_pedido, posicion);


--
-- Name: salon_pedido_linea salon_pedido_linea_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_pkey PRIMARY KEY (id_linea);


--
-- Name: salon_pedido salon_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido
    ADD CONSTRAINT salon_pedido_pkey PRIMARY KEY (id_pedido);


--
-- Name: unidad_medida_alias unidad_medida_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida_alias
    ADD CONSTRAINT unidad_medida_alias_pkey PRIMARY KEY (alias);


--
-- Name: unidad_medida unidad_medida_codigo_unece_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_codigo_unece_key UNIQUE (codigo_unece);


--
-- Name: unidad_medida_contexto unidad_medida_contexto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida_contexto
    ADD CONSTRAINT unidad_medida_contexto_pkey PRIMARY KEY (contexto, codigo_base);


--
-- Name: unidad_medida unidad_medida_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_pkey PRIMARY KEY (codigo);


--
-- Name: categoria_carta uq_categoria_carta_prefijo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_carta
    ADD CONSTRAINT uq_categoria_carta_prefijo UNIQUE (prefijo);


--
-- Name: categoria_producto uq_categoria_producto_prefijo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_producto
    ADD CONSTRAINT uq_categoria_producto_prefijo UNIQUE (prefijo);


--
-- Name: inventario_cierre_correccion_detalle uq_correccion_detalle_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT uq_correccion_detalle_producto UNIQUE (id_inventario_cierre_correccion, id_producto);


--
-- Name: factura_recepcion_detalle uq_factura_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT uq_factura_detalle UNIQUE (id_factura_recepcion, id_producto);


--
-- Name: factura_recepcion uq_factura_proveedor_numero; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT uq_factura_proveedor_numero UNIQUE (id_proveedor, numero_factura);


--
-- Name: factura_recepcion_detalle_historial uq_frdh_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT uq_frdh_producto UNIQUE (id_factura_recepcion_historial, id_producto);


--
-- Name: grupo_salsa_opcion uq_grupo_salsa_opcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT uq_grupo_salsa_opcion UNIQUE (id_grupo_salsa, id_producto);


--
-- Name: inventario_cierre_detalle uq_inventario_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT uq_inventario_detalle UNIQUE (id_inventario_cierre, id_producto);


--
-- Name: inventario_cierre uq_inventario_local_fecha; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT uq_inventario_local_fecha UNIQUE (id_local, fecha_inventario);


--
-- Name: item_carta uq_item_carta_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_carta
    ADD CONSTRAINT uq_item_carta_codigo UNIQUE (codigo);


--
-- Name: movimiento_inventario_detalle uq_movimiento_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT uq_movimiento_detalle UNIQUE (id_movimiento_inventario, id_producto);


--
-- Name: orden_compra_detalle uq_orden_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT uq_orden_detalle UNIQUE (id_orden_compra, id_producto);


--
-- Name: presentacion_venta uq_presentacion_venta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT uq_presentacion_venta UNIQUE (id_item_carta, id_menaje, contenido, unidad);


--
-- Name: producto uq_producto_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT uq_producto_codigo UNIQUE (codigo);


--
-- Name: promocion_opcion uq_promocion_opcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT uq_promocion_opcion UNIQUE (id_promocion_grupo, id_presentacion_venta);


--
-- Name: puesto_laboral uq_puesto_laboral_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT uq_puesto_laboral_nombre UNIQUE (nombre);


--
-- Name: receta_detalle uq_receta_detalle_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT uq_receta_detalle_producto UNIQUE (id_receta, id_producto);


--
-- Name: receta_detalle uq_receta_detalle_subproducto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT uq_receta_detalle_subproducto UNIQUE (id_receta, id_subproducto);


--
-- Name: receta uq_receta_presentacion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta
    ADD CONSTRAINT uq_receta_presentacion UNIQUE (id_presentacion_venta);


--
-- Name: subproducto uq_subproducto_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto
    ADD CONSTRAINT uq_subproducto_codigo UNIQUE (codigo);


--
-- Name: subproducto_detalle uq_subproducto_detalle_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT uq_subproducto_detalle_producto UNIQUE (id_subproducto, id_producto);


--
-- Name: usuario_local uq_usuario_local; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT uq_usuario_local UNIQUE (id_usuario, id_local);


--
-- Name: usuario usuario_dni_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_dni_key UNIQUE (dni);


--
-- Name: usuario_local usuario_local_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT usuario_local_pkey PRIMARY KEY (id_usuario_local);


--
-- Name: usuario_pin_salon usuario_pin_salon_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_pin_salon
    ADD CONSTRAINT usuario_pin_salon_pkey PRIMARY KEY (id_usuario);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario);


--
-- Name: fact_api_cola; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fact_api_cola ON public.fact_api_operacion USING btree (disponible_en) WHERE (estado = ANY (ARRAY['PENDIENTE'::text, 'REINTENTO'::text, 'PROCESANDO'::text]));


--
-- Name: fact_api_intento_inicio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fact_api_intento_inicio ON public.fact_api_intento USING btree (inicio);


--
-- Name: idx_actividad_usuario_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actividad_usuario_local ON public.actividad_usuario USING btree (id_local);


--
-- Name: idx_actividad_usuario_perfil; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actividad_usuario_perfil ON public.actividad_usuario USING btree (id_perfil_utilizado);


--
-- Name: idx_actividad_usuario_puesto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actividad_usuario_puesto ON public.actividad_usuario USING btree (id_puesto_laboral);


--
-- Name: idx_auditoria_cambio_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_cambio_local ON public.auditoria_cambio USING btree (id_local);


--
-- Name: idx_auditoria_cambio_perfil; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_cambio_perfil ON public.auditoria_cambio USING btree (id_perfil_utilizado);


--
-- Name: idx_auditoria_cambio_puesto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_cambio_puesto ON public.auditoria_cambio USING btree (id_puesto_laboral);


--
-- Name: idx_proveedor_categoria_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proveedor_categoria_categoria ON public.proveedor_categoria USING btree (id_categoria);


--
-- Name: idx_usuario_local_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuario_local_local ON public.usuario_local USING btree (id_local) WHERE (estado_registro = 1);


--
-- Name: idx_usuario_local_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuario_local_usuario ON public.usuario_local USING btree (id_usuario) WHERE (estado_registro = 1);


--
-- Name: idx_usuario_puesto_laboral; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuario_puesto_laboral ON public.usuario USING btree (id_puesto_laboral);


--
-- Name: ix_actividad_modulo_registro; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_actividad_modulo_registro ON public.actividad_usuario USING btree (modulo, id_registro_afectado);


--
-- Name: ix_actividad_usuario_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_actividad_usuario_fecha ON public.actividad_usuario USING btree (id_usuario, fecha_actividad DESC);


--
-- Name: ix_asistente_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_asistente_usuario ON public.asistente_ia_borrador USING btree (id_usuario, creado_en);


--
-- Name: ix_auditoria_cambio_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_auditoria_cambio_fecha ON public.auditoria_cambio USING btree (fecha_cambio DESC);


--
-- Name: ix_auditoria_cambio_registro; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_auditoria_cambio_registro ON public.auditoria_cambio USING btree (tabla_afectada, id_registro_afectado);


--
-- Name: ix_cliente_comercial_local_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cliente_comercial_local_nombre ON public.cliente_comercial USING btree (id_local, nombre);


--
-- Name: ix_cobro_jornada; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cobro_jornada ON public.salon_cobro USING btree (id_jornada);


--
-- Name: ix_conteo_puesto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_conteo_puesto ON public.inventario_conteo USING btree (puesto_asignado, id_ronda);


--
-- Name: ix_correccion_inventario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_correccion_inventario ON public.inventario_cierre_correccion USING btree (id_inventario_cierre, fecha_correccion DESC);


--
-- Name: ix_correccion_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_correccion_usuario ON public.inventario_cierre_correccion USING btree (usuario_correccion);


--
-- Name: ix_evento_jornada; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_evento_jornada ON public.inventario_evento USING btree (id_jornada, id_producto);


--
-- Name: ix_evento_saldo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_evento_saldo ON public.inventario_evento USING btree (id_local, id_producto);


--
-- Name: ix_factura_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_detalle_producto ON public.factura_recepcion_detalle USING btree (id_producto);


--
-- Name: ix_factura_orden; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_orden ON public.factura_recepcion USING btree (id_orden_compra);


--
-- Name: ix_factura_recepcion_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_recepcion_fecha ON public.factura_recepcion USING btree (fecha_recepcion);


--
-- Name: ix_factura_recepcion_orden; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_recepcion_orden ON public.factura_recepcion USING btree (id_orden_compra);


--
-- Name: ix_facturacion_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_facturacion_local ON public.facturacion_comprobante USING btree (id_local, creado_en);


--
-- Name: ix_frh_factura; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_frh_factura ON public.factura_recepcion_historial USING btree (id_factura_recepcion);


--
-- Name: ix_grupo_salsa_opcion_grupo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_grupo_salsa_opcion_grupo ON public.grupo_salsa_opcion USING btree (id_grupo_salsa);


--
-- Name: ix_grupo_salsa_opcion_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_grupo_salsa_opcion_producto ON public.grupo_salsa_opcion USING btree (id_producto);


--
-- Name: ix_ia_consumo_mes_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ia_consumo_mes_usuario ON public.ia_consumo USING btree (mes, id_usuario, dia);


--
-- Name: ix_inventario_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inventario_detalle_producto ON public.inventario_cierre_detalle USING btree (id_producto);


--
-- Name: ix_item_carta_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_item_carta_categoria ON public.item_carta USING btree (id_categoria_carta);


--
-- Name: ix_movimiento_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimiento_detalle_producto ON public.movimiento_inventario_detalle USING btree (id_producto);


--
-- Name: ix_movimiento_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimiento_fecha ON public.movimiento_inventario USING btree (fecha_movimiento);


--
-- Name: ix_movimiento_local_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimiento_local_fecha ON public.movimiento_inventario USING btree (id_local, fecha_movimiento);


--
-- Name: ix_oceh_orden; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_oceh_orden ON public.orden_compra_estado_historial USING btree (id_orden_compra);


--
-- Name: ix_orden_compra_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_compra_estado ON public.orden_compra USING btree (estado_orden_compra);


--
-- Name: ix_orden_compra_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_compra_fecha ON public.orden_compra USING btree (fecha_registro);


--
-- Name: ix_orden_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_detalle_producto ON public.orden_compra_detalle USING btree (id_producto);


--
-- Name: ix_orden_detalle_proveedor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_detalle_proveedor ON public.orden_compra_detalle USING btree (id_proveedor);


--
-- Name: ix_orden_local_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_local_fecha ON public.orden_compra USING btree (id_local, fecha_registro);


--
-- Name: ix_pch_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pch_fecha ON public.producto_categoria_historial USING btree (fecha_cambio DESC);


--
-- Name: ix_pch_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pch_producto ON public.producto_categoria_historial USING btree (id_producto);


--
-- Name: ix_pph_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pph_fecha ON public.producto_proveedor_historial USING btree (fecha_cambio DESC);


--
-- Name: ix_pph_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pph_producto ON public.producto_proveedor_historial USING btree (id_producto);


--
-- Name: ix_presentacion_venta_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_presentacion_venta_item ON public.presentacion_venta USING btree (id_item_carta);


--
-- Name: ix_presentacion_venta_menaje; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_presentacion_venta_menaje ON public.presentacion_venta USING btree (id_menaje);


--
-- Name: ix_producto_stock_local_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_producto_stock_local_local ON public.producto_stock_local USING btree (id_local);


--
-- Name: ix_promocion_grupo_promocion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_promocion_grupo_promocion ON public.promocion_grupo USING btree (id_promocion);


--
-- Name: ix_promocion_opcion_grupo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_promocion_opcion_grupo ON public.promocion_opcion USING btree (id_promocion_grupo);


--
-- Name: ix_promocion_opcion_presentacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_promocion_opcion_presentacion ON public.promocion_opcion USING btree (id_presentacion_venta);


--
-- Name: ix_receta_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_receta_detalle_producto ON public.receta_detalle USING btree (id_producto) WHERE (id_producto IS NOT NULL);


--
-- Name: ix_receta_detalle_receta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_receta_detalle_receta ON public.receta_detalle USING btree (id_receta);


--
-- Name: ix_receta_detalle_subproducto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_receta_detalle_subproducto ON public.receta_detalle USING btree (id_subproducto) WHERE (id_subproducto IS NOT NULL);


--
-- Name: ix_reintegro_salida; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reintegro_salida ON public.movimiento_reintegro USING btree (id_salida);


--
-- Name: ix_salon_cobro_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_cobro_local ON public.salon_cobro USING btree (id_local, creado_en);


--
-- Name: ix_salon_cobro_pedido; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_cobro_pedido ON public.salon_cobro_pedido USING btree (id_cobro);


--
-- Name: ix_salon_linea_promocion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_linea_promocion ON public.salon_pedido_linea USING btree (id_promocion) WHERE (id_promocion IS NOT NULL);


--
-- Name: ix_salon_mesa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_mesa ON public.salon_pedido USING btree (id_local, mesa, id_pedido);


--
-- Name: ix_salon_pedido_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_pedido_usuario ON public.salon_pedido USING btree (id_local, id_usuario);


--
-- Name: ix_salon_reposicion_barra; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_reposicion_barra ON public.salon_pedido_linea USING btree (id_barra_libre) WHERE (id_barra_libre IS NOT NULL);


--
-- Name: ix_seguimiento_destino; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_seguimiento_destino ON public.movimiento_seguimiento USING btree (id_local_destino, estado);


--
-- Name: ix_subproducto_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subproducto_detalle_producto ON public.subproducto_detalle USING btree (id_producto);


--
-- Name: ix_subproducto_detalle_subproducto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subproducto_detalle_subproducto ON public.subproducto_detalle USING btree (id_subproducto);


--
-- Name: ix_upl_usuario_activo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_upl_usuario_activo ON public.usuario_puestos_laborales USING btree (id_usuario, estado_registro);


--
-- Name: ix_usuario_perfiles_perfil; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_usuario_perfiles_perfil ON public.usuario_perfiles USING btree (id_perfil);


--
-- Name: ix_usuario_puestos_activos; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_usuario_puestos_activos ON public.usuario_puestos_laborales USING btree (id_usuario, estado_registro);


--
-- Name: uq_cliente_comercial_documento_local; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_cliente_comercial_documento_local ON public.cliente_comercial USING btree (id_local, tipo_documento, numero_documento) WHERE ((numero_documento IS NOT NULL) AND ((numero_documento)::text <> ''::text));


--
-- Name: uq_guia_reintegro; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_guia_reintegro ON public.movimiento_reintegro USING btree (id_salida, guia_proveedor) WHERE (guia_proveedor IS NOT NULL);


--
-- Name: uq_jornada_abierta; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_jornada_abierta ON public.inventario_jornada USING btree (id_local) WHERE (cerrado_en IS NULL);


--
-- Name: uq_proveedor_ruc; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_proveedor_ruc ON public.proveedor USING btree (((datos_comerciales ->> 'ruc'::text))) WHERE (COALESCE((datos_comerciales ->> 'ruc'::text), ''::text) <> ''::text);


--
-- Name: uq_ronda_abierta; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_ronda_abierta ON public.inventario_ronda USING btree (id_local) WHERE (cerrado_en IS NULL);


--
-- Name: uq_salon_borrador; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_salon_borrador ON public.salon_pedido USING btree (id_local, mesa) WHERE ((estado)::text = 'BORRADOR'::text);


--
-- Name: uq_salon_envio; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_salon_envio ON public.salon_pedido USING btree (id_local, mesa, envio_clave) WHERE (envio_clave IS NOT NULL);


--
-- Name: ux_categoria_carta_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_categoria_carta_nombre ON public.categoria_carta USING btree (lower((nombre)::text));


--
-- Name: ux_categoria_producto_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_categoria_producto_nombre ON public.categoria_producto USING btree (lower((nombre)::text));


--
-- Name: ux_inventario_cierre_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_inventario_cierre_detalle_producto ON public.inventario_cierre_detalle USING btree (id_inventario_cierre, id_producto);


--
-- Name: ux_menaje_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_menaje_nombre ON public.menaje USING btree (lower((nombre)::text));


--
-- Name: ux_opcion_menu_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_opcion_menu_codigo ON public.opcion_menu USING btree (lower((codigo)::text));


--
-- Name: ux_opcion_menu_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_opcion_menu_url ON public.opcion_menu USING btree (lower((url_menu)::text));


--
-- Name: ux_perfiles_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_perfiles_nombre ON public.perfiles USING btree (lower((nombre)::text));


--
-- Name: ux_proveedor_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_proveedor_nombre ON public.proveedor USING btree (lower((nombre)::text));


--
-- Name: ux_usuario_correo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_usuario_correo ON public.usuario USING btree (lower((correo_electronico)::text));


--
-- Name: salon_cobro cobro_jornada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cobro_jornada BEFORE INSERT ON public.salon_cobro FOR EACH ROW EXECUTE FUNCTION public.inventario_cobro_jornada();


--
-- Name: movimiento_inventario_detalle movimiento_evento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER movimiento_evento AFTER INSERT OR DELETE OR UPDATE ON public.movimiento_inventario_detalle FOR EACH ROW EXECUTE FUNCTION public.inventario_registrar_evento();


--
-- Name: salon_pedido_linea proteger_linea_salon; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER proteger_linea_salon BEFORE INSERT OR DELETE OR UPDATE ON public.salon_pedido_linea FOR EACH ROW EXECUTE FUNCTION public.proteger_linea_salon();


--
-- Name: salon_pedido proteger_pedido_salon; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER proteger_pedido_salon BEFORE DELETE OR UPDATE ON public.salon_pedido FOR EACH ROW EXECUTE FUNCTION public.proteger_pedido_salon();


--
-- Name: factura_recepcion_detalle recepcion_evento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recepcion_evento AFTER INSERT OR DELETE OR UPDATE ON public.factura_recepcion_detalle FOR EACH ROW EXECUTE FUNCTION public.inventario_registrar_evento();


--
-- Name: menaje_medida tr_carta_validar_medidas_menaje; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_carta_validar_medidas_menaje BEFORE INSERT OR UPDATE ON public.menaje_medida FOR EACH ROW EXECUTE FUNCTION public.carta_validar_medidas_menaje();


--
-- Name: movimiento_inventario tr_validar_movimiento_motivo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_validar_movimiento_motivo BEFORE INSERT OR UPDATE OF motivo_movimiento, tipo_movimiento, local_relacionado, id_proveedor ON public.movimiento_inventario FOR EACH ROW EXECUTE FUNCTION public.validar_movimiento_motivo();


--
-- Name: grupo_salsa_opcion tr_validar_unidad_contexto; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_validar_unidad_contexto BEFORE INSERT OR UPDATE OF unidad ON public.grupo_salsa_opcion FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_medida_contexto('producto');


--
-- Name: presentacion_venta tr_validar_unidad_contexto; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_validar_unidad_contexto BEFORE INSERT OR UPDATE OF unidad ON public.presentacion_venta FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_medida_contexto('presentacion');


--
-- Name: producto tr_validar_unidad_contexto; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_validar_unidad_contexto BEFORE INSERT OR UPDATE OF unidad ON public.producto FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_medida_contexto('producto');


--
-- Name: receta_detalle tr_validar_unidad_contexto; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_validar_unidad_contexto BEFORE INSERT OR UPDATE OF unidad ON public.receta_detalle FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_medida_contexto('presentacion');


--
-- Name: subproducto tr_validar_unidad_contexto; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_validar_unidad_contexto BEFORE INSERT OR UPDATE OF unidad ON public.subproducto FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_medida_contexto('subproducto');


--
-- Name: subproducto_detalle tr_validar_unidad_contexto; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_validar_unidad_contexto BEFORE INSERT OR UPDATE OF unidad ON public.subproducto_detalle FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_medida_contexto('producto');


--
-- Name: grupo_salsa_opcion trg_validar_unidad_grupo_salsa_opcion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_unidad_grupo_salsa_opcion BEFORE INSERT OR UPDATE OF id_producto, unidad ON public.grupo_salsa_opcion FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_grupo_salsa_opcion();


--
-- Name: receta_detalle trg_validar_unidad_receta_detalle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_unidad_receta_detalle BEFORE INSERT OR UPDATE OF tipo_componente, id_producto, id_subproducto, unidad ON public.receta_detalle FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_receta_detalle();


--
-- Name: subproducto_detalle trg_validar_unidad_subproducto_detalle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_unidad_subproducto_detalle BEFORE INSERT OR UPDATE OF id_producto, unidad ON public.subproducto_detalle FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_subproducto_detalle();


--
-- Name: asistente_ia_borrador asistente_ia_borrador_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistente_ia_borrador
    ADD CONSTRAINT asistente_ia_borrador_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: asistente_ia_workspace asistente_ia_workspace_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistente_ia_workspace
    ADD CONSTRAINT asistente_ia_workspace_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: cliente_comercial cliente_comercial_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_comercial
    ADD CONSTRAINT cliente_comercial_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: fact_api_adjunto fact_api_adjunto_id_factura_recepcion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_adjunto
    ADD CONSTRAINT fact_api_adjunto_id_factura_recepcion_fkey FOREIGN KEY (id_factura_recepcion) REFERENCES public.factura_recepcion(id_factura_recepcion);


--
-- Name: fact_api_adjunto fact_api_adjunto_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_adjunto
    ADD CONSTRAINT fact_api_adjunto_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: fact_api_archivo fact_api_archivo_id_documento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_archivo
    ADD CONSTRAINT fact_api_archivo_id_documento_fkey FOREIGN KEY (id_documento) REFERENCES public.fact_api_documento(id_documento);


--
-- Name: fact_api_config fact_api_config_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_config
    ADD CONSTRAINT fact_api_config_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: fact_api_documento fact_api_documento_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_documento
    ADD CONSTRAINT fact_api_documento_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: fact_api_documento fact_api_documento_id_operacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_documento
    ADD CONSTRAINT fact_api_documento_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.fact_api_operacion(id_operacion);


--
-- Name: fact_api_intento fact_api_intento_id_operacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_intento
    ADD CONSTRAINT fact_api_intento_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.fact_api_operacion(id_operacion);


--
-- Name: fact_api_operacion fact_api_operacion_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_api_operacion
    ADD CONSTRAINT fact_api_operacion_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: facturacion_comprobante facturacion_comprobante_id_cobro_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facturacion_comprobante
    ADD CONSTRAINT facturacion_comprobante_id_cobro_fkey FOREIGN KEY (id_cobro) REFERENCES public.salon_cobro(id_cobro);


--
-- Name: facturacion_comprobante facturacion_comprobante_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facturacion_comprobante
    ADD CONSTRAINT facturacion_comprobante_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: actividad_usuario fk_actividad_perfil_utilizado; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_perfil_utilizado FOREIGN KEY (id_perfil_utilizado) REFERENCES public.perfiles(id_perfil);


--
-- Name: actividad_usuario fk_actividad_puesto_laboral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_puesto_laboral FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: actividad_usuario fk_actividad_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: actividad_usuario fk_actividad_usuario_local; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_usuario_local FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: auditoria_cambio fk_auditoria_cambio_local; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_local FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: auditoria_cambio fk_auditoria_cambio_perfil; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_perfil FOREIGN KEY (id_perfil_utilizado) REFERENCES public.perfiles(id_perfil);


--
-- Name: auditoria_cambio fk_auditoria_cambio_puesto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_puesto FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: auditoria_cambio fk_auditoria_cambio_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_cierre_correccion_detalle fk_correccion_detalle_cabecera; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT fk_correccion_detalle_cabecera FOREIGN KEY (id_inventario_cierre_correccion) REFERENCES public.inventario_cierre_correccion(id_inventario_cierre_correccion) ON DELETE CASCADE;


--
-- Name: inventario_cierre_correccion_detalle fk_correccion_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT fk_correccion_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_cierre_correccion fk_correccion_inventario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion
    ADD CONSTRAINT fk_correccion_inventario FOREIGN KEY (id_inventario_cierre) REFERENCES public.inventario_cierre(id_inventario_cierre);


--
-- Name: inventario_cierre_correccion fk_correccion_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion
    ADD CONSTRAINT fk_correccion_usuario FOREIGN KEY (usuario_correccion) REFERENCES public.usuario(id_usuario);


--
-- Name: factura_recepcion_detalle fk_factura_detalle_factura; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT fk_factura_detalle_factura FOREIGN KEY (id_factura_recepcion) REFERENCES public.factura_recepcion(id_factura_recepcion) ON DELETE CASCADE;


--
-- Name: factura_recepcion_detalle fk_factura_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT fk_factura_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: factura_recepcion fk_factura_orden; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT fk_factura_orden FOREIGN KEY (id_orden_compra) REFERENCES public.orden_compra(id_orden_compra);


--
-- Name: factura_recepcion fk_factura_proveedor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT fk_factura_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: factura_recepcion fk_factura_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT fk_factura_usuario FOREIGN KEY (usuario_recepcion) REFERENCES public.usuario(id_usuario);


--
-- Name: factura_recepcion_detalle_historial fk_frdh_historial; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT fk_frdh_historial FOREIGN KEY (id_factura_recepcion_historial) REFERENCES public.factura_recepcion_historial(id_factura_recepcion_historial) ON DELETE CASCADE;


--
-- Name: factura_recepcion_detalle_historial fk_frdh_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT fk_frdh_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: factura_recepcion_historial fk_frh_factura; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_historial
    ADD CONSTRAINT fk_frh_factura FOREIGN KEY (id_factura_recepcion) REFERENCES public.factura_recepcion(id_factura_recepcion);


--
-- Name: factura_recepcion_historial fk_frh_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_historial
    ADD CONSTRAINT fk_frh_usuario FOREIGN KEY (usuario_correccion) REFERENCES public.usuario(id_usuario);


--
-- Name: grupo_salsa_opcion fk_grupo_salsa_opcion_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT fk_grupo_salsa_opcion_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: inventario_cierre_detalle fk_inventario_detalle_cierre; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT fk_inventario_detalle_cierre FOREIGN KEY (id_inventario_cierre) REFERENCES public.inventario_cierre(id_inventario_cierre) ON DELETE CASCADE;


--
-- Name: inventario_cierre_detalle fk_inventario_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT fk_inventario_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_cierre fk_inventario_usuario_registro; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT fk_inventario_usuario_registro FOREIGN KEY (usuario_registro) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_cierre fk_inventario_usuario_revision; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT fk_inventario_usuario_revision FOREIGN KEY (usuario_revision) REFERENCES public.usuario(id_usuario);


--
-- Name: item_carta fk_item_carta_categoria; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_carta
    ADD CONSTRAINT fk_item_carta_categoria FOREIGN KEY (id_categoria_carta) REFERENCES public.categoria_carta(id_categoria_carta);


--
-- Name: menaje_medida fk_menaje_unidad_capacidad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menaje_medida
    ADD CONSTRAINT fk_menaje_unidad_capacidad FOREIGN KEY (unidad_capacidad) REFERENCES public.menaje_unidad_capacidad(codigo);


--
-- Name: movimiento_inventario_detalle fk_movimiento_detalle_movimiento; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT fk_movimiento_detalle_movimiento FOREIGN KEY (id_movimiento_inventario) REFERENCES public.movimiento_inventario(id_movimiento_inventario) ON DELETE CASCADE;


--
-- Name: movimiento_inventario_detalle fk_movimiento_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT fk_movimiento_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: movimiento_inventario fk_movimiento_proveedor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT fk_movimiento_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: movimiento_inventario fk_movimiento_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT fk_movimiento_usuario FOREIGN KEY (usuario_registro) REFERENCES public.usuario(id_usuario);


--
-- Name: orden_compra_estado_historial fk_oceh_orden; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_estado_historial
    ADD CONSTRAINT fk_oceh_orden FOREIGN KEY (id_orden_compra) REFERENCES public.orden_compra(id_orden_compra);


--
-- Name: orden_compra_estado_historial fk_oceh_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_estado_historial
    ADD CONSTRAINT fk_oceh_usuario FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: opcion_menu fk_opcion_menu_padre; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT fk_opcion_menu_padre FOREIGN KEY (id_padre) REFERENCES public.opcion_menu(id_opcion_menu);


--
-- Name: opcion_menu fk_opcion_menu_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT fk_opcion_menu_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuario(id_usuario);


--
-- Name: opcion_menu fk_opcion_menu_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT fk_opcion_menu_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: orden_compra_detalle fk_orden_detalle_orden; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT fk_orden_detalle_orden FOREIGN KEY (id_orden_compra) REFERENCES public.orden_compra(id_orden_compra) ON DELETE CASCADE;


--
-- Name: orden_compra_detalle fk_orden_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT fk_orden_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: orden_compra fk_orden_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT fk_orden_usuario FOREIGN KEY (usuario_registro) REFERENCES public.usuario(id_usuario);


--
-- Name: orden_compra fk_orden_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT fk_orden_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: producto_categoria_historial fk_pch_categoria_anterior; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_categoria_anterior FOREIGN KEY (id_categoria_anterior) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: producto_categoria_historial fk_pch_categoria_nueva; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_categoria_nueva FOREIGN KEY (id_categoria_nueva) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: producto_categoria_historial fk_pch_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: producto_categoria_historial fk_pch_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_usuario FOREIGN KEY (usuario_cambio) REFERENCES public.usuario(id_usuario);


--
-- Name: perfil_gestion_usuario fk_perfil_gestion_gestor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_gestion_usuario
    ADD CONSTRAINT fk_perfil_gestion_gestor FOREIGN KEY (id_perfil_gestor) REFERENCES public.perfiles(id_perfil);


--
-- Name: perfil_gestion_usuario fk_perfil_gestion_objetivo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_gestion_usuario
    ADD CONSTRAINT fk_perfil_gestion_objetivo FOREIGN KEY (id_perfil_objetivo) REFERENCES public.perfiles(id_perfil);


--
-- Name: perfil_opcion_menu fk_perfil_opcion_menu; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_opcion_menu
    ADD CONSTRAINT fk_perfil_opcion_menu FOREIGN KEY (id_opcion_menu) REFERENCES public.opcion_menu(id_opcion_menu);


--
-- Name: perfil_opcion_menu fk_perfil_opcion_perfil; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_opcion_menu
    ADD CONSTRAINT fk_perfil_opcion_perfil FOREIGN KEY (id_perfil) REFERENCES public.perfiles(id_perfil);


--
-- Name: producto_proveedor_historial fk_pph_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: producto_proveedor_historial fk_pph_proveedor_anterior; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_proveedor_anterior FOREIGN KEY (id_proveedor_anterior) REFERENCES public.proveedor(id_proveedor);


--
-- Name: producto_proveedor_historial fk_pph_proveedor_nuevo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_proveedor_nuevo FOREIGN KEY (id_proveedor_nuevo) REFERENCES public.proveedor(id_proveedor);


--
-- Name: producto_proveedor_historial fk_pph_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_usuario FOREIGN KEY (usuario_cambio) REFERENCES public.usuario(id_usuario);


--
-- Name: presentacion_venta fk_presentacion_venta_item; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT fk_presentacion_venta_item FOREIGN KEY (id_item_carta) REFERENCES public.item_carta(id_item_carta);


--
-- Name: presentacion_venta fk_presentacion_venta_menaje; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT fk_presentacion_venta_menaje FOREIGN KEY (id_menaje) REFERENCES public.menaje(id_menaje);


--
-- Name: presentacion_venta fk_presentacion_venta_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT fk_presentacion_venta_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: producto fk_producto_categoria; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: producto fk_producto_proveedor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT fk_producto_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: producto fk_producto_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT fk_producto_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: puesto_laboral fk_puesto_laboral_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT fk_puesto_laboral_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuario(id_usuario);


--
-- Name: puesto_laboral fk_puesto_laboral_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT fk_puesto_laboral_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: receta_detalle fk_receta_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: receta_detalle fk_receta_detalle_receta; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_receta FOREIGN KEY (id_receta) REFERENCES public.receta(id_receta);


--
-- Name: receta_detalle fk_receta_detalle_subproducto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_subproducto FOREIGN KEY (id_subproducto) REFERENCES public.subproducto(id_subproducto);


--
-- Name: receta_detalle fk_receta_detalle_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: receta fk_receta_presentacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta
    ADD CONSTRAINT fk_receta_presentacion FOREIGN KEY (id_presentacion_venta) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: subproducto_detalle fk_subproducto_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT fk_subproducto_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: subproducto_detalle fk_subproducto_detalle_subproducto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT fk_subproducto_detalle_subproducto FOREIGN KEY (id_subproducto) REFERENCES public.subproducto(id_subproducto);


--
-- Name: subproducto_detalle fk_subproducto_detalle_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT fk_subproducto_detalle_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: subproducto fk_subproducto_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto
    ADD CONSTRAINT fk_subproducto_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: usuario_puestos_laborales fk_upl_asignador; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_asignador FOREIGN KEY (usuario_asignacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_puestos_laborales fk_upl_modificador; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_modificador FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_puestos_laborales fk_upl_puesto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_puesto FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: usuario_puestos_laborales fk_upl_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario fk_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT fk_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_local fk_usuario_local_local; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT fk_usuario_local_local FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: usuario_local fk_usuario_local_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT fk_usuario_local_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario fk_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT fk_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_perfiles fk_usuario_perfiles_asignacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_asignacion FOREIGN KEY (usuario_asignacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_perfiles fk_usuario_perfiles_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_perfiles fk_usuario_perfiles_perfil; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_perfil FOREIGN KEY (id_perfil) REFERENCES public.perfiles(id_perfil);


--
-- Name: usuario_perfiles fk_usuario_perfiles_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario fk_usuario_puesto_laboral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT fk_usuario_puesto_laboral FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: grupo_salsa grupo_salsa_id_presentacion_venta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa
    ADD CONSTRAINT grupo_salsa_id_presentacion_venta_fkey FOREIGN KEY (id_presentacion_venta) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: grupo_salsa_opcion grupo_salsa_opcion_id_grupo_salsa_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT grupo_salsa_opcion_id_grupo_salsa_fkey FOREIGN KEY (id_grupo_salsa) REFERENCES public.grupo_salsa(id_grupo_salsa);


--
-- Name: grupo_salsa_opcion grupo_salsa_opcion_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT grupo_salsa_opcion_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: ia_consumo ia_consumo_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ia_consumo
    ADD CONSTRAINT ia_consumo_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: ia_cuota_usuario ia_cuota_usuario_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ia_cuota_usuario
    ADD CONSTRAINT ia_cuota_usuario_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_actualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_actualizado_por_fkey FOREIGN KEY (actualizado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_id_puesto_laboral_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_id_puesto_laboral_fkey FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: inventario_cierre inventario_cierre_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT inventario_cierre_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_conteo inventario_conteo_asignado_a_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_asignado_a_fkey FOREIGN KEY (asignado_a) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_contado_perfil_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_contado_perfil_fkey FOREIGN KEY (contado_perfil) REFERENCES public.perfiles(id_perfil);


--
-- Name: inventario_conteo inventario_conteo_contado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_contado_por_fkey FOREIGN KEY (contado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_contado_puesto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_contado_puesto_fkey FOREIGN KEY (contado_puesto) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: inventario_conteo_historial inventario_conteo_historial_id_ronda_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo_historial
    ADD CONSTRAINT inventario_conteo_historial_id_ronda_id_producto_fkey FOREIGN KEY (id_ronda, id_producto) REFERENCES public.inventario_conteo(id_ronda, id_producto);


--
-- Name: inventario_conteo_historial inventario_conteo_historial_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo_historial
    ADD CONSTRAINT inventario_conteo_historial_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_conteo inventario_conteo_id_ronda_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_id_ronda_fkey FOREIGN KEY (id_ronda) REFERENCES public.inventario_ronda(id_ronda);


--
-- Name: inventario_conteo inventario_conteo_justificado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_justificado_por_fkey FOREIGN KEY (justificado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_puesto_asignado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_puesto_asignado_fkey FOREIGN KEY (puesto_asignado) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: inventario_conteo inventario_conteo_revisado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_revisado_por_fkey FOREIGN KEY (revisado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_evento inventario_evento_id_jornada_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_id_jornada_fkey FOREIGN KEY (id_jornada) REFERENCES public.inventario_jornada(id_jornada);


--
-- Name: inventario_evento inventario_evento_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_evento inventario_evento_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_jornada inventario_jornada_abierto_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_abierto_por_fkey FOREIGN KEY (abierto_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_jornada inventario_jornada_cerrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_cerrado_por_fkey FOREIGN KEY (cerrado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_jornada inventario_jornada_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_jornada_inicio inventario_jornada_inicio_id_jornada_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada_inicio
    ADD CONSTRAINT inventario_jornada_inicio_id_jornada_fkey FOREIGN KEY (id_jornada) REFERENCES public.inventario_jornada(id_jornada);


--
-- Name: inventario_jornada_inicio inventario_jornada_inicio_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada_inicio
    ADD CONSTRAINT inventario_jornada_inicio_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_ronda inventario_ronda_creado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_ronda
    ADD CONSTRAINT inventario_ronda_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_ronda inventario_ronda_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_ronda
    ADD CONSTRAINT inventario_ronda_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_saldo_inicial inventario_saldo_inicial_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_saldo_inicial
    ADD CONSTRAINT inventario_saldo_inicial_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_saldo_inicial inventario_saldo_inicial_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_saldo_inicial
    ADD CONSTRAINT inventario_saldo_inicial_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: menu_requiere_perfil_operativo menu_requiere_perfil_operativo_id_opcion_menu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_requiere_perfil_operativo
    ADD CONSTRAINT menu_requiere_perfil_operativo_id_opcion_menu_fkey FOREIGN KEY (id_opcion_menu) REFERENCES public.opcion_menu(id_opcion_menu) ON DELETE CASCADE;


--
-- Name: movimiento_inventario movimiento_inventario_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: movimiento_motivo movimiento_motivo_motivo_recepcion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_motivo
    ADD CONSTRAINT movimiento_motivo_motivo_recepcion_fkey FOREIGN KEY (motivo_recepcion) REFERENCES public.movimiento_motivo(codigo);


--
-- Name: movimiento_reintegro movimiento_reintegro_id_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_reintegro
    ADD CONSTRAINT movimiento_reintegro_id_movimiento_fkey FOREIGN KEY (id_movimiento) REFERENCES public.movimiento_inventario(id_movimiento_inventario);


--
-- Name: movimiento_reintegro movimiento_reintegro_id_salida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_reintegro
    ADD CONSTRAINT movimiento_reintegro_id_salida_fkey FOREIGN KEY (id_salida) REFERENCES public.movimiento_seguimiento(id_movimiento);


--
-- Name: movimiento_seguimiento movimiento_seguimiento_id_local_destino_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_seguimiento
    ADD CONSTRAINT movimiento_seguimiento_id_local_destino_fkey FOREIGN KEY (id_local_destino) REFERENCES public.local(id_local);


--
-- Name: movimiento_seguimiento movimiento_seguimiento_id_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_seguimiento
    ADD CONSTRAINT movimiento_seguimiento_id_movimiento_fkey FOREIGN KEY (id_movimiento) REFERENCES public.movimiento_inventario(id_movimiento_inventario);


--
-- Name: orden_compra_detalle orden_compra_detalle_id_proveedor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT orden_compra_detalle_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: orden_compra orden_compra_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT orden_compra_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: perfil_capacidad perfil_capacidad_id_perfil_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_capacidad
    ADD CONSTRAINT perfil_capacidad_id_perfil_fkey FOREIGN KEY (id_perfil) REFERENCES public.perfiles(id_perfil) ON DELETE CASCADE;


--
-- Name: permiso_recurso permiso_recurso_id_opcion_menu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permiso_recurso
    ADD CONSTRAINT permiso_recurso_id_opcion_menu_fkey FOREIGN KEY (id_opcion_menu) REFERENCES public.opcion_menu(id_opcion_menu) ON DELETE CASCADE;


--
-- Name: producto_stock_local producto_stock_local_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_stock_local
    ADD CONSTRAINT producto_stock_local_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: producto_stock_local producto_stock_local_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_stock_local
    ADD CONSTRAINT producto_stock_local_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: promocion_grupo promocion_grupo_id_promocion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_grupo
    ADD CONSTRAINT promocion_grupo_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- Name: promocion_opcion promocion_opcion_id_presentacion_venta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT promocion_opcion_id_presentacion_venta_fkey FOREIGN KEY (id_presentacion_venta) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: promocion_opcion promocion_opcion_id_promocion_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT promocion_opcion_id_promocion_grupo_fkey FOREIGN KEY (id_promocion_grupo) REFERENCES public.promocion_grupo(id_promocion_grupo);


--
-- Name: promocion_reposicion promocion_reposicion_id_presentacion_venta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_reposicion
    ADD CONSTRAINT promocion_reposicion_id_presentacion_venta_fkey FOREIGN KEY (id_presentacion_venta) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: promocion_reposicion promocion_reposicion_id_promocion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_reposicion
    ADD CONSTRAINT promocion_reposicion_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- Name: proveedor_categoria proveedor_categoria_id_categoria_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor_categoria
    ADD CONSTRAINT proveedor_categoria_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: proveedor_categoria proveedor_categoria_id_proveedor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor_categoria
    ADD CONSTRAINT proveedor_categoria_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor) ON DELETE CASCADE;


--
-- Name: salon_cobro salon_cobro_id_cliente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.cliente_comercial(id_cliente);


--
-- Name: salon_cobro salon_cobro_id_jornada_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_jornada_fkey FOREIGN KEY (id_jornada) REFERENCES public.inventario_jornada(id_jornada);


--
-- Name: salon_cobro salon_cobro_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: salon_cobro salon_cobro_id_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_movimiento_fkey FOREIGN KEY (id_movimiento) REFERENCES public.movimiento_inventario(id_movimiento_inventario);


--
-- Name: salon_cobro salon_cobro_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_cobro_pedido salon_cobro_pedido_id_cobro_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro_pedido
    ADD CONSTRAINT salon_cobro_pedido_id_cobro_fkey FOREIGN KEY (id_cobro) REFERENCES public.salon_cobro(id_cobro);


--
-- Name: salon_cobro_pedido salon_cobro_pedido_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro_pedido
    ADD CONSTRAINT salon_cobro_pedido_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.salon_pedido(id_pedido);


--
-- Name: salon_distribucion salon_distribucion_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_distribucion
    ADD CONSTRAINT salon_distribucion_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: salon_linea_anulada salon_linea_anulada_id_linea_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_linea_anulada
    ADD CONSTRAINT salon_linea_anulada_id_linea_fkey FOREIGN KEY (id_linea) REFERENCES public.salon_pedido_linea(id_linea);


--
-- Name: salon_linea_anulada salon_linea_anulada_id_responsable_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_linea_anulada
    ADD CONSTRAINT salon_linea_anulada_id_responsable_fkey FOREIGN KEY (id_responsable) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_pedido_asignacion salon_pedido_asignacion_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_asignacion
    ADD CONSTRAINT salon_pedido_asignacion_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.salon_pedido(id_pedido);


--
-- Name: salon_pedido_asignacion salon_pedido_asignacion_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_asignacion
    ADD CONSTRAINT salon_pedido_asignacion_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_pedido salon_pedido_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido
    ADD CONSTRAINT salon_pedido_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: salon_pedido salon_pedido_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido
    ADD CONSTRAINT salon_pedido_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_barra_libre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_barra_libre_fkey FOREIGN KEY (id_barra_libre) REFERENCES public.salon_pedido_linea(id_linea);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.salon_pedido(id_pedido);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_presentacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_promocion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- Name: unidad_medida_alias unidad_medida_alias_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida_alias
    ADD CONSTRAINT unidad_medida_alias_codigo_fkey FOREIGN KEY (codigo) REFERENCES public.unidad_medida(codigo);


--
-- Name: unidad_medida unidad_medida_codigo_base_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_codigo_base_fkey FOREIGN KEY (codigo_base) REFERENCES public.unidad_medida(codigo);


--
-- Name: unidad_medida_contexto unidad_medida_contexto_codigo_base_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida_contexto
    ADD CONSTRAINT unidad_medida_contexto_codigo_base_fkey FOREIGN KEY (codigo_base) REFERENCES public.unidad_medida(codigo);


--
-- Name: usuario_pin_salon usuario_pin_salon_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_pin_salon
    ADD CONSTRAINT usuario_pin_salon_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- PostgreSQL database dump complete
--

\unrestrict MtWFxBWdaENJbDoI1Cx2tC5XuSaQAuYDG91Daus2eJ3aWW2EcDoaFJhCXtNsRXQ
