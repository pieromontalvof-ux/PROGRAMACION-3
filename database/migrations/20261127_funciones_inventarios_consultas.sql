BEGIN;

CREATE OR REPLACE FUNCTION public.inv_repository_contar_productos_activos()
RETURNS TABLE (total bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT COUNT(*) AS total
        FROM producto
        WHERE activo = TRUE
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_buscar_inventario_de_hoy(p_id_local_actual integer)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, productos_contados bigint, usuario text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_buscar_ultimo_inventario_cerrado(p_id_local_actual integer)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, productos_contados bigint, usuario text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_buscar_ultimos_inventarios(p_id_local_actual integer, p_limite integer)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, fecha_registro timestamp without time zone, observacion character varying, productos_contados bigint, usuario text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_buscar_cabecera_inventario_actual(p_id_local_actual integer)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, usuario text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_consultar_productos_para_inventario(p_id_inventario_cierre integer)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, unidad character varying, id_categoria integer, categoria character varying, stock_contado numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_crear_inventario_actual(p_id_local_actual integer, p_fecha_inventario date, p_id_usuario integer)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_producto_activo_existe(p_id_producto integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
            SELECT 1
            FROM producto
            WHERE id_producto = p_id_producto
              AND activo = TRUE
        ) AS existe
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_guardar_detalle_inventario(p_id_inventario_cierre integer, p_id_producto integer, p_stock_contado numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_eliminar_detalle_inventario(p_id_inventario_cierre integer, p_id_producto integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
          AND id_producto = p_id_producto
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_contar_detalles_inventario(p_id_inventario_cierre integer)
RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT COUNT(*)
        FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_actualizar_estado_inventario(p_estado text, p_id_inventario_cierre integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE inventario_cierre
        SET estado_inventario = p_estado
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_buscar_inventario_por_fecha(p_id_local_actual integer, p_fecha_inventario date)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, usuario_registro integer, fecha_registro timestamp without time zone, observacion character varying, usuario text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_eliminar_inventario_provisional_1(p_id_inventario_cierre integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_eliminar_inventario_provisional_2(p_id_inventario_cierre integer)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
WITH eliminada AS (DELETE FROM inventario_cierre
        WHERE id_inventario_cierre =
              p_id_inventario_cierre
          AND estado_inventario IN (
              'BORRADOR',
              'INCOMPLETO'
          ) RETURNING 1) SELECT EXISTS(SELECT 1 FROM eliminada)
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_cerrar_inventario_en_base_datos(p_id_inventario_cierre integer)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_listar_inventarios_para_revision(p_id_local_actual integer)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, fecha_registro timestamp without time zone, usuario_registro integer, registrado_por text, usuario_revision integer, revisado_por text, motivo_revision character varying, observacion character varying, productos_contados bigint, productos_en_cero bigint, productos_con_existencia bigint, total_productos_actuales bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_buscar_inventario_cerrado_por_id(p_id_local_actual integer, p_id_inventario integer)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying, fecha_registro timestamp without time zone, usuario_registro integer, registrado_por text, usuario_revision integer, revisado_por text, motivo_revision character varying, observacion character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_actualizar_revision_inventario(p_id_usuario_revision integer, p_motivo_revision text, p_observacion text, p_id_inventario integer)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE inventario_cierre
        SET
            usuario_revision = p_id_usuario_revision,
            motivo_revision = p_motivo_revision,
            observacion = p_observacion
        WHERE id_inventario_cierre = p_id_inventario
          AND estado_inventario = 'CERRADO'
        RETURNING id_inventario_cierre
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_bloquear_inventario_cerrado(p_id_local_actual integer, p_id_inventario integer)
RETURNS TABLE (id_inventario_cierre integer, fecha_inventario date, estado_inventario character varying)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
            id_inventario_cierre,
            fecha_inventario,
            estado_inventario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=p_id_local_actual) inventario_cierre
        WHERE id_inventario_cierre = p_id_inventario
          AND estado_inventario = 'CERRADO'
        FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_buscar_producto_para_correccion(p_id_inventario integer, p_id_producto integer)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, activo boolean, id_inventario_cierre_detalle integer, stock_contado numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_crear_cabecera_correccion(p_id_inventario integer, p_id_usuario integer, p_motivo text, p_observacion text)
RETURNS bigint
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_crear_detalle_correccion(p_id_correccion bigint, p_id_producto integer, p_stock_anterior numeric, p_stock_nuevo numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_aplicar_stock_corregido_1(p_id_inventario integer, p_id_producto integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM inventario_cierre_detalle
            WHERE id_inventario_cierre = p_id_inventario
              AND id_producto = p_id_producto
$$;

CREATE OR REPLACE FUNCTION public.inv_repository_aplicar_stock_corregido_2(p_id_inventario integer, p_id_producto integer, p_stock_nuevo numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_repository_listar_historial_correcciones(p_id_inventario integer)
RETURNS TABLE (id_inventario_cierre_correccion bigint, fecha_correccion timestamp without time zone, motivo_correccion character varying, observacion character varying, corregido_por text, id_producto integer, codigo character varying, producto character varying, unidad character varying, stock_anterior numeric, stock_nuevo numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_weekly_report_1(p_local integer, p_desde date, p_hasta date)
RETURNS TABLE (fecha date, cobros bigint, cobros_con_inventario bigint, jornada_cerrada boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_weekly_report_2(p_local integer, p_desde date, p_hasta date)
RETURNS TABLE (fecha date, id_presentacion integer, id_promocion integer, nombre text, cantidad numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_weekly_report_3(p_local integer, p_desde date, p_hasta date)
RETURNS TABLE (fecha date, id_producto integer, cantidad numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT (c.creado_en AT TIME ZONE 'America/Lima')::date fecha,d.id_producto,sum(d.cantidad) cantidad
        FROM salon_cobro c JOIN movimiento_inventario m ON m.id_movimiento_inventario=c.id_movimiento AND m.id_local=c.id_local
        JOIN movimiento_inventario_detalle d USING(id_movimiento_inventario)
        WHERE c.id_local=p_local AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        GROUP BY 1,d.id_producto
$$;

CREATE OR REPLACE FUNCTION public.inv_weekly_report_4(p_local integer)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, unidad character varying, presentacion numeric, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, stock_actual numeric, compra_habilitada boolean, stock_minimo numeric, stock_maximo numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto,p.codigo,p.nombre,p.unidad,p.presentacion,p.id_categoria,cat.nombre categoria,
        p.id_proveedor,pr.nombre proveedor,s.stock_actual,
        coalesce(p.activo AND cat.activo AND pr.activo,false) compra_habilitada,
        coalesce(sl.stock_minimo,0) stock_minimo,sl.stock_maximo
        FROM producto p LEFT JOIN categoria_producto cat USING(id_categoria) LEFT JOIN proveedor pr USING(id_proveedor)
        LEFT JOIN inventario_stock_teorico s ON s.id_producto=p.id_producto AND s.id_local=p_local
        LEFT JOIN producto_stock_local sl ON sl.id_producto=p.id_producto AND sl.id_local=p_local
        WHERE p.activo OR coalesce(s.stock_actual,0)<>0 ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.inv_demand_report_1(p_local integer, p_desde date, p_hasta date)
RETURNS TABLE (id_presentacion integer, id_promocion integer, nombre text, id_item_carta integer, categoria character varying, cantidad numeric, total numeric, cantidad_en_promociones numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_demand_report_2(p_local integer, p_desde date, p_hasta date)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, unidad character varying, categoria character varying, stock_actual numeric, consumo_ventas numeric, entradas numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_demand_global_report_1(p_desde date, p_hasta date)
RETURNS TABLE (id_local integer, nombre character varying, cobros bigint, cobros_con_inventario bigint, dias_con_ventas bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT l.id_local,l.nombre,count(c.id_cobro) cobros,
        count(m.id_movimiento_inventario) cobros_con_inventario,
        count(DISTINCT (c.creado_en AT TIME ZONE 'America/Lima')::date) dias_con_ventas
        FROM local l LEFT JOIN salon_cobro c ON c.id_local=l.id_local AND c.comprobante->'anulacion' IS NULL
        AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN p_desde AND p_hasta
        LEFT JOIN movimiento_inventario m ON m.id_movimiento_inventario=c.id_movimiento AND m.id_local=l.id_local
        WHERE l.estado_registro=1 GROUP BY l.id_local,l.nombre ORDER BY l.id_local
$$;

CREATE OR REPLACE FUNCTION public.inv_demand_global_report_2()
RETURNS TABLE (id_local integer, id_producto integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_local,id_producto FROM inventario_saldo_inicial
                        UNION SELECT id_local,id_producto FROM inventario_evento
$$;

CREATE OR REPLACE FUNCTION public.inv_demand_global_report_3()
RETURNS TABLE (id_presentacion integer, nombre character varying, tipo character varying, contenido numeric, unidad character varying, precio numeric, activo boolean, menaje character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,ic.tipo,
        pv.contenido,pv.unidad,pv.precio,pv.activo,m.nombre menaje
        FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
        JOIN menaje m USING(id_menaje)
$$;

CREATE OR REPLACE FUNCTION public.inv_product_outlook_report_1(p_local integer, p_desde date, p_hasta date)
RETURNS TABLE (fecha date)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inv_product_outlook_report_2(p_local integer)
RETURNS TABLE (id_producto integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto FROM inventario_saldo_inicial WHERE id_local=p_local
                  UNION SELECT id_producto FROM inventario_evento WHERE id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.inv_product_outlook_report_3(p_local integer)
RETURNS TABLE (nombre character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT nombre FROM local WHERE id_local=p_local
$$;

COMMIT;
