BEGIN;
ALTER TABLE proveedor ADD COLUMN IF NOT EXISTS datos_comerciales jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE UNIQUE INDEX IF NOT EXISTS uq_proveedor_ruc ON proveedor ((datos_comerciales->>'ruc'))
 WHERE COALESCE(datos_comerciales->>'ruc','') <> '';
ALTER TABLE factura_recepcion ADD COLUMN IF NOT EXISTS datos_factura jsonb;
ALTER TABLE factura_recepcion ADD COLUMN IF NOT EXISTS entregas jsonb NOT NULL DEFAULT '[]'::jsonb;
COMMIT;
