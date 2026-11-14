# Revisión de insumos Implementation Plan

**Goal:** Revisar producto, stock del local y proveedor durante la conversación de presentaciones y recetas, conservando decisiones y confirmaciones.

**Architecture:** Una consulta de abastecimiento de solo lectura compone datos de las rutas nativas. Presentaciones, Recetas y Subproductos reciben conexiones de consulta, separadas de los recursos que pueden crear. La revisión previa de presentaciones incorpora coincidencias literales del catálogo como posibles insumos, sin inventar recetas.

**Tech Stack:** Flask/Python, unittest; sin migraciones ni dependencias nuevas.

**Spec:** Solicitud aprobada en chat: distinguir no registrado/sin stock/con existencias, informar proveedor real y ofrecer revisar abastecimiento antes de continuar, respetando permisos.

## Restricciones y decisiones

- Mantener los permisos operativos: Administrador no recibe acceso nuevo a stock por este cambio.
- Stock ausente, nulo, inaccesible o fallido no significa cero. Existencias positivas no garantizan suficiencia sin receta y cantidad a preparar.
- No deducir una receta del título: las coincidencias de nombres solo son posibles insumos por confirmar.
- Ofrecer revisar proveedor o abrir Compras; no prometer que se puede enviar un pedido ni que el proveedor tiene disponibilidad. Las compras manuales continúan en su formulario existente.
- Trabajar sobre el estado local autorizado y conservar los cambios previos.

## Tareas

1. [x] Escribir y ejecutar pruebas RED para estados de catálogo, stock, proveedor y permisos; implementar consulta de solo lectura.
2. [x] Conectar la consulta al runtime, revisión previa y manifiesto sin ampliar permisos de escritura. Probar que la continuación conserva la tarea.
3. [x] Ajustar instrucciones, probar conversaciones sin escrituras comerciales, revisión independiente y suite de backend.
4. [x] Reiniciar backend y comprobar por HTTP el caso real de Maracuyá.

## Revisión

Coincidencias parciales/ambiguas, producto inactivo, stock nulo/ausente, proveedor desactivado, permisos de agente o perfil, título que no define receta y no repetir compras implícitas.

## Resultados

- `unittest discover -s tests`: 465 pruebas, 131 omitidas, sin fallas (334 correctas).
- Revisión independiente: corregido desvío a Compras anterior al router. Prueba RED→GREEN del endpoint.
- Pruebas reales detectaron y corrigieron el contrato de actividad de la consulta del catálogo (retorno estructurado), y la confusión de «registrar receta» con leer una existente. Ambas tienen regresiones RED→GREEN.
- Conversaciones reales de presentaciones y recetas conservan Maracuyá especial, 400 mL, S/14 y proveedor asociado. No se persistieron borradores comerciales durante esas pruebas.
- Backend reiniciado en 127.0.0.1:5001. HTTP200 para la consulta real: producto27 Maracuya, proveedor Distribuidora Central Lima S.A.C., stock SIN_ACCESO/null con perfil Administrador y continuación conservada. Sin cambios confirmados.
