# Cercanía geográfica comprobable

Autorizado: sustituir declaraciones del modelo por cálculo independiente desde
dirección de la sede. Radio inicial 1500 m en línea recta, configurable; sin rutas
peatonales ni tiempos inventados.

- [x] Regresiones de distancia, falso cercano del modelo, ambigüedad, calles con
  números, polígonos grandes y margen que atraviesa el radio.
- [x] Geocodificación Nominatim configurable, identificación de cliente, atribución,
  cache local y rate limit compartido entre procesos/hilos de al menos 1.05 segundos.
- [x] Validar Perú, nombre/calle/número, rechazo de calles/ciudades y ubicaciones
  contradictorias. Padre parque solo con caja acotada y margen conservador.
- [x] Clasificar con distancias calculadas en servidor; fuera de radio descartado,
  sin mapa pendiente; no aceptar coordenadas o etiquetas del modelo.
- [x] Invalidar cache previo, mostrar criterio geográfico y enlaces de mapa.
- [x] Activar backend y completar verificación final.

Prueba real: dirección registrada de Sheraton resuelta en OSM way435970161.
Parque de la Exposición resuelto en OSM way39413088 como área; centros separados
aproximadamente522m con margen cartográfico combinado, dentro de1500m. No se
presenta como distancia exacta al acceso del anfiteatro ni recorrido a pie.
Hotel de otra zona sin resolución inequívoca quedó pendiente, nunca cercano.
Revisión independiente corrigió extracción de28enAv28deJulio800 y control del
boundingbox en cualquier resultado poligonal, no solo fallback.

Verificación final:536 pruebas sin fallos,131omitidas;21pruebas de eventos.
Revisión independiente sin bloqueos tras fixes. Prueba real final: parque522m,
margen combinado366m, DENTRO; Estadio San Marcos sin resolución inequívoca,
PENDIENTE (no se inventa distancia). Backend e interfaz HTTP200 tras reinicio.
