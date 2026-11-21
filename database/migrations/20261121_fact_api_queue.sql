BEGIN;
CREATE TABLE IF NOT EXISTS fact_api_config (
 id_local integer PRIMARY KEY REFERENCES local(id_local),
 activo boolean NOT NULL DEFAULT false,
 ambiente text NOT NULL DEFAULT 'DEMO' CHECK(ambiente='DEMO'),
 empresa jsonb NOT NULL,
 serie_factura varchar(4) NOT NULL,
 serie_boleta varchar(4) NOT NULL,
 tasa_igv numeric(5,2) NOT NULL CHECK(tasa_igv BETWEEN 0 AND 100),
 creado_en timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS fact_api_operacion (
 id_operacion uuid PRIMARY KEY,
 id_local integer NOT NULL REFERENCES local(id_local),
 origen text NOT NULL CHECK(origen IN ('VENTA','COMPRA')),
 id_origen bigint NOT NULL,
 version integer NOT NULL DEFAULT 1,
 payload jsonb NOT NULL,
 payload_hash char(64) NOT NULL,
 estado text NOT NULL DEFAULT 'PENDIENTE' CHECK(estado IN
 ('PENDIENTE','PROCESANDO','REINTENTO','COMPLETADO','RECHAZADO','BLOQUEADO','REVISION')),
 intentos integer NOT NULL DEFAULT 0,
 max_intentos integer NOT NULL DEFAULT 6,
 obsoleto boolean NOT NULL DEFAULT false,
 disponible_en timestamptz NOT NULL DEFAULT now(),
 lease_hasta timestamptz,
 lease_token uuid,
 ultimo_http integer,
 ultimo_error text,
 creado_en timestamptz NOT NULL DEFAULT now(),
 actualizado_en timestamptz NOT NULL DEFAULT now(),
 UNIQUE(origen,id_origen,version)
);
CREATE INDEX IF NOT EXISTS fact_api_cola ON fact_api_operacion(disponible_en)
 WHERE estado IN ('PENDIENTE','REINTENTO','PROCESANDO');
ALTER TABLE fact_api_operacion ADD COLUMN IF NOT EXISTS max_intentos integer NOT NULL DEFAULT 6;
ALTER TABLE fact_api_operacion ADD COLUMN IF NOT EXISTS obsoleto boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS fact_api_intento (
 id_intento bigserial PRIMARY KEY,
 id_operacion uuid NOT NULL REFERENCES fact_api_operacion,
 numero integer NOT NULL,
 inicio timestamptz NOT NULL DEFAULT now(),
 fin timestamptz,
 duracion_ms numeric,
 http_status integer,
 resultado text NOT NULL DEFAULT 'INICIADO',
 UNIQUE(id_operacion,numero)
);
CREATE TABLE IF NOT EXISTS fact_api_documento (
 id_documento uuid PRIMARY KEY,
 id_operacion uuid NOT NULL UNIQUE REFERENCES fact_api_operacion,
 id_local integer NOT NULL REFERENCES local(id_local),
 id_externo uuid NOT NULL UNIQUE,
 numero text NOT NULL,
 estado text NOT NULL CHECK(estado='DEMO_GENERADO'),
 subtotal numeric(14,2) NOT NULL,
 igv numeric(14,2) NOT NULL,
 total numeric(14,2) NOT NULL,
 creado_en timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS fact_api_archivo (
 id_archivo uuid PRIMARY KEY,
 id_documento uuid NOT NULL REFERENCES fact_api_documento,
 formato text NOT NULL CHECK(formato IN ('A4','80mm')),
 ruta text NOT NULL UNIQUE,
 sha256 char(64) NOT NULL,
 bytes integer NOT NULL CHECK(bytes>0),
 creado_en timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id_documento,formato)
);
CREATE TABLE IF NOT EXISTS fact_api_circuito (
 id integer PRIMARY KEY CHECK(id=1),
 fallos integer NOT NULL DEFAULT 0,
 abierto_hasta timestamptz
);
CREATE TABLE IF NOT EXISTS fact_api_adjunto (
 id_adjunto uuid PRIMARY KEY,
 id_local integer NOT NULL REFERENCES local(id_local),
 id_factura_recepcion integer NOT NULL REFERENCES factura_recepcion(id_factura_recepcion),
 formato text NOT NULL CHECK(formato IN ('PDF','XML')),
 ruta text NOT NULL UNIQUE,
 sha256 char(64) NOT NULL,
 bytes integer NOT NULL CHECK(bytes>0 AND bytes<=5242880),
 creado_en timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id_local,id_factura_recepcion,sha256)
);
INSERT INTO fact_api_circuito(id) VALUES(1) ON CONFLICT DO NOTHING;
CREATE OR REPLACE VIEW fact_api_seguimiento AS
 SELECT o.id_operacion,o.id_local,l.nombre AS local,o.origen,o.id_origen,o.version,o.estado,
 o.intentos,o.ultimo_http,o.ultimo_error,o.creado_en,o.actualizado_en,d.numero,
 d.estado AS estado_documento,d.total,d.id_documento
 FROM fact_api_operacion o JOIN local l USING(id_local)
 LEFT JOIN fact_api_documento d USING(id_operacion);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT,UPDATE ON fact_api_config,fact_api_operacion,fact_api_intento,
    fact_api_documento,fact_api_archivo,fact_api_circuito,fact_api_adjunto TO multi;
  GRANT SELECT ON fact_api_seguimiento TO multi;
  GRANT USAGE,SELECT ON SEQUENCE fact_api_intento_id_intento_seq TO multi;
 END IF;
END $$;
COMMIT;
