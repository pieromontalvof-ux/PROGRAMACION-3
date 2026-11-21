# Arquitectura y diagnóstico

1. Separar los archivos de salón en modules/salon y actualizar todas las referencias, conservando endpoints y permisos. Verificar con pruebas existentes.
2. Agregar telemetría HTTP sin datos personales: identificador generado en servidor, ruta normalizada, estado y duración. Probar respuestas normales y errores.
3. Agregar contención de errores de React y carga de pantallas bajo demanda. Probar el fallback y compilar.
4. Extraer carga de productos a un hook cancelable, manteniendo el contrato de servicios. Probar respuestas tardías y desmontaje.
5. Ejecutar pruebas, lint y build. Documentar advertencias restantes y límites del diagnóstico de memoria.

Continuación solicitada:

6. Separar servicios, contexto, cálculos y formatos de los componentes; compartir carga de usuarios y proveedores con protección ante respuestas tardías.
7. Eliminar las advertencias existentes sin desactivar reglas. Cancelar el inicio de cargas desmontadas y conservar sus limpiezas.
8. Agregar métricas acotadas y panel exclusivo para administrador, probando rechazo de sesiones no autorizadas.
9. Medir memoria de Python y de Chrome en recorridos de lectura, documentando su alcance. Verificar frontend, backend e integración en PostgreSQL temporal.
