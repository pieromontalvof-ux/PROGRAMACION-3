-- Carga local para Sheraton. Ejecutar en la misma transacción que la migración.
LOCK TABLE salon_cobro, salon_cierre_diario IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
    inicio constant date := DATE '2026-07-20';
    fin constant date := DATE '2026-11-19';
    etiqueta constant text := 'DEMO-SHERATON-VENTAS-20260720-20261119';
    gerente integer;
    dia date;
    momento timestamptz;
    movimiento integer;
    clave uuid;
    metodo text;
    linea jsonb;
    total numeric(12,2);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM local WHERE id_local = 4 AND lower(nombre) = 'sheraton')
        OR NOT EXISTS (SELECT 1 FROM salon_cobro WHERE id_local = 4
                       AND comprobante->>'prueba' LIKE 'DEMO-SHERATON-%') THEN
        RAISE EXCEPTION 'Se requiere la base local de demostración de Sheraton';
    END IF;
    IF EXISTS (SELECT 1 FROM salon_cobro WHERE id_local = 4
        AND (creado_en AT TIME ZONE 'America/Lima')::date BETWEEN inicio AND fin
        AND NOT coalesce(comprobante->>'prueba' LIKE 'DEMO-SHERATON-%', false)) THEN
        RAISE EXCEPTION 'El rango contiene ventas ajenas a la demostración';
    END IF;

    SELECT min(id_usuario) INTO gerente FROM usuario_local
    JOIN usuario_perfiles USING (id_usuario)
    JOIN usuario USING (id_usuario)
    WHERE usuario_local.id_local = 4 AND usuario_perfiles.id_perfil = 2
      AND usuario_local.estado_registro = 1 AND usuario_perfiles.estado_registro = 1
      AND usuario.estado_registro = 1;
    IF gerente IS NULL THEN
        RAISE EXCEPTION 'Falta gerente activo del local de demostración';
    END IF;

    FOR dia IN SELECT inicio + n FROM generate_series(0, fin - inicio) AS n LOOP
        IF EXISTS (SELECT 1 FROM salon_cierre_diario WHERE id_local = 4 AND fecha = dia) THEN
            CONTINUE;
        END IF;
        momento := (dia + time '19:30') AT TIME ZONE 'America/Lima';
        clave := md5(etiqueta || dia::text)::uuid;
        metodo := CASE WHEN extract(isodow FROM dia) IN (5, 6, 7) THEN 'TARJETA' ELSE 'EFECTIVO' END;

        SELECT jsonb_build_object('nombre', producto->>'nombre', 'precio', producto->'precio',
            'cantidad', 1 + (dia - inicio) % 3, 'opciones', '[]'::jsonb,
            'comentario', 'Venta simulada de demostración')
        INTO STRICT linea
        FROM salon_cobro c CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') producto
        WHERE c.id_local = 4 AND c.comprobante->>'prueba' LIKE 'DEMO-SHERATON-%'
          AND producto->>'nombre' IS NOT NULL AND (producto->>'precio')::numeric > 0
        ORDER BY abs(extract(epoch FROM c.creado_en - momento)), c.id_cobro, producto->>'nombre'
        LIMIT 1;
        total := (linea->>'precio')::numeric * (linea->>'cantidad')::integer;

        -- El vínculo es obligatorio para el comprobante. Sin detalle no hay consumo.
        INSERT INTO movimiento_inventario
            (codigo, tipo_movimiento, motivo_movimiento, fecha_movimiento, usuario_registro,
             id_local, observacion, registrado_en)
        VALUES ('DSVF-' || to_char(dia, 'YYYYMMDD'), 'SALIDA', 'VENTA_SALON', dia, gerente,
                4, etiqueta || ' · simulación sin consumo de inventario', momento AT TIME ZONE 'America/Lima')
        RETURNING id_movimiento_inventario INTO movimiento;

        INSERT INTO salon_cobro
            (id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento,
             cliente, total, comprobante, id_movimiento, creado_en)
        VALUES (4, gerente, 'M01', clave, md5(clave::text), 'FACTURA', metodo, '00000000000',
                'Cliente ficticio de demostración', total, jsonb_build_object(
                    'tipo', 'FACTURA', 'metodo', metodo, 'documento', '00000000000',
                    'cliente', 'Cliente ficticio de demostración', 'local', 'Sheraton', 'mesa', 'M01',
                    'total', total, 'fiscal', false, 'lineas', jsonb_build_array(linea),
                    'usuario', 'Simulación', 'prueba', etiqueta, 'nota', 'SIMULACIÓN SIN VALIDEZ TRIBUTARIA'),
                movimiento, momento);

        INSERT INTO salon_cierre_diario (id_local, fecha, simulacion, cantidad, efectivo, tarjeta)
        SELECT 4, dia, true, count(*),
            coalesce(sum(c.total) FILTER (WHERE c.metodo = 'EFECTIVO'), 0),
            coalesce(sum(c.total) FILTER (WHERE c.metodo = 'TARJETA'), 0)
        FROM salon_cobro c
        WHERE c.id_local = 4 AND c.creado_en >= (dia::timestamp AT TIME ZONE 'America/Lima')
          AND c.creado_en < ((dia + 1)::timestamp AT TIME ZONE 'America/Lima')
          AND c.comprobante->'anulacion' IS NULL;
    END LOOP;
END $$;
