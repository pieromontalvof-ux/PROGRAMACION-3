BEGIN;

CREATE OR REPLACE FUNCTION public.locales_permitidos(p_usuario integer, p_perfil integer)
RETURNS TABLE (id_local integer, codigo varchar, nombre varchar, direccion varchar)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
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

CREATE OR REPLACE FUNCTION public.local_permitido(p_usuario integer, p_perfil integer, p_local integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT EXISTS (SELECT 1 FROM public.locales_permitidos(p_usuario,p_perfil) l WHERE l.id_local=p_local)
$$;

CREATE OR REPLACE FUNCTION public.operaciones_por_local_listas()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
    SELECT EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid=to_regclass('public.inventario_cierre')
          AND conname='uq_inventario_local_fecha' AND convalidated)
$$;

CREATE OR REPLACE FUNCTION public.registro_de_local(p_tipo text, p_identidad integer, p_local integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO pg_catalog, public AS $$
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

COMMIT;
