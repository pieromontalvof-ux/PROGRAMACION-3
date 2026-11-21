CREATE TABLE IF NOT EXISTS salon_cierre_diario (
    id_local integer NOT NULL CHECK (id_local > 0),
    fecha date NOT NULL,
    registrado_en timestamptz NOT NULL DEFAULT now(),
    simulacion boolean NOT NULL DEFAULT false,
    cantidad integer NOT NULL CHECK (cantidad >= 0),
    efectivo numeric(14,2) NOT NULL CHECK (efectivo >= 0),
    tarjeta numeric(14,2) NOT NULL CHECK (tarjeta >= 0),
    PRIMARY KEY (id_local, fecha)
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'multi') THEN
        GRANT SELECT ON salon_cierre_diario TO multi;
    END IF;
END $$;
