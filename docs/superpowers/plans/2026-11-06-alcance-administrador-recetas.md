# Alcance del Administrador al definir recetas

**Criterio aprobado:** el Administrador define el catálogo global, presentaciones y recetas. Cada tienda se encarga de stock y compras. Esto reemplaza la revisión automática de abastecimiento para el Administrador definida anteriormente.

- [x] Probar y aplicar revisión de catálogo sin consultas de stock/proveedor para Administrador (RED→GREEN).
- [x] Mantener la revisión operativa de abastecimiento para los perfiles de tienda.
- [x] Retirar stock de las herramientas del especialista en el flujo global y evitar repetir advertencias antiguas del historial.
- [x] Verificar que el registro de un producto nuevo siga pudiendo resolver su proveedor obligatorio desde su catálogo.
- [x] Probar con la conversación guardada real sin persistir propuestas ni confirmar escrituras: continúa con PREPARADO, Sin alcohol, Vaso, 400mL, S/14 y pregunta estado activo.
- [x] Suite final: 475 pruebas, 131 omitidas, sin fallas (344 correctas).
- [x] Revisión independiente: corregida la pregunta de abastecimiento de la revisión previa para insumos inactivos/ambiguos en alcance CATALOGO, con regresión RED→GREEN.
- [x] Backend reiniciado y verificado por HTTP200: Administrador recibe solo registro activo de Maracuya, categoría y menaje; no consulta ni presenta advertencias de stock/proveedor. Continuación conservada.
