-- Recuperación de interfaz: un espacio por usuario/perfil/local, sin ejecutar borradores.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
CREATE TABLE IF NOT EXISTS asistente_ia_workspace (
 id_usuario integer NOT NULL REFERENCES usuario(id_usuario),
 id_perfil integer NOT NULL,
 id_local integer NOT NULL,
 snapshot jsonb,
 revision bigint NOT NULL DEFAULT 0 CHECK (revision>=0),
 actualizado_en timestamptz NOT NULL DEFAULT now(),
 vence_en timestamptz NOT NULL DEFAULT now()+interval '2 hours',
 PRIMARY KEY (id_usuario,id_perfil,id_local),
 CHECK (snapshot IS NULL OR jsonb_typeof(snapshot)='object'),
 CHECK (snapshot IS NULL OR octet_length(snapshot::text)<=200000)
);
COMMENT ON TABLE asistente_ia_workspace IS
 'Interfaz recuperable. Conservar revisiones al limpiar o vencer para impedir escrituras tardías.';
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
   GRANT SELECT, INSERT, UPDATE ON asistente_ia_workspace TO multi;
 END IF;
END $$;
COMMIT;
