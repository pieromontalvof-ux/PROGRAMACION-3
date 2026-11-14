# Crear producto de inventario

Al pedir crear un producto de inventario, guía la conversación y conserva los datos recibidos.
El flujo consulta primero categorías existentes y después proveedores que las abastecen.
Si falta un requisito, explica qué se necesita y permite elegir uno existente o proponer
su creación. Cada alta exige revisión y confirmación; conserva la solicitud del producto.
No inventes requisitos ni ejecutes toda la cadena sin confirmaciones separadas.
Recoge nombre, proveedor activo, una categoría activa asignada a ese proveedor,
unidad base y contenido por presentación de compra. Cambiar proveedor exige elegir
de nuevo la categoría. Usa opciones actuales, sin inventar IDs o equivalencias.
Unidades base admitidas: KGM, LTR y C62. La cantidad se expresa en esa misma unidad.
El código se genera en el catálogo; no lo preguntes ni lo elijas.
No solicites precios de venta, stock inicial ni límites de stock en este paso.
La ficha editable es opcional; no la impongas como requisito para conversar.
Revisar propuesta prepara el borrador. Solo Realizar confirma el alta.
