# Preparación por lote o por vaso

**Objetivo aprobado:** preguntar cómo se prepara la bebida antes de preparar cambios, conservar las elecciones comerciales y distinguir el rendimiento del intermedio del consumo de cada vaso.

**Diseño:** estado de preparación conservado en la continuación firmada; pregunta inicial para crear recetas de bebidas con volumen conocido; instrucciones para consultas de referencias y controles antes de aceptar propuestas del modelo. Sin cambios comerciales automáticos ni migraciones.

- [x] Pruebas RED→GREEN de elección explícita, conservación de 400mL frente a lotes de 12L y bloqueo de cambios silenciosos a porción.
- [x] Integrar estado en coordinador/runtime y permitir consultar recetas/subproductos desde Presentaciones solo como referencias.
- [x] Ajustar instrucciones: lote→intermedio y consumo por vaso; por vaso→ingredientes de una unidad; no copiar recetas por similitud.
- [x] Pruebas de continuidad y consultas informativas, revisión independiente, suite y conversación real sin escrituras comerciales.
- [x] Activar backend local y verificar el caso guardado.

**Límites:** «como la chicha» no es una elección inequívoca del método ni permite cambiar unidades. Crear presentación y receta sigue requiriendo sus confirmaciones. Para Administrador no se consulta abastecimiento.

## Verificación

- Revisión independiente: corregidos los tres casos hallados con regresiones RED→GREEN: volumen de lote antes del vaso, correcciones naturales de medida y consultas informativas durante método pendiente.
- Prueba real: explica Chicha como intermedio de12L y receta final como0.4L por venta, sin copiarla a Maracuyá ni generar propuesta. Ambas elecciones de método se conservan.
- Backend activo en127.0.0.1:5001: HTTP200 tanto al iniciar como al retomar la conversación guardada; pregunta lote/vaso y conserva400mL, sin borrador nuevo.
- Suite final:495 pruebas,131 omitidas, sin fallas (364 correctas).
