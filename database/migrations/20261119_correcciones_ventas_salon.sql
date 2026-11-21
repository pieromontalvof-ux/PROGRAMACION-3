-- Same-day sale corrections use the existing JSON receipt audit history.
BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT UPDATE(tipo,documento,cliente,id_cliente,comprobante) ON salon_cobro TO multi;
 END IF;
END $$;
COMMIT;
