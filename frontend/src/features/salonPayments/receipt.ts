export interface ReceiptLine {
  nombre: string; cantidad: number; precio: number; enviada: boolean
  comentario: string; opciones: {nombre: string}[]; barra_nombre?: string | null; cantidad_reposiciones?: number
  id_barra_libre?: number | null; ids_lineas?: number[]
  selecciones_promocion?: {nombre: string; opciones: {nombre: string}[]}[]
}
export interface Receipt {
  prueba?: string
  editable?: boolean; anulacion?: {motivo:string;referencia:string}; historial?: {accion:string;fecha:string;motivo:string}[]
  id: number; numero: string; fecha: string; tipo: string; metodo: string
  documento: string; cliente: string; local: string; mesa: string
  usuario: string; total: number; fiscal: boolean; lineas: ReceiptLine[]
}
export const money = (value: number) => new Intl.NumberFormat('es-PE', {style:'currency', currency:'PEN'}).format(value)
export const documentNames: Record<string,string> = {BOLETA:'Boleta', BOLETA_ELECTRONICA:'Boleta electrónica', FACTURA:'Factura'}

export function resumenReposiciones(barra: ReceiptLine, lineas: ReceiptLine[]) {
  const identidad=barra.ids_lineas?.[0]
  if(!identidad)return ''
  const cantidades=new Map<string,number>()
  for(const linea of lineas.filter(linea => linea.id_barra_libre===identidad)) {
    const salsa=linea.opciones[0]?.nombre.replace(/^Salsa\s+/i,'') ?? 'Sin salsa'
    cantidades.set(salsa,(cantidades.get(salsa) ?? 0)+linea.cantidad)
  }
  return [...cantidades].map(([salsa,cantidad]) => `${cantidad} ${salsa}`).join(' · ')
}
