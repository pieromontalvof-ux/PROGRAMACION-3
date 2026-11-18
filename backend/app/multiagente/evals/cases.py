"""Hand-labelled synthetic cases. Never include customer conversations here."""

ROUTING_CASES = (
    ('inventory', 'Consulta el stock bajo mínimo', '', 'inventario'),
    ('catalog', 'Crear producto', '', 'carta_recetas'),
    ('recipe', 'Edita la receta de Alitas', '', 'recetas'),
    ('recipe-stock', 'Crear receta y revisar stock', '', 'recetas'),
    ('menu-article', 'crear un artículo de la carta', '', 'presentaciones'),
    ('joined-word', 'crearun producto de la carta', '', 'presentaciones'),
    ('tableware', 'Editar menaje Copa', '', 'menajes'),
    ('subproduct', 'Crea un subproducto de salsa', '', 'subproductos'),
    ('category', 'Crea una categoría de carta', '', 'categorias_carta'),
    ('promotion', 'Crear promo', '', 'promociones'),
    ('purchase', 'Hacer un pedido de compra', '', 'compras'),
    ('service-order', 'Consultar pedidos de mesa', '', 'salon'),
    ('reception', 'Llegó el pedido', '', 'recepcion'),
    ('events', 'Busca conciertos', '', 'eventos'),
    ('demand', 'Analiza las ventas', '', 'demanda'),
    ('cross-domain', 'Cambia la receta y revisa el stock', '', 'orquestador'),
    ('follow-up', 'Usa 0.5 kg', 'Crear recetas', 'recetas'),
    ('new-task', 'Crea un menaje', 'Crear recetas', 'menajes'),
)

CASES = tuple(
    {'id': identity, 'kind': 'route', 'instruction': instruction,
     'previous': previous, 'expected': expected}
    for identity, instruction, previous, expected in ROUTING_CASES
) + (
    {'id': 'read-granted', 'kind': 'permission', 'resource': 'productos',
     'session': {'menu': [{'id_opcion_menu': 4, 'permisos': {'consultar': True}}]}, 'expected': True},
    {'id': 'read-denied', 'kind': 'permission', 'resource': 'productos',
     'session': {'menu': [{'id_opcion_menu': 4, 'permisos': {'consultar': False}}]}, 'expected': False},
    {'id': 'other-menu-does-not-grant', 'kind': 'permission', 'resource': 'productos',
     'session': {'menu': [{'id_opcion_menu': 5, 'permisos': {'consultar': True}}]}, 'expected': False},
    {'id': 'empty-menu-denied', 'kind': 'authorize', 'resource': 'productos',
     'session': {'menu': []}, 'expected': 403},
    {'id': 'unknown-resource-denied', 'kind': 'authorize', 'resource': 'synthetic_unknown',
     'session': {'menu': []}, 'expected': 403},
    {'id': 'users-write-denied', 'kind': 'authorize', 'resource': 'usuarios', 'action': 'editar',
     'session': {'menu': [{'id_opcion_menu': 2, 'permisos': {'editar': True}}]}, 'expected': 403},
)
