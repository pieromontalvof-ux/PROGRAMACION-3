# Búsqueda consistente de eventos del bar

Alcance autorizado: buscar candidatos, comprobarlos por separado, conservar motivos
de inclusión/descarte y reutilizar resultados recientes de la misma sede/período.
No modifica stock, compras ni porcentajes.

- [x] Pruebas: filtrar fechas/cancelaciones/acceso restringido; deduplicar y ordenar;
  conservar candidatos descartados con motivo; cache por sede, dirección y período;
  reintento explícito renueva y mantiene candidatos previos como datos a comprobar.
- [x] Separar descubrimiento y verificación con fuentes devueltas por búsqueda.
- [x] Renderizar tablas desde datos validados en servidor, sin completar cupos.
- [x] Cache atómico local de 30 minutos; nunca guardar fallos como agenda vacía.
- [x] Regresiones, revisión, búsqueda real y activación del backend local.

Revisión independiente: se corrigió pérdida de candidatos anteriores si ambas fases
de reintento devolvían listas vacías. Fallos y renovación tras caducidad mantienen
los candidatos no resueltos como pendientes. Regresión cubre ambos casos.

Validación real: dos ejecuciones completas de descubrimiento/verificación con datos
públicos de Sheraton, y repetición inmediata sin nuevas llamadas al proveedor,
con informe idéntico (CACHE_REPETICION_OK). No se modificó ningún dato comercial.
La cobertura sigue siendo no exhaustiva; las fuentes pueden cambiar.

Se evita mostrar prosa libre de limitaciones que contradiga el resultado clasificado;
el resumen y motivos los produce el servidor. Se mantienen observaciones originales
en detalle. Pruebas de eventos: 14. Suite completa final: 529 pruebas sin fallos,
131 omitidas. Backend e interfaz activos y respondiendo HTTP200.
