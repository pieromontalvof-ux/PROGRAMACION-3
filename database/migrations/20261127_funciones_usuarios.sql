BEGIN;

CREATE OR REPLACE FUNCTION public.usuarios_perfiles_permitidos(p_id_perfil_gestor integer)
RETURNS TABLE (id_perfil integer, nombre character varying, puede_crear boolean, puede_editar boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_puestos()
RETURNS TABLE (id_puesto_laboral integer, nombre character varying, descripcion character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
    id_puesto_laboral,
    nombre,
    descripcion
FROM puesto_laboral
WHERE estado_registro = 1
ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.usuarios_listar(p_id_perfil_gestor integer, p_id_local integer)
RETURNS TABLE (id_usuario integer, dni character varying, nombres character varying, apellido_paterno character varying, apellido_materno character varying, celular character varying, correo_electronico character varying, estado_registro smallint, fecha_creacion date, ids_puestos_laborales integer[], puestos_laborales jsonb, ids_perfiles integer[], perfiles jsonb, ids_locales integer[], locales jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_perfil_gestionable(p_id_perfil_gestor integer, p_id_perfil_objetivo integer, p_crear boolean)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
    SELECT 1
    FROM perfil_gestion_usuario
    WHERE id_perfil_gestor = p_id_perfil_gestor
      AND id_perfil_objetivo = p_id_perfil_objetivo
      AND CASE WHEN p_crear THEN puede_crear ELSE puede_editar END = TRUE
      AND estado_registro = 1
)
$$;

CREATE OR REPLACE FUNCTION public.usuarios_buscar(p_id_usuario integer, p_id_perfil_gestor integer, p_id_local integer)
RETURNS TABLE (id_usuario integer, id integer, ids_perfiles integer[])
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_puestos_existen(p_cantidad integer, p_ids_puestos_laborales integer[])
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT COUNT(*) = p_cantidad
FROM puesto_laboral
WHERE id_puesto_laboral = ANY(p_ids_puestos_laborales)
  AND estado_registro = 1
$$;

CREATE OR REPLACE FUNCTION public.usuarios_dni_existe(p_dni text, p_excluir_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_correo_existe(p_correo text, p_excluir_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_crear(p_dni text, p_nombres text, p_apellido_paterno text, p_apellido_materno text, p_celular text, p_correo text, p_clave text, p_id_gestor integer)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_asignar_perfil(p_id_usuario integer, p_id_perfil integer, p_id_gestor integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_desactivar_perfiles(p_id_gestor integer, p_id_usuario integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE usuario_perfiles
SET
    estado_registro = 0,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
WHERE id_usuario = p_id_usuario
  AND estado_registro = 1
$$;

CREATE OR REPLACE FUNCTION public.usuarios_desactivar_puestos(p_id_gestor integer, p_id_usuario integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE usuario_puestos_laborales
SET estado_registro = 0,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
WHERE id_usuario = p_id_usuario
  AND estado_registro = 1
$$;

CREATE OR REPLACE FUNCTION public.usuarios_asignar_puesto(p_id_usuario integer, p_id_puesto_laboral integer, p_id_gestor integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_actualizar(p_dni text, p_nombres text, p_apellido_paterno text, p_apellido_materno text, p_celular text, p_correo text, p_clave text, p_id_gestor integer, p_id_usuario integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_cambiar_estado(p_estado integer, p_id_gestor integer, p_id_usuario integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE usuario
SET
    estado_registro = p_estado,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_DATE
WHERE id_usuario = p_id_usuario
$$;

CREATE OR REPLACE FUNCTION public.usuarios_locales_activos()
RETURNS TABLE (id_local integer, codigo character varying, nombre character varying, direccion character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_local, codigo, nombre, direccion
FROM local
WHERE estado_registro = 1
ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.usuarios_contar_locales(p_ids_locales integer[])
RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT COUNT(*)
FROM local
WHERE id_local = ANY(p_ids_locales)
  AND estado_registro = 1
$$;

CREATE OR REPLACE FUNCTION public.usuarios_desactivar_locales(p_id_gestor integer, p_id_usuario integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE usuario_local
SET
    estado_registro = 0,
    usuario_modificacion = p_id_gestor,
    fecha_modificacion = CURRENT_TIMESTAMP
WHERE id_usuario = p_id_usuario
  AND estado_registro = 1
$$;

CREATE OR REPLACE FUNCTION public.usuarios_asignar_local(p_id_usuario integer, p_id_local integer, p_id_gestor integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.usuarios_bloquear_locales()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    LOCK TABLE local IN SHARE ROW EXCLUSIVE MODE
$$;

CREATE OR REPLACE FUNCTION public.usuarios_siguiente_codigo_local()
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.usuarios_listar_locales()
RETURNS TABLE (id_local integer, codigo varchar, nombre varchar, direccion varchar, estado_registro smallint)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
    FROM local l ORDER BY length(l.codigo), l.codigo
$$;

CREATE OR REPLACE FUNCTION public.usuarios_crear_local(p_codigo text, p_nombre text, p_direccion text, p_usuario integer)
RETURNS TABLE (id_local integer, codigo varchar, nombre varchar, direccion varchar, estado_registro smallint)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    INSERT INTO local AS l (codigo, nombre, direccion, usuario_creacion)
    VALUES (p_codigo, p_nombre, p_direccion, p_usuario)
    RETURNING l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
$$;

CREATE OR REPLACE FUNCTION public.usuarios_bloquear_local(p_id integer)
RETURNS SETOF public.local
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT l.* FROM local l WHERE l.id_local = p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.usuarios_total_locales_activos()
RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT count(*) FROM local WHERE estado_registro = 1
$$;

CREATE OR REPLACE FUNCTION public.usuarios_local_tiene_datos(p_id integer)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.usuarios_eliminar_local(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    DELETE FROM local WHERE id_local = p_id
$$;

CREATE OR REPLACE FUNCTION public.usuarios_editar_local(p_id integer, p_nombre text, p_direccion text, p_usuario integer)
RETURNS TABLE (id_local integer, codigo varchar, nombre varchar, direccion varchar, estado_registro smallint)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE local AS l SET nombre = p_nombre, direccion = p_direccion,
        usuario_modificacion = p_usuario, fecha_modificacion = CURRENT_TIMESTAMP
    WHERE l.id_local = p_id
    RETURNING l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
$$;

CREATE OR REPLACE FUNCTION public.usuarios_estado_local(p_id integer, p_estado integer, p_usuario integer)
RETURNS TABLE (id_local integer, codigo varchar, nombre varchar, direccion varchar, estado_registro smallint)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
    UPDATE local AS l SET estado_registro = p_estado,
        usuario_modificacion = p_usuario, fecha_modificacion = CURRENT_TIMESTAMP
    WHERE l.id_local = p_id
    RETURNING l.id_local, l.codigo, l.nombre, l.direccion, l.estado_registro
$$;

COMMIT;
