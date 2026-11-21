BEGIN;
CREATE TABLE IF NOT EXISTS fact_api_escalado (
 id integer PRIMARY KEY CHECK(id=1),
 supervisor uuid NOT NULL,
 pid integer NOT NULL,
 minimo integer NOT NULL CHECK(minimo>=1),
 maximo integer NOT NULL CHECK(maximo BETWEEN 1 AND 4 AND maximo>=minimo),
 activos integer NOT NULL CHECK(activos>=0),
 objetivo integer NOT NULL CHECK(objetivo>=0),
 listos integer NOT NULL,
 ocupados integer NOT NULL,
 espera_segundos numeric NOT NULL,
 pausado boolean NOT NULL,
 workers jsonb NOT NULL,
 actualizado_en timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS fact_api_intento_inicio ON fact_api_intento(inicio);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT,UPDATE ON fact_api_escalado TO multi;
 END IF;
END $$;
COMMIT;
