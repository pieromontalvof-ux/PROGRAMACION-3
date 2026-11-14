# Cuadro compacto y búsqueda dirigida por recintos

Autorización: reproducir Día/Evento publicado/Tipo/Lugar y mejorar cobertura de
eventos próximos, sin presentar pendientes ni descartes como eventos confirmados.

- [x] Render de cuatro columnas con fecha legible, enlace al evento, tipo y recinto
  con distancia aproximada. Se muestra todo incluido, sin corte arbitrario a seis.
- [x] Revisión de candidatos y motivos en detalle desplegable cerrado inicialmente.
  Mantener tabla y detalle si la última consulta del flujo es stock.
- [x] Identificar recintos próximos en Overpass, por radio/origen, cache24h; priorizar
  tipos distintos y nombres de sus agendas en las dos fases de búsqueda.
  Si el servicio no responde, usar ubicaciones previas comprobadas como pistas.
- [x] Validar que los recintos del mapa son solo pistas, no prueba de un evento;
  mantener geocodificación, fuentes, fechas y radio para clasificación final.
- [x] Prueba real: búsqueda devolvió cuadro de cuatro columnas con dos eventos
  del Parque de la Exposición dentro del radio y motivos aparte. Repetición idéntica
  sin nuevo gasto de búsqueda. Consulta no exhaustiva, sin prometer todos los eventos.
- [x] Activación y verificaciones finales.

Pruebas:22deeventos;537enbackend(131omitidas), sin fallos. Frontend:12pruebas
relevantes pasan. Revisión independiente detectó la pérdida del cuadro en rama stock;
corregida con regresión. Compilación TS/Vite final pasa; backend reiniciado.
Interfaz y backend HTTP200. Sin modificaciones a datos comerciales.
