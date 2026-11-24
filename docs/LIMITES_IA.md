# Administración del consumo de IA

Ruta: **Asistente IA → Límites y consumo**, exclusivamente con perfil activo
Administrador del sistema. El backend vuelve a validar la sesión y ese perfil.

## Operación

**Estado general → Apagar asistente / Activar asistente** cambia inmediatamente
el permiso general, separado de «Aplicar los límites». Apagar bloquea nuevas
consultas, dictado y confirmaciones del chat para todos los usuarios y locales,
incluido el administrador. La administración de cuotas permanece disponible para
reactivar el servicio. Las llamadas ya autorizadas pueden terminar. El cambio
queda auditado y persiste tras reiniciar el servidor.

1. Consulta el consumo diario y mensual por usuario. El registro comienza al
   instalar esta función; no importa automáticamente consumos anteriores.
2. Define cuotas predeterminadas por usuario y, opcionalmente, topes generales.
3. Edita excepciones por usuario. Puedes volver a la cuota predeterminada.
4. Activa «Aplicar los límites» y guarda. Inicialmente está desactivado y todos
   los campos están sin límite. Un campo vacío significa ilimitado; cero bloquea.

El usuario comparte saldo entre todos sus perfiles y locales. El día y el mes
se calculan en hora de Lima. No hay que borrar registros para reiniciar el saldo:
las consultas del nuevo período cuentan únicamente sus propias llamadas.

En Consumo por usuario se combinan búsqueda por nombre/correo, local y rol.
Estos filtros seleccionan usuarios por sus asignaciones activas; el administrador
global tiene acceso a todos los locales activos. Las cifras conservan el consumo
total de cada persona entre sus roles/locales, sin duplicar o dividir su cuota.
Los totales de la pantalla suman las personas visibles tras aplicar los filtros.

Como punto inicial de ensayo se puede usar **200 000 tokens diarios y 2 millones
mensuales por usuario**, revisándolo después de una semana de uso real. No es un
precio ni una equivalencia fija de consultas: una consulta puede ejecutar varias
llamadas de varios agentes, con tamaños muy distintos. Conviene añadir un tope
general según el número de usuarios activos y el presupuesto disponible.

## Reserva y consumo

Antes de cada llamada Responses se registra una reserva conservadora: bytes del
cuerpo textual UTF-8 más máximo de salida. Un bloqueo transaccional de PostgreSQL
serializa las reservas y los cambios de configuración entre procesos e instancias.
No mantiene ese bloqueo durante la espera de la red.

Después se reemplaza la reserva por `usage.input_tokens + usage.output_tokens`.
Se incluye la entrada en caché y la salida de razonamiento según el total reportado
por el proveedor. Las llamadas sucesivas de agentes y reintentos de respuestas
incompletas tienen sus propios registros. Los hilos de búsquedas conservan el
usuario responsable, incluso sin compartir una petición Flask.

Una respuesta HTTP de rechazo 4xx libera la reserva. Un timeout, respuesta
ilegible, caída del proceso o resultado desconocido la conserva: no se reenvía
automáticamente una llamada que podría haber sido cobrada. Estas reservas aparecen
como pendientes y no se descartan automáticamente. El consumo real informado
siempre prevalece; la reserva es una previsión, no un conteo oficial previo.

## Alcance

- Esta cuota controla llamadas textuales al modelo; no controla cobros en dólares.
- El dictado/transcripción no está incluido.
- Con límites activos no se admiten adjuntos multimedia sin contador adecuado.
- Si existe un tope aplicable se bloquean herramientas alojadas por el proveedor,
  como búsqueda web: sus resultados agregan entradas que no pueden acotarse con
  los bytes enviados. Con cuotas desactivadas se contabiliza su uso real cuando
  el proveedor lo informa. No se promete un límite duro para esas herramientas.
- Una llamada ya autorizada puede terminar después de reducir una cuota. Los
  nuevos límites se aplican a las próximas reservas.
- No se almacenan prompts, respuestas ni claves en las tablas de consumo.

## Archivos y tablas

- `backend/app/multiagente/api/quotas.py`: períodos, validación, reserva, cierre,
  consultas y auditoría de cambios.
- `backend/app/multiagente/api/provider.py`: punto central antes/después del HTTP.
- `backend/app/multiagente/api/routes.py`: endpoints administrativos autenticados.
- `frontend/src/features/asistenteIA/TokenLimitsPage.tsx`: pantalla administrativa.
- `database/migrations/20261124_ai_quotas.sql`: migración repetible y aditiva.
- `backend/scripts/migrate_ai_quotas.py`: instalación local con conexión
  administrativa, sin imprimir contraseñas ni modificar datos del negocio.

Tablas: `ia_cuota_config`, `ia_cuota_usuario`, `ia_consumo`, `ia_cuota_auditoria`.
La migración está incluida en el contenedor y su lista de migraciones de arranque.

```sql
SELECT id_usuario, dia, sum(total) AS tokens_contabilizados
FROM ia_consumo
GROUP BY id_usuario, dia ORDER BY dia DESC, id_usuario;

SELECT id, id_usuario, modelo, reservado, entrada, salida, total, estado, creado_en
FROM ia_consumo ORDER BY creado_en DESC LIMIT 50;

SELECT administrador, id_usuario, anterior, nuevo, creado_en
FROM ia_cuota_auditoria ORDER BY creado_en DESC;
```
