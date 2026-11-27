BEGIN;

-- Los sistemas antiguos pueden no tener instalado el inventario operativo.
SET LOCAL check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.stock_minimo_por_local(p_producto integer, p_local integer, p_minimo_general numeric)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inventario_operativo_instalado()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT to_regclass('public.inventario_evento') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.inventario_stock_consulta_operativo(p_local integer)
RETURNS TABLE (
    id_producto integer, codigo character varying, nombre character varying, unidad character varying, id_categoria integer, categoria character varying, stock_minimo numeric, stock_maximo numeric, fecha_ultimo_conteo date, stock_ultimo_conteo numeric, stock_actual numeric, entradas_recepcion numeric, entradas_movimiento numeric, salidas_movimiento numeric, estado_stock text
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inventario_stock_consulta_historico(p_local integer)
RETURNS TABLE (
    id_producto integer, codigo character varying, nombre character varying, unidad character varying, stock_minimo numeric, id_categoria integer, categoria character varying, fecha_ultimo_conteo date, stock_ultimo_conteo numeric, entradas_recepcion numeric, entradas_movimiento numeric, salidas_movimiento numeric, stock_actual numeric, estado_stock text
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.inventario_productos_revision(p_local integer, p_inventario integer)
RETURNS TABLE (
    id_producto integer, codigo character varying, producto character varying, categoria character varying, unidad character varying, stock_minimo numeric, activo boolean, stock_contado numeric, fue_contado boolean
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.compras_productos_sugeridos_operativo(p_local integer)
RETURNS TABLE (
    id_producto integer, codigo character varying, nombre character varying, unidad character varying, presentacion numeric, stock_minimo numeric, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, stock_actual numeric, consumo_total numeric, origen_consumo text
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.compras_productos_sugeridos_historico(p_local integer)
RETURNS TABLE (
    id_producto integer, codigo character varying, nombre character varying, unidad character varying, presentacion numeric, stock_minimo numeric, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, stock_actual numeric, consumo_total numeric
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

SET LOCAL check_function_bodies = on;
COMMIT;
