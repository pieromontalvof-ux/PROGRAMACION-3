<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        DB::unprepared(<<<'SQL'
            CREATE VIEW barbarito_bloqueos AS
                SELECT NULL::text AS clave WHERE false;

            CREATE FUNCTION barbarito_adquirir_bloqueo() RETURNS trigger
                LANGUAGE plpgsql SECURITY INVOKER
                SET search_path TO pg_catalog, pg_temp AS $$
            BEGIN
                PERFORM pg_advisory_xact_lock(hashtext(NEW.clave));
                RETURN NEW;
            END;
            $$;

            CREATE TRIGGER tr_barbarito_adquirir_bloqueo
                INSTEAD OF INSERT ON barbarito_bloqueos
                FOR EACH ROW EXECUTE FUNCTION barbarito_adquirir_bloqueo();

            CREATE VIEW barbarito_correlativos_documentos AS
                SELECT company_id, serie, 'invoice'::text AS tipo, correlativo::bigint AS correlativo
                  FROM invoices
                UNION ALL
                SELECT company_id, serie, 'boleta'::text AS tipo, correlativo::bigint AS correlativo
                  FROM boletas;
            SQL);
    }

    public function down(): void
    {
        DB::unprepared(<<<'SQL'
            DROP VIEW barbarito_correlativos_documentos;
            DROP VIEW barbarito_bloqueos;
            DROP FUNCTION barbarito_adquirir_bloqueo();
            SQL);
    }
};
