import type { UnidadMedida } from '../types/units'

export function formatearUnidad(valor: unknown, campo: 'unidad' | 'unidad_presentacion' = 'unidad'): string {
  if (typeof valor === 'string') return valor
  if (!valor || typeof valor !== 'object') return ''
  const fila = valor as Record<string, unknown> & {
    unidad_medida?: UnidadMedida
    unidad_presentacion_medida?: UnidadMedida
  }
  const simbolo = fila[`${campo}_medida`]?.simbolo
  return simbolo || (typeof fila[campo] === 'string' ? fila[campo] : '')
}

export function unidadesCompatibles(unidades: UnidadMedida[], valor: string): UnidadMedida[] {
  const base = unidades.find((u) => u.valor === valor)?.codigo_base
  return base ? unidades.filter((u) => u.codigo_base === base) : []
}

export function etiquetaUnidad(unidades: UnidadMedida[], valor: string): string {
  const unidad = unidades.find((u) => u.valor === valor)
  return unidad ? `${unidad.nombre} (${unidad.simbolo})` : formatearUnidad(valor)
}

export function convertirCantidadVisible(cantidad: string, origen: string, destino: string, unidades: UnidadMedida[]): string {
  const anterior = unidades.find((u) => u.valor === origen)
  const nueva = unidades.find((u) => u.valor === destino)
  if (!anterior || !nueva || anterior.codigo_base !== nueva.codigo_base || cantidad.trim() === '') return cantidad
  const valor = Number(cantidad) * Number(anterior.factor_a_base) / Number(nueva.factor_a_base)
  // Solo para editar el formulario; el backend valida y calcula con Decimal.
  return Number.isFinite(valor) ? String(Number(valor.toFixed(6))) : cantidad
}
