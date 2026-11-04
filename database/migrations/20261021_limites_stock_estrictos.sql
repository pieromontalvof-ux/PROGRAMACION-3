-- Correctiva: preservar los limites historicos iguales y exigir maximo > minimo
-- en INSERT/UPDATE futuros. Requiere 20260922_limites_stock.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- DROP y ADD son atomicos: nunca se publica una tabla sin la proteccion.
-- NOT VALID evita rechazar o modificar filas historicas con ambos limites iguales.
ALTER TABLE public.producto_stock_local
    DROP CONSTRAINT IF EXISTS ck_stock_local_maximo,
    ADD CONSTRAINT ck_stock_local_maximo
        CHECK (stock_maximo IS NULL OR stock_maximo > stock_minimo) NOT VALID;

-- La restriccion ya protege escrituras nuevas aunque quede sin validar.
-- Validar solamente cuando todos los datos existentes cumplen la regla estricta.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.producto_stock_local
        WHERE stock_maximo IS NOT NULL AND stock_maximo <= stock_minimo
    ) THEN
        ALTER TABLE public.producto_stock_local VALIDATE CONSTRAINT ck_stock_local_maximo;
    END IF;
END $$;
COMMIT;
