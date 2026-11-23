# Railway fact_api Implementation Plan

**Goal:** Generar los PDF de ventas online sin bloquear cobros ni perder archivos.

**Architecture:** Reutilizar el servicio MULTIAGENTE, PostgreSQL y volumen /data.
Nginx/PHP-FPM sirven solo el puente Laravel en localhost; Flask conserva el puerto
público. Laravel utiliza el esquema fact_api, sin mezclar tablas con public.
Un proceso padre inicia y vigila servidor, PHP y supervisor de trabajadores.

**Constraints:** DEMO obligatorio; ninguna emisión SUNAT. No copiar base local ni
reemplazar ventas online. Credenciales por entorno/volumen privado. Un contenedor,
una réplica; trabajadores mínimo 1/máximo inicial 2. Publicación autorizada por usuario.

- [ ] Verificar acceso Railway y estado de tablas/configuración sin imprimir secretos.
- [ ] Probar preparación de entorno, preservación de secretos, aislamiento y fallos de arranque.
- [ ] Añadir arranque Linux, configuración interna PHP-FPM/Nginx y migración idempotente.
- [ ] Incluir dependencias, scripts y migraciones necesarias en Docker.
- [ ] Ejecutar pruebas, revisar cambios y publicar ambos repositorios.
- [ ] Habilitar integración en Railway, comprobar despliegue y generar documento de venta existente.
- [ ] Verificar PDF privado, estados, trabajadores y persistencia; documentar resultado real.
