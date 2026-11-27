import type { MedidaConUnidad } from './units'

export interface ProductoPendienteRecepcion {
  id_producto: number
  codigo: string
  nombre: string
  categoria: string
  unidad: string
  presentacion: number
  cantidad_solicitada: number
  cantidad_recibida: number
  cantidad_pendiente: number
}

export interface PendienteRecepcion {
  datos_comerciales?: Record<string,string>
  id_orden_compra: number
  codigo_orden: string
  estado_orden_compra: string
  fecha_registro: string | null
  id_proveedor: number
  proveedor: string
  productos: ProductoPendienteRecepcion[]
}

export interface RespuestaPendientesRecepcion {
  resumen: {
    ordenes_pendientes: number
    recepciones_pendientes: number
    productos_pendientes: number
  }
  pendientes: PendienteRecepcion[]
}

export interface DatosRegistrarRecepcion {
  factura?: FacturaProveedorEntrada
  id_proveedor: number
  numero_factura: string
  fecha_recepcion: string
  detalles: Array<{
    id_producto: number
    cantidad_recibida: number
  }>
}

export interface RecepcionHistorial {
  total_factura?: number | null
  moneda?: string | null
  id_factura_recepcion: number
  id_orden_compra: number
  codigo_orden: string
  estado_orden_compra: string
  numero_factura: string
  fecha_recepcion: string
  id_proveedor: number
  proveedor: string
  recibido_por: string
  productos_recibidos: number
  cantidad_total: number
}

export interface DetalleRecepcionHistorial {
  id_factura_recepcion_detalle: number
  id_producto: number
  codigo: string
  nombre: string
  unidad: string
  cantidad_recibida: number
  cantidad_solicitada: number
  recibido_otras_facturas: number
  maximo_permitido: number
}

export interface RespuestaDetalleRecepcion {
  motivos_correccion: { codigo: string; etiqueta: string }[]
  recepcion: {
    factura?: FacturaProveedor | null
    entregas?: EntregaProveedor[]
    id_factura_recepcion: number
    id_orden_compra: number
    codigo_orden: string
    estado_orden_compra: string
    id_proveedor: number
    proveedor: string
    numero_factura: string
    fecha_recepcion: string
    recibido_por: string
    detalles: DetalleRecepcionHistorial[]
  }
}

export interface LineaFacturaProveedor extends MedidaConUnidad {
  costo_total?: number
  id_producto: number
  cantidad_facturada: number
  precio_unitario: number
  descuento: number
  afectacion_igv?: 'GRAVADO' | 'EXONERADO' | 'INAFECTO'
  igv_porcentaje: number
}
export interface FacturaProveedorEntrada {
  fecha_emision: string
  moneda: 'PEN' | 'USD'
  lineas: LineaFacturaProveedor[]
}
export interface FacturaProveedor extends FacturaProveedorEntrada {
  datos_ficticios?: boolean
  proveedor: Record<string, string>
  base_gravada?: number
  base_exonerada?: number
  base_inafecta?: number
  subtotal: number
  igv: number
  total: number
  lineas: Array<LineaFacturaProveedor & { nombre: string; codigo: string; unidad: string; subtotal: number; igv: number; total: number }>
}
export interface EntregaProveedor {
  fecha: string
  usuario: number
  detalles: Array<{ id_producto: number; cantidad_recibida: number }>
}

export interface DatosCorregirRecepcion {
  numero_factura: string
  fecha_recepcion: string
  motivo_correccion: string
  observacion: string
  detalles: Array<{
    id_factura_recepcion_detalle: number
    cantidad_recibida: number
  }>
}
