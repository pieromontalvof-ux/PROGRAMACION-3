BEGIN;

CREATE OR REPLACE FUNCTION public.salon_usuario_miembro(p_usuario integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.salon_usuario_elegible(p_usuario integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT public.salon_usuario_miembro(p_usuario) OR EXISTS (
    SELECT 1 FROM usuario_perfiles up JOIN perfiles pf USING (id_perfil)
    WHERE up.id_usuario = p_usuario AND public.perfil_tiene_capacidad(up.id_perfil, 'supervisar_salon')
      AND up.estado_registro = 1 AND pf.estado_registro = 1
)
$$;

CREATE OR REPLACE FUNCTION public.salon_perfil(p_id bigint)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT min(up.id_perfil) FROM usuario_perfiles up JOIN perfiles p USING(id_perfil) WHERE up.id_usuario=p_id AND (public.perfil_tiene_capacidad(up.id_perfil, 'atender_salon') OR public.perfil_tiene_capacidad(up.id_perfil, 'supervisar_salon')) AND up.estado_registro=1 AND p.estado_registro=1
$$;

CREATE OR REPLACE FUNCTION public.salon_pin_instalado()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.usuario_pin_salon') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.salon_elegible(p_id bigint)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT 1 FROM usuario u WHERE u.id_usuario=p_id AND public.salon_usuario_elegible(u.id_usuario)
$$;

CREATE OR REPLACE FUNCTION public.salon_eliminar_pin(p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM usuario_pin_salon WHERE id_usuario=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_guardar_pin(p_id bigint, p_hash text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO usuario_pin_salon(id_usuario,pin_hash) VALUES(p_id,p_hash)
          ON CONFLICT(id_usuario) DO UPDATE SET pin_hash=EXCLUDED.pin_hash,
          version=usuario_pin_salon.version+1,fallos=0,bloqueado_hasta=NULL,actualizado_en=clock_timestamp()
$$;

CREATE OR REPLACE FUNCTION public.salon_locales()
RETURNS TABLE ("id_local" integer, "nombre" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_local,nombre FROM local WHERE estado_registro=1 ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.salon_usuarios(p_local bigint)
RETURNS TABLE ("id_usuario" integer, "nombre" text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) AS nombre
        FROM usuario u JOIN usuario_pin_salon pin USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.estado_registro=1 AND ul.estado_registro=1 AND l.estado_registro=1
          AND ul.id_local=p_local AND public.salon_usuario_elegible(u.id_usuario) ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.salon_limpiar_intentos()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM salon_intentos WHERE inicio<clock_timestamp()-interval '1 day'
$$;

CREATE OR REPLACE FUNCTION public.salon_incrementar_intentos(p_origen text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_intentos(origen,intentos) VALUES(p_origen,1)
      ON CONFLICT(origen) DO UPDATE SET
        intentos=CASE WHEN salon_intentos.inicio<clock_timestamp()-interval '5 minutes' THEN 1 ELSE salon_intentos.intentos+1 END,
        inicio=CASE WHEN salon_intentos.inicio<clock_timestamp()-interval '5 minutes' THEN clock_timestamp() ELSE salon_intentos.inicio END
      RETURNING intentos
$$;

CREATE OR REPLACE FUNCTION public.salon_verificar_pin(p_usuario bigint, p_local bigint)
RETURNS TABLE ("id_usuario" integer, "pin_hash" text, "version" integer, "fallos" integer, "bloqueado_hasta" timestamp with time zone, "actualizado_en" timestamp with time zone, "nombres" character varying, "local" character varying, "bloqueado" boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pin.*,u.nombres,l.nombre AS local,
        pin.bloqueado_hasta>clock_timestamp() AS bloqueado
        FROM usuario_pin_salon pin JOIN usuario u USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.id_usuario=p_usuario AND ul.id_local=p_local AND u.estado_registro=1
          AND ul.estado_registro=1 AND l.estado_registro=1 AND public.salon_usuario_elegible(u.id_usuario) FOR UPDATE OF pin
$$;

CREATE OR REPLACE FUNCTION public.salon_fallo_pin(p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE usuario_pin_salon SET bloqueado_hasta=CASE WHEN fallos>=4 THEN clock_timestamp()+interval '5 minutes' ELSE NULL END,
    fallos=CASE WHEN fallos>=4 THEN 0 ELSE fallos+1 END WHERE id_usuario=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_reiniciar_pin(p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE usuario_pin_salon SET fallos=0,bloqueado_hasta=NULL WHERE id_usuario=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_sesion(p_usuario bigint, p_local bigint)
RETURNS TABLE ("nombres" character varying, "local" character varying, "version" integer, "actualizado_en" timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT u.nombres,l.nombre AS local,pin.version,pin.actualizado_en
        FROM usuario u JOIN usuario_pin_salon pin USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.id_usuario=p_usuario AND ul.id_local=p_local AND ul.estado_registro=1
          AND u.estado_registro=1 AND l.estado_registro=1 AND public.salon_usuario_elegible(u.id_usuario)
$$;

CREATE OR REPLACE FUNCTION public.salon_mesas_control(p_local bigint)
RETURNS TABLE ("mesa" character varying, "id_usuario" integer, "usuario" text, "desde" timestamp with time zone)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.mesa,p.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) AS usuario,
 min(p.creado_en) AS desde FROM salon_pedido_actual p JOIN usuario u USING(id_usuario)
 WHERE p.id_local=p_local GROUP BY p.mesa,p.id_usuario,u.nombres,u.apellido_paterno ORDER BY p.mesa
$$;

CREATE OR REPLACE FUNCTION public.salon_bloquear_pin(p_id bigint)
RETURNS TABLE ("id_usuario" integer, "pin_hash" text, "version" integer, "fallos" integer, "bloqueado_hasta" timestamp with time zone, "actualizado_en" timestamp with time zone, "bloqueado" boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT *,bloqueado_hasta>clock_timestamp() AS bloqueado FROM usuario_pin_salon WHERE id_usuario=p_id FOR UPDATE
$$;

CREATE OR REPLACE FUNCTION public.salon_pin_vigente(p_id bigint)
RETURNS TABLE ("version" integer, "actualizado_en" timestamp with time zone)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT version,actualizado_en FROM usuario_pin_salon WHERE id_usuario=p_id FOR SHARE
$$;

CREATE OR REPLACE FUNCTION public.salon_consumir_autorizacion(p_id text)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_autorizacion_usada(clave) VALUES(CAST(p_id AS uuid)) ON CONFLICT DO NOTHING RETURNING clave
$$;

CREATE OR REPLACE FUNCTION public.salon_bloqueo(p_clave text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock(hashtext(p_clave))
$$;

CREATE OR REPLACE FUNCTION public.salon_pedidos(p_local bigint, p_mesa text)
RETURNS TABLE ("id_pedido" bigint, "id_local" integer, "mesa" character varying, "id_usuario" integer, "estado" character varying, "version" integer, "creado_en" timestamp with time zone, "enviado_en" timestamp with time zone, "envio_clave" uuid, "envio_hash" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT * FROM salon_pedido_actual WHERE id_local=p_local AND mesa=p_mesa ORDER BY id_pedido
$$;

CREATE OR REPLACE FUNCTION public.salon_meseros(p_local bigint)
RETURNS TABLE ("id_usuario" integer, "nombre" text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) AS nombre
 FROM usuario u JOIN usuario_local ul USING(id_usuario) JOIN usuario_pin_salon pin USING(id_usuario)
 WHERE ul.id_local=p_local AND ul.estado_registro=1 AND u.estado_registro=1 AND public.salon_usuario_miembro(u.id_usuario) ORDER BY nombre
$$;

CREATE OR REPLACE FUNCTION public.salon_lineas_anulables(p_local bigint, p_mesa text, p_ids bigint[])
RETURNS TABLE ("id_linea" bigint, "nombre" text, "cantidad" integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT l.id_linea,l.nombre,l.cantidad FROM salon_pedido_linea l JOIN salon_pedido_actual p USING(id_pedido)
    WHERE p.id_local=p_local AND p.mesa=p_mesa AND p.estado='ENVIADO' AND l.id_linea=ANY(p_ids)
    AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea)
$$;

CREATE OR REPLACE FUNCTION public.salon_reposiciones_anulables(p_ids bigint[])
RETURNS TABLE ("id_linea" bigint, "nombre" text, "cantidad" integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_linea,nombre,cantidad FROM salon_pedido_linea
    WHERE id_barra_libre=ANY(p_ids) AND NOT EXISTS(
     SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=salon_pedido_linea.id_linea)
$$;

CREATE OR REPLACE FUNCTION public.salon_anular_linea(p_id bigint, p_usuario bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_linea_anulada(id_linea,id_responsable) VALUES(p_id,p_usuario)
$$;

CREATE OR REPLACE FUNCTION public.salon_mesero_bloqueado(p_id bigint, p_local bigint)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT u.id_usuario FROM usuario u JOIN usuario_local ul USING(id_usuario) JOIN usuario_pin_salon pin USING(id_usuario)
     WHERE u.id_usuario=p_id AND ul.id_local=p_local AND ul.estado_registro=1 AND u.estado_registro=1 AND public.salon_usuario_miembro(u.id_usuario) FOR SHARE OF u,ul,pin
$$;

CREATE OR REPLACE FUNCTION public.salon_asignar_pedido(p_id bigint, p_mesa text, p_usuario bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_pedido_asignacion(id_pedido,mesa,id_usuario) VALUES(p_id,p_mesa,p_usuario) ON CONFLICT(id_pedido) DO UPDATE SET mesa=excluded.mesa,id_usuario=excluded.id_usuario
$$;

CREATE OR REPLACE FUNCTION public.salon_cierres_instalados()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_cierre_diario') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.salon_cierres_diarios(p_local bigint, p_desde date, p_fin date)
RETURNS TABLE ("fecha" date, "simulacion" boolean, "cantidad" integer, "efectivo" numeric, "tarjeta" numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT fecha, simulacion, cantidad, efectivo, tarjeta
FROM public.salon_cierre_diario
WHERE id_local = p_local AND fecha >= p_desde AND fecha < p_fin
ORDER BY fecha DESC
$$;

CREATE OR REPLACE FUNCTION public.salon_distribucion_instalada()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_distribucion') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.salon_distribucion(p_local bigint)
RETURNS TABLE ("version" integer, "elementos" jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT version,elementos FROM salon_distribucion WHERE id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.salon_pedidos_instalados()
RETURNS regclass
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_pedido')
$$;

CREATE OR REPLACE FUNCTION public.salon_control_instalado()
RETURNS regclass
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_pedido_actual')
$$;

CREATE OR REPLACE FUNCTION public.salon_mesas_usadas(p_local bigint)
RETURNS TABLE ("mesa" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT DISTINCT mesa FROM salon_pedido_actual WHERE id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.salon_guardar_distribucion(p_local bigint, p_elementos text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_distribucion(id_local,version,elementos) VALUES(p_local,1,CAST(p_elementos AS jsonb)) ON CONFLICT(id_local) DO UPDATE SET version=salon_distribucion.version+1,elementos=excluded.elementos
$$;

CREATE OR REPLACE FUNCTION public.salon_bloqueo_compartido(p_clave text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock_shared(hashtext(p_clave))
$$;

CREATE OR REPLACE FUNCTION public.salon_pedidos_instalados_existe()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_pedido') IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.salon_envios_instalados()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='salon_pedido' AND column_name='envio_clave')
$$;

CREATE OR REPLACE FUNCTION public.salon_promociones_instaladas()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.promocion_reposicion') IS NOT NULL AND EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='salon_pedido_linea' AND column_name='id_promocion')
$$;

CREATE OR REPLACE FUNCTION public.salon_catalogo()
RETURNS TABLE ("id" integer, "nombre" character varying, "contenido" numeric, "unidad" character varying, "precio" numeric, "id_categoria" integer, "categoria" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pv.id_presentacion_venta AS id,ic.nombre,pv.contenido,pv.unidad,pv.precio,
  cc.id_categoria_carta AS id_categoria,cc.nombre AS categoria
FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
JOIN categoria_carta cc USING(id_categoria_carta)
WHERE pv.activo AND ic.activo AND cc.activo ORDER BY cc.nombre,ic.nombre,pv.contenido
$$;

CREATE OR REPLACE FUNCTION public.salon_grupos_salsa()
RETURNS TABLE ("id_grupo_salsa" integer, "id_presentacion_venta" integer, "cantidad_maxima" smallint, "permite_repetir" boolean, "id" integer, "nombre" character varying, "cantidad" numeric, "unidad" character varying, "id_producto" integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT gs.id_grupo_salsa,gs.id_presentacion_venta,
       gs.cantidad_maxima,gs.permite_repetir,gso.id_grupo_salsa_opcion AS id,
       p.nombre,gso.cantidad,p.unidad,gso.id_producto
       FROM grupo_salsa gs LEFT JOIN grupo_salsa_opcion gso ON gso.id_grupo_salsa=gs.id_grupo_salsa AND gso.activo
       LEFT JOIN producto p ON p.id_producto=gso.id_producto AND p.activo
       WHERE gs.activo ORDER BY gs.id_grupo_salsa,p.nombre
$$;

CREATE OR REPLACE FUNCTION public.salon_promociones_activas()
RETURNS TABLE ("id_promocion" integer, "nombre" character varying, "precio" numeric)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
WITH reloj AS (SELECT (clock_timestamp() AT TIME ZONE 'America/Lima')::time AS hora)
SELECT p.id_promocion,p.nombre,p.precio FROM promocion p CROSS JOIN reloj
WHERE p.activo AND (p.hora_inicio IS NULL OR p.hora_fin IS NULL OR
  CASE WHEN p.hora_inicio<p.hora_fin THEN reloj.hora>=p.hora_inicio AND reloj.hora<p.hora_fin
  ELSE reloj.hora>=p.hora_inicio OR reloj.hora<p.hora_fin END)
ORDER BY p.nombre,p.id_promocion
$$;

CREATE OR REPLACE FUNCTION public.salon_grupos_promocion(p_id bigint)
RETURNS TABLE ("id_promocion_grupo" integer, "cantidad_elegir" smallint, "permite_repetir" boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_promocion_grupo,cantidad_elegir,permite_repetir
          FROM promocion_grupo WHERE id_promocion=p_id ORDER BY id_promocion_grupo
$$;

CREATE OR REPLACE FUNCTION public.salon_opciones_promocion(p_promo bigint, p_grupo bigint)
RETURNS TABLE ("id_presentacion_venta" integer, "reponible" boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT po.id_presentacion_venta,
              EXISTS(SELECT 1 FROM promocion_reposicion r WHERE r.id_promocion=p_promo
                AND r.id_presentacion_venta=po.id_presentacion_venta) AS reponible
              FROM promocion_opcion po WHERE po.id_promocion_grupo=p_grupo
              ORDER BY po.id_presentacion_venta
$$;

CREATE OR REPLACE FUNCTION public.salon_lineas(p_local bigint, p_mesa text)
RETURNS TABLE ("id_linea" bigint, "id_presentacion" integer, "id_promocion" integer, "selecciones_promocion" jsonb, "id_barra_libre" bigint, "barra_nombre" text, "nombre" text, "precio" numeric, "cantidad" integer, "comentario" character varying, "opciones" jsonb, "enviada" boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT l.id_linea,l.id_presentacion,l.id_promocion,l.selecciones_promocion,
        l.id_barra_libre,barra.nombre AS barra_nombre,l.nombre,l.precio,l.cantidad,l.comentario,l.opciones,
        p.estado='ENVIADO' AS enviada FROM salon_pedido_linea l JOIN salon_pedido_actual p USING(id_pedido)
        LEFT JOIN salon_pedido_linea barra ON barra.id_linea=l.id_barra_libre
        WHERE p.id_local=p_local AND p.mesa=p_mesa AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea) ORDER BY p.id_pedido,l.posicion
$$;

CREATE OR REPLACE FUNCTION public.salon_mesas_propias(p_local bigint, p_usuario bigint)
RETURNS TABLE ("mesa" character varying, "estado" text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT mesa,CASE WHEN bool_or(estado='BORRADOR') THEN 'BORRADOR' ELSE 'ENVIADO' END AS estado FROM salon_pedido_actual
      WHERE id_local=p_local AND id_usuario=p_usuario AND EXISTS(
        SELECT 1 FROM salon_pedido_linea l WHERE l.id_pedido=salon_pedido_actual.id_pedido)
      GROUP BY mesa ORDER BY mesa
$$;

CREATE OR REPLACE FUNCTION public.salon_promocion_padre(p_id bigint, p_local bigint, p_mesa text)
RETURNS TABLE ("id_promocion" integer, "selecciones_promocion" jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT l.id_promocion,l.selecciones_promocion FROM salon_pedido_linea l
              JOIN salon_pedido_actual actual USING(id_pedido)
              WHERE l.id_linea=p_id AND l.id_promocion IS NOT NULL AND actual.id_local=p_local
              AND actual.mesa=p_mesa AND actual.estado='ENVIADO'
              AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea)
$$;

CREATE OR REPLACE FUNCTION public.salon_envio_previo(p_local bigint, p_clave text)
RETURNS TABLE ("envio_hash" character varying, "mesa" character varying, "vigente" boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT p.envio_hash,coalesce(a.mesa,p.mesa) AS mesa,
                EXISTS(SELECT 1 FROM salon_pedido_actual actual WHERE actual.id_pedido=p.id_pedido) AS vigente
                FROM salon_pedido p LEFT JOIN salon_pedido_asignacion a USING(id_pedido)
                WHERE p.id_local=p_local AND p.envio_clave=CAST(p_clave AS uuid)
$$;

CREATE OR REPLACE FUNCTION public.salon_bloquear_catalogo()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
LOCK TABLE presentacion_venta,item_carta,categoria_carta,grupo_salsa,grupo_salsa_opcion,producto,promocion,promocion_grupo,promocion_opcion,promocion_reposicion IN SHARE MODE
$$;

CREATE OR REPLACE FUNCTION public.salon_eliminar_lineas(p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM salon_pedido_linea WHERE id_pedido=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_eliminar_pedido(p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
DELETE FROM salon_pedido WHERE id_pedido=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_crear_pedido(p_local bigint, p_mesa text, p_usuario bigint)
RETURNS bigint
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_pedido(id_local,mesa,id_usuario)
              VALUES(p_local,p_mesa,p_usuario) RETURNING id_pedido
$$;

CREATE OR REPLACE FUNCTION public.salon_crear_linea(p_pedido bigint, p_posicion bigint, p_id_presentacion bigint, p_id_promocion bigint, p_selecciones_promocion text, p_id_barra_libre bigint, p_nombre text, p_precio numeric, p_cantidad numeric, p_comentario text, p_opciones text)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_pedido_linea(id_pedido,posicion,id_presentacion,id_promocion,
                            selecciones_promocion,id_barra_libre,nombre,precio,cantidad,comentario,opciones)
                            VALUES(p_pedido,p_posicion,p_id_presentacion,p_id_promocion,CAST(p_selecciones_promocion AS jsonb),
                            p_id_barra_libre,p_nombre,p_precio,p_cantidad,p_comentario,CAST(p_opciones AS jsonb))
$$;

CREATE OR REPLACE FUNCTION public.salon_guardar_pedido(p_version bigint, p_estado text, p_enviar boolean, p_envio_clave text, p_envio_hash text, p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE salon_pedido SET version=p_version,estado=p_estado,
            enviado_en=CASE WHEN p_enviar THEN clock_timestamp() ELSE NULL END,
            envio_clave=CAST(p_envio_clave AS uuid),envio_hash=p_envio_hash WHERE id_pedido=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_cobros_instalados()
RETURNS regclass
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.salon_cobro')
$$;

CREATE OR REPLACE FUNCTION public.salon_lineas_cobro(p_local bigint, p_mesa text)
RETURNS TABLE ("id_linea" bigint, "id_pedido" bigint, "posicion" integer, "id_presentacion" integer, "nombre" text, "precio" numeric, "cantidad" integer, "comentario" character varying, "opciones" jsonb, "id_promocion" integer, "selecciones_promocion" jsonb, "id_barra_libre" bigint, "id_usuario" integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT l.*,p.id_usuario FROM salon_pedido_linea l
        JOIN salon_pedido_actual p USING(id_pedido)
        WHERE p.id_local=p_local AND p.mesa=p_mesa AND p.estado='ENVIADO'
        AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea)
        ORDER BY l.id_linea
$$;

CREATE OR REPLACE FUNCTION public.salon_pedidos_cobro(p_local bigint, p_mesa text)
RETURNS TABLE ("id_pedido" bigint, "version" integer, "estado" character varying, "id_usuario" integer)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_pedido,version,estado,id_usuario
        FROM salon_pedido_actual WHERE id_local=p_local AND mesa=p_mesa ORDER BY id_pedido
$$;

CREATE OR REPLACE FUNCTION public.salon_producto_consumo(p_id bigint)
RETURNS TABLE ("nombre" character varying, "unidad" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT nombre,unidad FROM producto WHERE id_producto=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_receta_activa(p_id bigint)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_receta FROM receta
            WHERE id_presentacion_venta=p_id AND activo
$$;

CREATE OR REPLACE FUNCTION public.salon_detalles_receta(p_id bigint)
RETURNS TABLE ("id_receta_detalle" integer, "id_receta" integer, "tipo_componente" character varying, "id_producto" integer, "id_subproducto" integer, "cantidad" numeric, "unidad" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT * FROM receta_detalle WHERE id_receta=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_nombre_presentacion(p_id bigint)
RETURNS character varying
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT ic.nombre FROM presentacion_venta pv
            JOIN item_carta ic USING(id_item_carta) WHERE pv.id_presentacion_venta=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_subproducto(p_id bigint)
RETURNS TABLE ("id_subproducto" integer, "codigo" character varying, "nombre" character varying, "rendimiento" numeric, "unidad" character varying, "instruccion" text, "activo" boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT * FROM subproducto WHERE id_subproducto=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_ingredientes_subproducto(p_id bigint)
RETURNS TABLE ("id_subproducto_detalle" integer, "id_subproducto" integer, "id_producto" integer, "cantidad" numeric, "unidad" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT * FROM subproducto_detalle WHERE id_subproducto=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_producto_salsa(p_id bigint, p_presentacion bigint)
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT o.id_producto FROM grupo_salsa_opcion o
                    JOIN grupo_salsa g USING(id_grupo_salsa)
                    WHERE o.id_grupo_salsa_opcion=p_id AND g.id_presentacion_venta=p_presentacion
$$;

CREATE OR REPLACE FUNCTION public.salon_diario(p_local bigint, p_inicio timestamp with time zone, p_fin timestamp with time zone, p_tipo text, p_metodo text, p_codigo text, p_offset bigint)
RETURNS TABLE ("cantidad" bigint, "total" numeric, "efectivo" numeric, "tarjeta" numeric, "ventas" jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.salon_comprobante(p_id bigint, p_local bigint)
RETURNS TABLE ("id_cobro" bigint, "id_local" integer, "id_usuario" integer, "mesa" character varying, "clave" uuid, "solicitud_hash" character varying, "tipo" character varying, "metodo" character varying, "documento" character varying, "cliente" character varying, "total" numeric, "comprobante" jsonb, "id_movimiento" integer, "creado_en" timestamp with time zone, "id_cliente" uuid)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_cobro, id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento, cliente, total, comprobante, id_movimiento, creado_en, id_cliente FROM salon_cobro WHERE id_cobro=p_id AND id_local=p_local
$$;

CREATE OR REPLACE FUNCTION public.salon_jornadas_instaladas()
RETURNS regclass
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT to_regclass('public.inventario_jornada')
$$;

CREATE OR REPLACE FUNCTION public.salon_comprobante_editable(p_id bigint)
RETURNS TABLE ("editable" boolean)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT j.cerrado_en IS NULL AND j.fecha=(clock_timestamp() AT TIME ZONE 'America/Lima')::date AND (c.creado_en AT TIME ZONE 'America/Lima')::date=j.fecha AS editable FROM salon_cobro c LEFT JOIN inventario_jornada j USING(id_jornada) WHERE c.id_cobro=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_cobro_previo(p_local bigint, p_clave text)
RETURNS TABLE ("id_cobro" bigint, "id_local" integer, "id_usuario" integer, "mesa" character varying, "clave" uuid, "solicitud_hash" character varying, "tipo" character varying, "metodo" character varying, "documento" character varying, "cliente" character varying, "total" numeric, "comprobante" jsonb, "id_movimiento" integer, "creado_en" timestamp with time zone, "id_cliente" uuid)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT id_cobro, id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento, cliente, total, comprobante, id_movimiento, creado_en, id_cliente FROM salon_cobro WHERE id_local=p_local AND clave=CAST(p_clave AS uuid)
$$;

CREATE OR REPLACE FUNCTION public.salon_bloquear_recetas()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
LOCK TABLE receta,receta_detalle,subproducto,subproducto_detalle,producto,grupo_salsa,grupo_salsa_opcion IN SHARE MODE
$$;

CREATE OR REPLACE FUNCTION public.salon_bloquear_codigo()
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT pg_advisory_xact_lock(hashtext('movimiento_inventario_codigo'))
$$;

CREATE OR REPLACE FUNCTION public.salon_siguiente_movimiento()
RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT coalesce(max(CASE WHEN codigo ~ '^MI-[0-9]+$'
            THEN substring(codigo FROM 4)::integer END),0)+1 FROM movimiento_inventario
$$;

CREATE OR REPLACE FUNCTION public.salon_crear_movimiento(p_codigo text, p_usuario bigint, p_local bigint, p_observacion text)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO movimiento_inventario
            (codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local,observacion)
            VALUES(p_codigo,'SALIDA','VENTA_SALON',(clock_timestamp() AT TIME ZONE 'America/Lima')::date,p_usuario,p_local,p_observacion)
            RETURNING id_movimiento_inventario
$$;

CREATE OR REPLACE FUNCTION public.salon_detalle_movimiento(p_movimiento bigint, p_producto bigint, p_cantidad numeric)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO movimiento_inventario_detalle
                (id_movimiento_inventario,id_producto,cantidad) VALUES(p_movimiento,p_producto,p_cantidad)
$$;

CREATE OR REPLACE FUNCTION public.salon_crear_cobro(p_local bigint, p_usuario bigint, p_mesa text, p_clave text, p_hash text, p_tipo text, p_metodo text, p_documento text, p_cliente text, p_total numeric, p_snapshot text, p_movimiento bigint)
RETURNS TABLE ("id_cobro" bigint, "id_local" integer, "id_usuario" integer, "mesa" character varying, "clave" uuid, "solicitud_hash" character varying, "tipo" character varying, "metodo" character varying, "documento" character varying, "cliente" character varying, "total" numeric, "comprobante" jsonb, "id_movimiento" integer, "creado_en" timestamp with time zone, "id_cliente" uuid)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_cobro
            (id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,documento,cliente,total,comprobante,id_movimiento)
            VALUES(p_local,p_usuario,p_mesa,CAST(p_clave AS uuid),p_hash,p_tipo,p_metodo,p_documento,p_cliente,p_total,CAST(p_snapshot AS jsonb),p_movimiento)
            RETURNING id_cobro, id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento, cliente, total, comprobante, id_movimiento, creado_en, id_cliente
$$;

CREATE OR REPLACE FUNCTION public.salon_cliente_cobro(p_cliente text, p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE salon_cobro SET id_cliente=CAST(p_cliente AS uuid) WHERE id_cobro=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_vincular_pedido(p_cobro bigint, p_pedido bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
INSERT INTO salon_cobro_pedido(id_cobro,id_pedido) VALUES(p_cobro,p_pedido)
$$;

CREATE OR REPLACE FUNCTION public.salon_cambio_bloqueado(p_id bigint, p_local bigint)
RETURNS TABLE ("id_cobro" bigint, "id_local" integer, "id_usuario" integer, "mesa" character varying, "clave" uuid, "solicitud_hash" character varying, "tipo" character varying, "metodo" character varying, "documento" character varying, "cliente" character varying, "total" numeric, "comprobante" jsonb, "id_movimiento" integer, "creado_en" timestamp with time zone, "id_jornada" bigint, "id_cliente" uuid, "jornada_fecha" date, "cerrado_en" timestamp with time zone, "hoy" date, "fecha_venta" date)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT c.*,j.fecha AS jornada_fecha,j.cerrado_en,
            (clock_timestamp() AT TIME ZONE 'America/Lima')::date AS hoy,
            (c.creado_en AT TIME ZONE 'America/Lima')::date AS fecha_venta
            FROM salon_cobro c LEFT JOIN inventario_jornada j USING(id_jornada)
            WHERE c.id_cobro=p_id AND c.id_local=p_local FOR UPDATE OF c
$$;

CREATE OR REPLACE FUNCTION public.salon_reloj()
RETURNS timestamp with time zone
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT clock_timestamp()
$$;

CREATE OR REPLACE FUNCTION public.salon_actualizar_cliente(p_tipo text, p_doc text, p_cliente text, p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE salon_cobro SET tipo=p_tipo,documento=p_doc,cliente=p_cliente,id_cliente=NULL WHERE id_cobro=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_guardar_comprobante(p_c text, p_id bigint)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
UPDATE salon_cobro SET comprobante=CAST(p_c AS jsonb) WHERE id_cobro=p_id
$$;

CREATE OR REPLACE FUNCTION public.salon_mesas_usadas_anteriores(p_local bigint)
RETURNS TABLE ("mesa" character varying)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp AS $$
SELECT DISTINCT mesa FROM salon_pedido WHERE id_local=p_local
$$;

COMMIT;
