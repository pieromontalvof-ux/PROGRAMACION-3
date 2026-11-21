export type FormValues = { nombre?: string; prefijo?: string; categorias?: number[]; proveedor?: string; categoria?: string; unidad?: string; contenido?: string; item?: string; tipo?: string; menaje?: string; precio?: string; activo?: boolean }

export function valuesFromProposal(data: Record<string, unknown>): FormValues {
  const text = (value: unknown) => value == null ? '' : String(value)
  const rawUnit = text(data.unidad)
  const rawAmount = data.contenido ?? data.presentacion
  const scaled = ['MLT', 'GRM'].includes(rawUnit) && Number.isFinite(Number(rawAmount))
  const unit = scaled ? rawUnit === 'MLT' ? 'LTR' : 'KGM' : rawUnit
  const amount = scaled ? Number(rawAmount) / 1000 : rawAmount
  return { nombre: text(data.nombre_item ?? data.nombre), prefijo: text(data.prefijo),
    categorias: Array.isArray(data.ids_categorias) ? data.ids_categorias.filter((id): id is number => typeof id === 'number') : [],
    proveedor: text(data.id_proveedor), categoria: text(data.id_categoria_carta ?? data.id_categoria),
    unidad: unit, contenido: text(amount), item: text(data.id_item_carta),
    tipo: text(data.tipo_item), menaje: text(data.id_menaje), precio: text(data.precio), activo: typeof data.activo === 'boolean' ? data.activo : true }
}
