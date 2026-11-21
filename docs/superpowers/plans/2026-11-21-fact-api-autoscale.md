# Workers automáticos y publicación

Objetivo autorizado: aumentar/reducir workers automáticamente, actualizar código
y respaldo completo cifrado en GitHub.

Decisiones: supervisor único por bloqueo PostgreSQL de sesión; mínimo 1/máximo 4,
cola elegible y antigüedad, crecimiento con espera mínima y reducción tras 60 s
sin carga. No crecer con circuito abierto o fallos transitorios recientes.
Retiro mediante archivo de parada revisado entre trabajos; sin matar una emisión.
Estado de escalado en PostgreSQL. Arranque automático como opción predeterminada.

- [x] Pruebas de política, retiro y bloqueo de supervisor.
- [x] Supervisor, telemetría de escalado, migración y arranque.
- [x] Pruebas de procesos y PostgreSQL, regresiones y revisión.
- [x] Respaldos cifrados de barbarito/fact_api_demo y archivos, esquemas y verificación.
- [ ] Revisar secretos/archivos staged, commit, push normal y comprobar remoto.

Conservar cambios previos solicitados al publicar el estado del programa. No
subir .env, claves, certificados, dumps planos, logs ni vendor. La clave Fernet
existente se mantiene solo en .local. No sobrescribir cambios del remoto.

Verificación: 755 backend (608 correctas, 147 omitidas por entorno), 14 pruebas
PostgreSQL aisladas, ocho pruebas de política incluidas en la suite, 151 frontend,
lint y build correctos. Supervisor vivo con mínimo 1/máximo 4, una reserva global.
Restauración real de los respaldos: 81 tablas Barbarito y 25 fact_api_demo; 39
archivos privados cifrados. Revisión independiente corrigió propiedad tras caídas
y publicación atómica de generaciones de respaldo.
