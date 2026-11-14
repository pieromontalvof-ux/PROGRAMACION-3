# Conversación entre agentes Implementation Plan

**Goal:** Ofrecer alternativas reales antes de resolver dependencias, preguntar una decisión a la vez y conservar las correcciones entre especialistas.

**Architecture:** Mantener el coordinador firmado y las confirmaciones existentes. Mejorar la revisión previa de presentaciones, las instrucciones comunes y el contexto de ida y vuelta de cada requisito.

**Tech Stack:** Python, Flask, unittest; sin dependencias nuevas.

**Spec:** Alcance aprobado en esta conversación: consulta de Limonada especial, recomendación de 400 mL frente a 500 mL, precio elegido por la persona, continuidad con categoría y menaje.

## Restricciones

- Trabajar en la copia local solicitada, conservando cambios existentes; no publicar ni crear registros comerciales durante las pruebas.
- Una referencia de presentación no demuestra capacidad física del menaje.
- No calcular ni cambiar precio o contenido sin decisión del usuario.
- Mantener Realizar como confirmación de cada escritura.

## Tareas

1. [x] Añadir pruebas y corregir lectura de comillas y recomendación de medida; preguntar la decisión inmediata antes del tipo y prefijo.
2. [x] Añadir pruebas y conservar aclaraciones al delegar y retomar; validar continuación antes de reemplazar tareas antiguas de formulario.
3. [x] Ajustar las instrucciones comunes y especialistas; comprobar comportamiento con conversaciones reales sin escrituras.
4. [x] Ejecutar pruebas de conversación, coordinación y catálogo, revisión independiente y reiniciar el backend local para activar los cambios.

## Revisión

Comillas simples y curvas, falta de referencias de volumen, correcciones durante un requisito, continuaciones de otro perfil/local y solicitudes completas durante una tarea activa.

## Decisiones

- Implementación en la copia local porque contiene trabajo previo necesario y el usuario pidió activarlo localmente.
- El precio se conserva hasta una corrección expresa; ajustar tamaño no implica ajustar precio automáticamente.

## Verificación final

- unittest discover -s tests desde backend: 444 pruebas, 131 omitidas, ninguna falla (313 correctas).
- Revisión independiente: corregido el truncamiento de nombres con apóstrofos; pruebas RED→GREEN para delimitadores emparejados. Sin otros hallazgos concretos.
- Conversación real con escrituras comerciales bloqueadas: conserva 400 mL, S/12, Vaso y tipo preparada; después propone la categoría BT para revisión.
- Backend reiniciado en 127.0.0.1:5001. Comprobación HTTP: consulta inicial y respuesta «Prefiero 400 mL y revisar el precio» devuelven 200; pregunta el nuevo precio sin preparar un borrador.
