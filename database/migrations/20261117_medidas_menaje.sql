-- One-to-one optional physical measurements; no invented capacities or owner changes.
CREATE TABLE IF NOT EXISTS public.menaje_medida (
    -- Parent existence and removal are enforced transactionally by tableware_admin.
    -- The restricted application role lacks REFERENCES on the legacy table.
    id_menaje integer PRIMARY KEY,
    capacidad numeric(12,3),
    unidad_capacidad varchar(16),
    diametro_cm numeric(10,3),
    altura_cm numeric(10,3),
    CONSTRAINT ck_menaje_medidas CHECK (
            ((capacidad IS NULL AND unidad_capacidad IS NULL) OR
             (capacidad IS NOT NULL AND capacidad>0 AND capacidad<=1000000 AND unidad_capacidad IS NOT NULL AND unidad_capacidad IN ('MLT','LTR','FLOZ_US','FLOZ_UK')))
            AND (diametro_cm IS NULL OR (diametro_cm>0 AND diametro_cm<=10000))
            AND (altura_cm IS NULL OR (altura_cm>0 AND altura_cm<=10000))
    )
);
