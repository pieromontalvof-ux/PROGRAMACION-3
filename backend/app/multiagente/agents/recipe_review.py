"""Recipe evidence retained when the read phase or generation cannot continue."""
from app.multiagente.agents.tables import table, quantity


def available_answer(consulted):
    lines=[]
    for query in consulted:
        if query.get('recurso')!='recetas':
            continue
        for row in query.get('registros',[])[:5]:
            lines.append('### '+str(row.get('item_carta') or row.get('nombre') or 'Receta registrada'))
            ingredients=row.get('componentes') or []
            if ingredients:
                lines.append(table(['Ingrediente registrado','Cantidad'],[
                    [item.get('nombre_componente') or item.get('nombre') or 'Sin nombre',quantity(item.get('cantidad'),item.get('unidad'))]
                    for item in ingredients]))
            if row.get('instrucciones'):
                lines.append('Preparaci\u00f3n registrada: '+str(row['instrucciones']))
    if not lines:
        lines.append('No pude recuperar una receta identificada para mostrar sus ingredientes.')
    lines.append('No pude completar la comparaci\u00f3n de alternativas. \u00bfQu\u00e9 ingrediente quieres cambiar? Revisaremos su cantidad, la preparaci\u00f3n y la presentaci\u00f3n antes de sustituirlo. No se guardaron cambios.')
    return '\n\n'.join(lines)
