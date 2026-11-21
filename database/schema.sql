--
-- PostgreSQL database dump
--

\restrict fP1JyiEDEpbiFEM9im8kuASerl46MOCdHOuw1IflMlWVMVfMi0QHnQxbM4dZJbi

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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
    CONSTRAINT grupo_salsa_opcion_cantidad_check CHECK ((cantidad > (0)::numeric)),
    CONSTRAINT grupo_salsa_opcion_unidad_check CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying])::text[])))
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
    CONSTRAINT ck_producto_stock_minimo CHECK ((stock_minimo >= (0)::numeric)),
    CONSTRAINT ck_producto_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying])::text[])))
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
    capacidad numeric(12,3),
    unidad_capacidad character varying(16),
    diametro_cm numeric(10,3),
    altura_cm numeric(10,3),
    largo_cm numeric(10,3),
    ancho_cm numeric(10,3),
    origen_medidas character varying(16),
    CONSTRAINT ck_menaje_medidas CHECK (((((capacidad IS NULL) AND (unidad_capacidad IS NULL)) OR ((capacidad IS NOT NULL) AND (capacidad > (0)::numeric) AND (capacidad <= (1000000)::numeric) AND (unidad_capacidad IS NOT NULL) AND ((unidad_capacidad)::text = ANY ((ARRAY['MLT'::character varying, 'LTR'::character varying, 'FLOZ_US'::character varying, 'FLOZ_UK'::character varying])::text[])))) AND ((diametro_cm IS NULL) OR ((diametro_cm > (0)::numeric) AND (diametro_cm <= (10000)::numeric))) AND ((altura_cm IS NULL) OR ((altura_cm > (0)::numeric) AND (altura_cm <= (10000)::numeric))))),
    CONSTRAINT ck_menaje_rectangular CHECK ((((largo_cm IS NULL) OR ((largo_cm > (0)::numeric) AND (largo_cm <= (10000)::numeric))) AND ((ancho_cm IS NULL) OR ((ancho_cm > (0)::numeric) AND (ancho_cm <= (10000)::numeric))) AND ((origen_medidas IS NULL) OR ((origen_medidas)::text = ANY ((ARRAY['DEMO'::character varying, 'REGISTRADO'::character varying])::text[])))))
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
    CONSTRAINT ck_movimiento_coherencia CHECK (((((tipo_movimiento)::text = 'ENTRADA'::text) AND ((motivo_movimiento)::text = 'PRESTAMO_RECIBIDO'::text) AND (local_relacionado IS NOT NULL) AND (id_proveedor IS NULL)) OR (((tipo_movimiento)::text = 'ENTRADA'::text) AND ((motivo_movimiento)::text = 'REPOSICION_PROVEEDOR'::text) AND (local_relacionado IS NULL) AND (id_proveedor IS NOT NULL)) OR (((tipo_movimiento)::text = 'SALIDA'::text) AND ((motivo_movimiento)::text = ANY ((ARRAY['MERMA'::character varying, 'VENTA_SALON'::character varying])::text[])) AND (local_relacionado IS NULL) AND (id_proveedor IS NULL)) OR (((tipo_movimiento)::text = 'SALIDA'::text) AND ((motivo_movimiento)::text = 'PRESTAMO_ENTREGADO'::text) AND (local_relacionado IS NOT NULL) AND (id_proveedor IS NULL)) OR (((tipo_movimiento)::text = 'SALIDA'::text) AND ((motivo_movimiento)::text = 'DEVOLUCION_PROVEEDOR'::text) AND (local_relacionado IS NULL) AND (id_proveedor IS NOT NULL)))),
    CONSTRAINT ck_movimiento_local CHECK (((local_relacionado IS NULL) OR (btrim((local_relacionado)::text) <> ''::text))),
    CONSTRAINT ck_movimiento_motivo CHECK (((motivo_movimiento)::text = ANY ((ARRAY['PRESTAMO_RECIBIDO'::character varying, 'MERMA'::character varying, 'PRESTAMO_ENTREGADO'::character varying, 'DEVOLUCION_PROVEEDOR'::character varying, 'REPOSICION_PROVEEDOR'::character varying, 'VENTA_SALON'::character varying])::text[]))),
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
    CONSTRAINT ck_presentacion_venta_precio CHECK ((precio >= (0)::numeric)),
    CONSTRAINT ck_presentacion_venta_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying, 'PORCION'::character varying])::text[])))
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
    CONSTRAINT ck_receta_detalle_tipo CHECK (((tipo_componente)::text = ANY ((ARRAY['PRODUCTO'::character varying, 'SUBPRODUCTO'::character varying])::text[]))),
    CONSTRAINT ck_receta_detalle_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying, 'PORCION'::character varying])::text[])))
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
    CONSTRAINT ck_subproducto_rendimiento CHECK ((rendimiento > (0)::numeric)),
    CONSTRAINT ck_subproducto_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'PORCION'::character varying])::text[])))
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
    CONSTRAINT ck_subproducto_detalle_cantidad CHECK ((cantidad > (0)::numeric)),
    CONSTRAINT ck_subproducto_detalle_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying])::text[])))
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
    CONSTRAINT unidad_medida_dimension_check CHECK (((dimension)::text = ANY ((ARRAY['MASA'::character varying, 'VOLUMEN'::character varying, 'CONTEO'::character varying])::text[]))),
    CONSTRAINT unidad_medida_factor_a_base_check CHECK ((factor_a_base > (0)::numeric))
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
-- Name: perfiles perfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_pkey PRIMARY KEY (id_perfil);


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
-- Name: unidad_medida unidad_medida_codigo_unece_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_codigo_unece_key UNIQUE (codigo_unece);


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
-- Name: movimiento_inventario movimiento_inventario_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


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
-- Name: unidad_medida unidad_medida_codigo_base_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_codigo_base_fkey FOREIGN KEY (codigo_base) REFERENCES public.unidad_medida(codigo);


--
-- Name: usuario_pin_salon usuario_pin_salon_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_pin_salon
    ADD CONSTRAINT usuario_pin_salon_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- PostgreSQL database dump complete
--

\unrestrict fP1JyiEDEpbiFEM9im8kuASerl46MOCdHOuw1IflMlWVMVfMi0QHnQxbM4dZJbi
