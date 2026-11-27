BEGIN;

CREATE OR REPLACE FUNCTION public.catalogos_entidad_eliminable(p_entidad text)
RETURNS TABLE (tabla text, clave text, opcion integer, hijas jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.catalogos_comprobar_dependencias(
    p_tabla regclass, p_ids bigint[], p_permitidas jsonb
)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.catalogos_fila_auditoria(p_tabla regclass, p_fila jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.catalogos_filas_auditoria(p_tabla regclass, p_filas jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
    SELECT coalesce(jsonb_agg(public.catalogos_fila_auditoria(p_tabla, f.fila) ORDER BY f.posicion), '[]')
    FROM jsonb_array_elements(p_filas) WITH ORDINALITY AS f(fila,posicion)
$$;

CREATE OR REPLACE FUNCTION public.catalogos_eliminar_registro(p_entidad text, p_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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
$$;

COMMIT;
