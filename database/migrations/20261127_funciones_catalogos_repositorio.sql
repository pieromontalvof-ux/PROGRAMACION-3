BEGIN;

CREATE OR REPLACE FUNCTION public.catalogos_origen_categorias_proveedor()
RETURNS TABLE (id_proveedor integer,id_categoria integer)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
BEGIN
    IF to_regclass('public.proveedor_categoria') IS NOT NULL THEN
        RETURN QUERY SELECT pc.id_proveedor, pc.id_categoria FROM public.proveedor_categoria pc;
    ELSE
        RETURN QUERY SELECT DISTINCT p.id_proveedor, p.id_categoria FROM public.producto p;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogos_categorias_proveedor_disponibles()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.proveedor_categoria') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.catalogos_listar_productos()
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, id_categoria integer, categoria character varying, id_proveedor integer, proveedor character varying, unidad character varying, stock_minimo numeric, presentacion numeric, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.catalogos_listar_categorias_producto()
RETURNS TABLE (id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT
            id_categoria,
            nombre,
            prefijo,
            siguiente_numero,
            activo
        FROM categoria_producto
        ORDER BY nombre ASC
$$;

CREATE OR REPLACE FUNCTION public.catalogos_listar_categorias_producto_detalladas()
RETURNS TABLE (id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean, total_productos bigint, productos_activos bigint, productos_inactivos bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.catalogos_listar_proveedores()
RETURNS TABLE (id_proveedor integer, nombre character varying, activo boolean, datos_comerciales jsonb, ids_categorias integer[])
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.catalogos_listar_proveedores_detallados(p_id integer)
RETURNS SETOF character varying
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT cp.nombre FROM public.catalogos_origen_categorias_proveedor() pc
            JOIN categoria_producto cp USING(id_categoria)
            WHERE pc.id_proveedor = p_id ORDER BY cp.nombre
$$;

CREATE OR REPLACE FUNCTION public.catalogos_categorias_proveedor(p_id integer)
RETURNS SETOF integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_categoria FROM public.catalogos_origen_categorias_proveedor() pc
        WHERE id_proveedor = p_id ORDER BY id_categoria
$$;

CREATE OR REPLACE FUNCTION public.catalogos_asignar_categorias_proveedor_1(p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM proveedor_categoria WHERE id_proveedor = p_id
$$;

CREATE OR REPLACE FUNCTION public.catalogos_asignar_categorias_proveedor_2(p_id integer, p_categoria integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO proveedor_categoria (id_proveedor, id_categoria)
            VALUES (p_id, p_categoria)
$$;

CREATE OR REPLACE FUNCTION public.catalogos_obtener_categoria(p_id_categoria integer)
RETURNS TABLE (id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_categoria, nombre, prefijo,
                   siguiente_numero, activo
            FROM categoria_producto
            WHERE id_categoria = p_id_categoria
$$;

CREATE OR REPLACE FUNCTION public.catalogos_obtener_categoria_bloqueado(p_id_categoria integer)
RETURNS TABLE (id_categoria integer, nombre character varying, prefijo character varying, siguiente_numero integer, activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_categoria, nombre, prefijo,
                   siguiente_numero, activo
            FROM categoria_producto
            WHERE id_categoria = p_id_categoria FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.catalogos_categoria_repetida(p_excluir_id integer, p_nombre text, p_prefijo text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
                SELECT 1 FROM categoria_producto
                WHERE (p_excluir_id IS NULL OR id_categoria <> p_excluir_id)
                  AND (
                    LOWER(BTRIM(nombre)) = LOWER(BTRIM(p_nombre))
                    OR UPPER(BTRIM(prefijo)) = UPPER(BTRIM(p_prefijo))
                  )
            )
$$;

CREATE OR REPLACE FUNCTION public.catalogos_crear_categoria(p_nombre text, p_prefijo text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO categoria_producto
                (nombre, prefijo, siguiente_numero, activo)
            VALUES (p_nombre, p_prefijo, 1, TRUE)
            RETURNING id_categoria
$$;

CREATE OR REPLACE FUNCTION public.catalogos_actualizar_categoria(p_nombre text, p_prefijo text, p_id_categoria integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE categoria_producto
            SET nombre = p_nombre, prefijo = p_prefijo
            WHERE id_categoria = p_id_categoria
$$;

CREATE OR REPLACE FUNCTION public.catalogos_productos_categoria(p_id_categoria integer, p_solo_activos boolean)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto, p.codigo, p.nombre, p.activo
            FROM producto p
            WHERE p.id_categoria = p_id_categoria AND (NOT p_solo_activos OR p.activo) ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.catalogos_cambiar_estado_categoria(p_activo boolean, p_id_categoria integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE categoria_producto SET activo = p_activo
            WHERE id_categoria = p_id_categoria
$$;

CREATE OR REPLACE FUNCTION public.catalogos_reasignar_categoria_productos_1(p_nueva integer, p_anterior integer, p_ids integer[])
RETURNS SETOF integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE producto
            SET id_categoria = p_nueva
            WHERE id_categoria = p_anterior
              AND id_producto = ANY(p_ids)
            RETURNING id_producto
$$;

CREATE OR REPLACE FUNCTION public.catalogos_reasignar_categoria_productos_2(p_id_producto integer, p_anterior integer, p_nueva integer, p_usuario integer, p_motivo text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO producto_categoria_historial (
                    id_producto, id_categoria_anterior,
                    id_categoria_nueva, usuario_cambio, motivo
                ) VALUES (
                    p_id_producto, p_anterior, p_nueva, p_usuario, p_motivo
                )
$$;

CREATE OR REPLACE FUNCTION public.catalogos_obtener_proveedor(p_id_proveedor integer)
RETURNS TABLE (id_proveedor integer, nombre character varying, activo boolean, datos_comerciales jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_proveedor, nombre, activo, datos_comerciales
            FROM proveedor
            WHERE id_proveedor = p_id_proveedor
$$;

CREATE OR REPLACE FUNCTION public.catalogos_obtener_proveedor_bloqueado(p_id_proveedor integer)
RETURNS TABLE (id_proveedor integer, nombre character varying, activo boolean, datos_comerciales jsonb)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_proveedor, nombre, activo, datos_comerciales
            FROM proveedor
            WHERE id_proveedor = p_id_proveedor FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.catalogos_proveedor_repetido(p_nombre text, p_excluir_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
                SELECT 1 FROM proveedor
                WHERE LOWER(BTRIM(nombre)) = LOWER(BTRIM(p_nombre))
                  AND (p_excluir_id IS NULL OR id_proveedor <> p_excluir_id)
            )
$$;

CREATE OR REPLACE FUNCTION public.catalogos_crear_proveedor(p_nombre text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO proveedor (nombre, activo)
            VALUES (p_nombre, TRUE)
            RETURNING id_proveedor
$$;

CREATE OR REPLACE FUNCTION public.catalogos_actualizar_proveedor(p_nombre text, p_id_proveedor integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE proveedor SET nombre = p_nombre
            WHERE id_proveedor = p_id_proveedor
$$;

CREATE OR REPLACE FUNCTION public.catalogos_productos_proveedor(p_id_proveedor integer, p_solo_activos boolean)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, activo boolean, id_categoria integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.id_producto, p.codigo, p.nombre, p.activo,
                   p.id_categoria
            FROM producto p
            WHERE p.id_proveedor = p_id_proveedor AND (NOT p_solo_activos OR p.activo) ORDER BY p.nombre
$$;

CREATE OR REPLACE FUNCTION public.catalogos_cambiar_estado_proveedor(p_activo boolean, p_id_proveedor integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE proveedor SET activo = p_activo
            WHERE id_proveedor = p_id_proveedor
$$;

CREATE OR REPLACE FUNCTION public.catalogos_reasignar_proveedor_productos_1(p_nuevo integer, p_anterior integer, p_ids integer[])
RETURNS SETOF integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE producto
            SET id_proveedor = p_nuevo
            WHERE id_proveedor = p_anterior
              AND id_producto = ANY(p_ids)
            RETURNING id_producto
$$;

CREATE OR REPLACE FUNCTION public.catalogos_reasignar_proveedor_productos_2(p_id_producto integer, p_anterior integer, p_nuevo integer, p_usuario integer, p_motivo text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO producto_proveedor_historial (
                    id_producto, id_proveedor_anterior,
                    id_proveedor_nuevo, usuario_cambio, motivo
                ) VALUES (
                    p_id_producto, p_anterior, p_nuevo, p_usuario, p_motivo
                )
$$;

CREATE OR REPLACE FUNCTION public.catalogos_obtener_producto(p_id_producto integer)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, id_categoria integer, id_proveedor integer, unidad character varying, stock_minimo numeric, presentacion numeric, activo boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto, codigo, nombre, id_categoria,
                   id_proveedor, unidad, stock_minimo,
                   presentacion, activo
            FROM producto
            WHERE id_producto = p_id_producto
$$;

CREATE OR REPLACE FUNCTION public.catalogos_obtener_producto_bloqueado(p_id_producto integer)
RETURNS TABLE (id_producto integer, codigo character varying, nombre character varying, id_categoria integer, id_proveedor integer, unidad character varying, stock_minimo numeric, presentacion numeric, activo boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_producto, codigo, nombre, id_categoria,
                   id_proveedor, unidad, stock_minimo,
                   presentacion, activo
            FROM producto
            WHERE id_producto = p_id_producto FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.catalogos_generar_codigo_producto(p_id_categoria integer)
RETURNS TABLE (prefijo varchar, numero integer)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE categoria_producto
            SET siguiente_numero = siguiente_numero + 1
            WHERE id_categoria = p_id_categoria AND activo = TRUE
            RETURNING prefijo, siguiente_numero - 1 AS numero
$$;

CREATE OR REPLACE FUNCTION public.catalogos_producto_repetido(p_nombre text, p_excluir_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS (
                SELECT 1 FROM producto
                WHERE LOWER(BTRIM(nombre)) = LOWER(BTRIM(p_nombre))
                  AND (p_excluir_id IS NULL OR id_producto <> p_excluir_id)
            )
$$;

CREATE OR REPLACE FUNCTION public.catalogos_crear_producto_registro(p_codigo text, p_nombre text, p_categoria integer, p_proveedor integer, p_unidad text, p_presentacion numeric)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO producto (
                codigo, nombre, id_categoria, id_proveedor,
                unidad, presentacion, activo
            ) VALUES (
                p_codigo, p_nombre, p_categoria, p_proveedor,
                p_unidad, p_presentacion, TRUE
            ) RETURNING id_producto
$$;

CREATE OR REPLACE FUNCTION public.catalogos_actualizar_producto_registro(p_nombre text, p_categoria integer, p_proveedor integer, p_unidad text, p_presentacion numeric, p_id_producto integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE producto
            SET nombre = p_nombre,
                id_categoria = p_categoria,
                id_proveedor = p_proveedor,
                unidad = p_unidad,
                presentacion = p_presentacion
            WHERE id_producto = p_id_producto
$$;

CREATE OR REPLACE FUNCTION public.catalogos_cambiar_estado_producto(p_activo boolean, p_id_producto integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE producto SET activo = p_activo
            WHERE id_producto = p_id_producto
$$;

CREATE OR REPLACE FUNCTION public.catalogos_dependencias_producto(p_id integer)
RETURNS TABLE (recetas bigint, subproductos bigint, salsas_activas bigint, ordenes bigint, recepciones bigint, inventarios bigint, movimientos bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.catalogos_guardar_historial_categoria_producto(p_producto integer, p_anterior integer, p_nueva integer, p_usuario integer, p_motivo text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO producto_categoria_historial (
            id_producto, id_categoria_anterior, id_categoria_nueva,
            usuario_cambio, motivo
        ) VALUES (p_producto, p_anterior, p_nueva, p_usuario, p_motivo)
$$;

CREATE OR REPLACE FUNCTION public.catalogos_guardar_historial_proveedor_producto(p_producto integer, p_anterior integer, p_nuevo integer, p_usuario integer, p_motivo text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO producto_proveedor_historial (
            id_producto, id_proveedor_anterior, id_proveedor_nuevo,
            usuario_cambio, motivo
        ) VALUES (p_producto, p_anterior, p_nuevo, p_usuario, p_motivo)
$$;

CREATE OR REPLACE FUNCTION public.catalogos_guardar_comercial_proveedor(p_datos text, p_id integer)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE proveedor SET datos_comerciales=CAST(p_datos AS jsonb) WHERE id_proveedor=p_id
$$;

CREATE OR REPLACE FUNCTION public.catalogos_ruc_proveedor_repetido(p_ruc text, p_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM proveedor WHERE datos_comerciales->>'ruc'=p_ruc AND (p_id IS NULL OR id_proveedor<>p_id))
$$;

COMMIT;
