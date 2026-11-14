# Recuperación de conexión local

**Objetivo aprobado:** corregir la repetición de «No se pudo conectar con OpenAI» mostrada en el entorno local.

## Evidencia

El proceso local del puerto 5001 falló antes de la primera herramienta de Recetas. El mismo proceso respondió HTTP200 «Conectado» después, sin reiniciar. Las comprobaciones de red fuera del sandbox no tenían proxy y OpenAI respondió200. El registro original no conservaba la causa técnica concreta del URLError.

## Trabajo

- [x] Probar recuperación tras un corte, máximo de intentos, exclusión de errores HTTP/certificados/DNS permanente, presupuesto de reintentos y logs sin secretos (RED→GREEN).
- [x] Añadir hasta tres intentos de apertura con espera breve y presupuesto restante; mantener validación TLS y configuración de red existentes.
- [x] Revisión independiente sin hallazgos bloqueantes. El presupuesto limita nuevos intentos, no constituye un plazo absoluto para toda la lectura JSON de urllib.
- [x] Probar la consulta exacta: la conexión funcionó, pero apareció un recorrido innecesario del catálogo.
- [x] Aclarar al agente que una búsqueda filtrada cubre todos los registros; no debe recorrer páginas sin filtro tras cero coincidencias.
- [x] Evitar declarar ausente un insumo porque se buscó el nombre comercial completo de la bebida: ofrecer la coincidencia literal como referencia por confirmar (RED→GREEN).
- [x] Suite completa: 472 pruebas, 131 omitidas, sin fallas (341 correctas).
- [x] Comprobación final de la consulta exacta con el backend reiniciado: HTTP200, reconoce Maracuya activo y pregunta si será ingrediente; conserva la presentación de 400 mL a S/14. No confirmó cambios comerciales ni agotó el límite de consultas.
