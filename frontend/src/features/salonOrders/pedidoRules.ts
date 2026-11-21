import type { GrupoPromocion, Linea, Opcion, Producto, Promocion, SeleccionBorrador, SeleccionPromocion } from './pedidoTypes'

function crearSeleccion(grupo: GrupoPromocion, producto: Producto, clave: string): SeleccionBorrador {
  return {
    clave, id_grupo: grupo.id, id_presentacion: producto.id, nombre: producto.nombre,
    reponible: Boolean(producto.reponible), grupo: producto.grupo, opciones: [],
  }
}

export function seleccionesIniciales(promo: Promocion, crearClave: () => string) {
  return promo.grupos
    .filter(grupo => grupo.cantidad === 1 && grupo.opciones.length === 1)
    .map(grupo => crearSeleccion(grupo, grupo.opciones[0], crearClave()))
}

export function seleccionarProducto(items: SeleccionBorrador[], grupo: GrupoPromocion, producto: Producto, clave: string) {
  const actuales = items.filter(item => item.id_grupo === grupo.id)
  if (actuales.length >= grupo.cantidad || (!grupo.repetir && actuales.some(item => item.id_presentacion === producto.id))) {
    return items
  }
  return [...items, crearSeleccion(grupo, producto, clave)]
}

export function grupoCompleto(grupo: GrupoPromocion, items: SeleccionBorrador[]) {
  return items.filter(item => item.id_grupo === grupo.id).length === grupo.cantidad
}

export function ajustarSalsa(seleccion: SeleccionBorrador, opcion: Opcion, delta: number) {
  const opciones = seleccion.opciones
  const count = opciones.filter(item => item.id === opcion.id).length
  if (delta > 0) {
    if (!puedeAgregarSalsa(seleccion, opcion)) return seleccion
    return { ...seleccion, opciones: [...opciones, opcion] }
  }
  if (delta >= 0 || count === 0) return seleccion
  const indice = opciones.findIndex(item => item.id === opcion.id)
  return { ...seleccion, opciones: [...opciones.slice(0, indice), ...opciones.slice(indice + 1)] }
}

export function puedeAgregarSalsa(seleccion: SeleccionBorrador, opcion: Opcion) {
  const grupo = seleccion.grupo
  return Boolean(grupo && seleccion.opciones.length < grupo.maximo
    && (grupo.repetir || !seleccion.opciones.some(item => item.id === opcion.id)))
}

export function construirReposiciones(
  barra: Linea, seleccion: SeleccionPromocion, cantidades: Record<number, number>, pendientes: number,
): { lineas: Linea[] } | { error: string } {
  const identidad = barra.ids_lineas?.[0]
  if (!identidad) return { error: 'No se pudo identificar la barra libre. Actualiza el pedido.' }

  const lineas = seleccion.grupo?.opciones.flatMap(opcion => {
    const cantidad = cantidades[opcion.id] ?? 0
    return cantidad ? [{
      id_presentacion: seleccion.id_presentacion, nombre: seleccion.nombre, precio: 0,
      cantidad, comentario: '', opciones: [opcion], enviada: false,
      id_barra_libre: identidad, barra_nombre: barra.nombre,
    }] : []
  }) ?? []
  if (!lineas.length) return { error: 'Agrega al menos una porción con el botón +.' }
  if (pendientes + lineas.length > 100) return { error: 'Se alcanzó el límite de líneas pendientes.' }
  return { lineas }
}
