-- Ejecutar conectado a barbarito. Solo lecturas; no muestra tokens.
SELECT current_database(),current_user;
SELECT minimo,maximo,activos,objetivo,listos,ocupados,pausado,actualizado_en FROM fact_api_escalado;
SELECT table_name FROM information_schema.tables
 WHERE table_schema='public' AND table_name LIKE 'fact_api_%' ORDER BY 1;
SELECT * FROM fact_api_seguimiento ORDER BY creado_en DESC LIMIT 50;
SELECT id_local,origen,estado,count(*) FROM fact_api_operacion GROUP BY 1,2,3 ORDER BY 1,2,3;
SELECT o.id_operacion,o.id_local,o.origen,i.numero,i.inicio,i.fin,i.http_status,i.resultado,i.duracion_ms
 FROM fact_api_operacion o JOIN fact_api_intento i USING(id_operacion)
 ORDER BY i.inicio DESC LIMIT 100;
SELECT d.id_operacion,d.numero,d.total,a.formato,a.bytes,a.sha256,a.ruta
 FROM fact_api_documento d JOIN fact_api_archivo a USING(id_documento)
 ORDER BY d.creado_en DESC LIMIT 50;
SELECT id_local,id_factura_recepcion,formato,bytes,creado_en FROM fact_api_adjunto ORDER BY creado_en DESC;
SELECT estado,count(*),min(creado_en) AS mas_antigua FROM fact_api_operacion GROUP BY estado;
SELECT percentile_cont(.95) WITHIN GROUP(ORDER BY duracion_ms) AS p95_ms,
 count(*) FILTER(WHERE http_status>=400) AS errores,count(*) AS intentos
 FROM fact_api_intento WHERE inicio>now()-interval '24 hours';
-- En OTRA conexión a fact_api_demo:
-- SELECT id,origin,source_reference,number,state,native_type,native_id FROM barbarito_documents;
-- SELECT document_id,format,path,bytes,sha256 FROM barbarito_files;
