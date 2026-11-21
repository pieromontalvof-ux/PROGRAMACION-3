import type { LineaFacturaProveedor } from '../../types/reception'

export function importesLinea(l: LineaFacturaProveedor) {
 const total=l.costo_total??Math.round((l.cantidad_facturada*l.precio_unitario-l.descuento)*(1+l.igv_porcentaje/100)*100)/100
 const cents=Number.isFinite(total)&&total>=0?Math.round(total*100):0
 const tasa=l.afectacion_igv==='EXONERADO'?0:18
 const base=tasa?Number((BigInt(cents)*100n+59n)/118n):cents
 return {total:cents/100,base:base/100,igv:(cents-base)/100,unitario:l.cantidad_facturada>0?base/100/l.cantidad_facturada:0}
}
