# Recuperación de arranque de fact_api — 24 noviembre 2026

El servicio cayó después de las migraciones de la aplicación, al preparar Laravel.
El archivo administrado de entorno se escribía con python-dotenv, cuyo escape de
comillas simples no es compatible con el lector dotenv de PHP. Un token pegado
con comillas externas provocó el error de lectura. Después de corregir ese
formato, Laravel eliminaba esas comillas externas y Python todavía las conservaba,
produciendo un 401 en la comprobación privada.

La corrección genera el archivo completo con comillas dobles y escapes compatibles
con PHP, sin interpolar dólares. Valida el contenido antes de truncar el archivo y
mantiene permisos privados. Únicamente para el token Bearer se eliminan envolturas
de comillas de configuración, de modo que ambos procesos usan el mismo valor.
No se normalizan ni alteran contraseñas de base de datos.

Durante el diagnóstico se utilizó temporalmente `FACT_API_BUNDLED=0` para recuperar
la web y Salón, dejando la generación de documentos en espera. El modo normal es
`FACT_API_BUNDLED=1`. No se borraron tablas, ventas, respaldos ni documentos y no
se reemplazó la clave persistente de Laravel.

Validación: prueba con el parser PHP real para comillas, barras, dólares literales,
Unicode y saltos de línea; prueba de normalización del token; prueba en el servidor
real de comandos Artisan y del puente privado autenticado. Los diagnósticos con
valores de configuración permanecen en el volumen privado y no se publican en Git.
