# Revisión de pedido ya solicitada

**Objetivo aprobado:** una solicitud que incluye eventos, ventas, stock y reposición debe continuar esos análisis sin volver a pedir autorización. Después se pregunta el incremento antes de preparar la orden.

**Diseño:** conservar el flujo guiado opcional para solicitudes simples. Para la revisión explícita, componer lecturas acotadas de Eventos, Demanda y la base nativa de Compras; devolver resumen compacto y estado firmado esperando porcentaje. No preparar ni enviar órdenes durante la revisión.

- [x] Pruebas RED→GREEN del flujo completo, eventos fallidos/no cercanos, permisos y continuación con porcentaje.
- [x] Resumen compacto de eventos con fuentes en detalle y análisis de los datos internos solicitados.
- [x] Base de reposición sin asumir margen: mostrar cantidades nativas y sus límites; distinguir análisis histórico y fórmula de compra.
- [x] Mantener revisión única, margen elegido y estado usuario/perfil/local. No repetir web automáticamente.
- [x] Pruebas completas, revisión independiente, prueba con Gerente y activación local.

**Límites:** eventos no verificados no justifican incrementos; datos faltantes o permisos no significan stock suficiente. Un porcentaje ya dado se conserva y la preparación se confirma como paso siguiente. No se cambian fórmula, permisos ni stock.

## Verificación final

- Revisión independiente: corregido el caso de exclusiones individuales con regresiones RED→GREEN (stock sin ventas, ventas sin stock/reposición, análisis interno sin eventos).
- El resumen de Inventario conserva los estados nativos, incluido bajo mínimo en el límite y sin conteo; no asume cero por ausencia de datos.
- Suite final:515 pruebas,131 omitidas, sin fallas (384 correctas).
- Prueba con Gerente/Sheraton usando el informe de eventos guardado, sin nueva búsqueda pagada ni propuestas comerciales: análisis de ventas, stock actual y base nativa; pregunta porcentaje al finalizar.
- Backend reiniciado en127.0.0.1:5001; HTTP200 al retomar el flujo guardado con «Continúa con el análisis solicitado». Recursos demanda_rotacion, stock y pedido_sugerido; ningún borrador.
- En los datos locales de esta prueba no hay ventas cobradas/consumo en los últimos30 días; el informe comunica esa limitación y no inventa cantidades de compra.
