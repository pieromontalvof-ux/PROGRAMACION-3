# Eventos del bar: sede, período y tabla

Alcance autorizado: usar sede/dirección de sesión; preguntar fecha cuando falte;
buscar recintos próximos, congresos de hoteles y conciertos; conservar tabla breve
con fuentes y oportunidad potencial para el bar, sin edades ni demanda inventadas.
No modifica fórmulas de compra ni confirma órdenes.

- [x] Reproducir pérdida de fechas, ausencia de pregunta y descarte de tabla con pruebas.
- [x] Resolver períodos futuros separados de períodos históricos de ventas.
- [x] Continuar el pedido firmado después de recibir las fechas.
- [x] Ampliar búsqueda dirigida acotada y actualizar instrucciones del agente.
- [x] Conservar tabla, fuentes y período en revisión de compras.
- [x] Ejecutar regresiones, revisión de código y activar backend local.

Verificación: suite backend 520 pruebas, 131 omitidas, sin fallos; cinco pruebas
de regresión de períodos/conversación. Revisión independiente corrigió pérdida de
fechas posteriores a ventas y ampliación de una consulta de un solo día.
Dos consultas reales de solo lectura: respuesta con tabla y fuentes; búsqueda
dirigida ampliada devolvió conciertos próximos. La cobertura sigue siendo no
exhaustiva. Backend local reiniciado en 127.0.0.1:5001. Sin órdenes ni inventario modificados.
