BEGIN;

CREATE OR REPLACE FUNCTION public.auditoria_insertar_actividad(p_id_usuario integer, p_modulo text, p_accion text, p_id_registro_afectado integer, p_descripcion text, p_id_perfil_utilizado integer, p_id_puesto_laboral integer, p_id_local integer)
RETURNS bigint
LANGUAGE sql SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
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

CREATE OR REPLACE FUNCTION public.auditoria_actividades(p_limite integer, p_administrador boolean, p_id_local integer)
RETURNS TABLE (id_actividad_usuario bigint, id_usuario integer, usuario text, id_perfil_utilizado integer, perfil_utilizado varchar, id_puesto_laboral integer, puesto_laboral varchar, id_local integer, local varchar, modulo varchar, accion varchar, id_registro_afectado integer, descripcion varchar, fecha_actividad timestamp)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
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

CREATE OR REPLACE FUNCTION public.auditoria_insertar_cambio(p_id_usuario integer, p_id_perfil_utilizado integer, p_id_puesto_laboral integer, p_id_local integer, p_modulo text, p_accion text, p_tabla_afectada text, p_id_registro_afectado integer, p_datos_anteriores text, p_datos_nuevos text, p_motivo text)
RETURNS bigint
LANGUAGE sql SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
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

CREATE OR REPLACE FUNCTION public.auditoria_historial(p_local integer, p_globales boolean, p_desde date, p_hasta date, p_q text, p_patron text, p_offset integer)
RETURNS TABLE (origen text, id bigint, id_usuario integer, id_perfil_utilizado integer, id_puesto_laboral integer, id_local integer, modulo varchar, accion varchar, id_registro_afectado integer, descripcion varchar, fecha timestamp, tabla text, antes jsonb, despues jsonb, usuario text, perfil varchar, puesto varchar, local varchar, usuario_afectado text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
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

CREATE OR REPLACE FUNCTION public.auditoria_locales(p_local integer)
RETURNS TABLE (id_local integer, nombre varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
SELECT l.id_local,l.nombre FROM public.local l WHERE p_local IS NULL OR l.id_local=p_local ORDER BY l.nombre
$$;

COMMIT;
