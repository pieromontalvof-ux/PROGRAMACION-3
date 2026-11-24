# Límites y consumo del asistente

Agregar una sección exclusiva del administrador, siguiendo la navegación existente.
Cuotas por usuario (sin reinicio al cambiar rol/local), por día y mes de Lima;
topes generales opcionales. Inicialmente desactivados, registro activo.

Secuencia: pruebas de validación y períodos; migración aditiva; contabilidad
centralizada antes de cada llamada Responses; endpoints autenticados; pantalla;
pruebas de permisos, concurrencia y compilación.

Cada llamada reserva entrada textual conservadora (bytes UTF-8 del cuerpo) más
salida máxima. Al responder, se sustituye por el uso real informado. Las llamadas
de resultado desconocido conservan la reserva, visible como consumo pendiente.
No se guardan instrucciones ni respuestas en este registro. No es un límite en
dólares ni incluye dictado. No se liberan reservas inciertas automáticamente.
Con cuotas activas no se admiten entradas multimedia sin conteo verificable.
