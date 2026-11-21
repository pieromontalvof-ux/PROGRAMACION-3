import type { FacturaProveedorEntrada, LineaFacturaProveedor, ProductoPendienteRecepcion } from '../../types/reception'
import { formatearUnidad } from '../../utils/unitHelpers'
import './InvoiceFields.css'

import { importesLinea } from './invoiceAmounts'
export function InvoiceFields({productos,value,onChange}:{productos:ProductoPendienteRecepcion[];value:FacturaProveedorEntrada;onChange:(v:FacturaProveedorEntrada)=>void}){
 const cambiar=(id:number,patch:Partial<LineaFacturaProveedor>)=>onChange({...value,lineas:value.lineas.map(l=>l.id_producto===id?{...l,...patch}:l)})
 const total=value.lineas.reduce((s,l)=>s+Math.round(importesLinea(l).total*100),0)/100
 return <section className="invoice-fields">
 <div className="invoice-fields-header"><label>Fecha de la factura del proveedor<input type="date" required value={value.fecha_emision} onChange={e=>onChange({...value,fecha_emision:e.target.value})}/></label><label>Moneda<select value={value.moneda} onChange={e=>onChange({...value,moneda:e.target.value as 'PEN'|'USD'})}><option value="PEN">Soles (S/)</option><option value="USD">Dólares (US$)</option></select></label></div>
 <p>Ingresa la cantidad recibida y su costo total con IGV. Los productos retirados o las cantidades faltantes quedan pendientes en la OC.</p>
 <div className="invoice-scroll"><table className="invoice-table"><thead><tr><th>Producto</th><th>Solicitado</th><th>Recibido</th><th>Costo total</th><th>Exonerado IGV</th><th>Unitario sin IGV</th><th>Importe sin IGV</th><th>IGV</th><th></th></tr></thead><tbody>{value.lineas.map(l=>{
 const p=productos.find(p=>p.id_producto===l.id_producto)!;const n=importesLinea(l)
 return <tr key={l.id_producto}><td>{p.nombre}<small>{p.codigo} · {formatearUnidad(p.unidad)}</small></td><td>{p.cantidad_pendiente}</td><td><input aria-label={`Recibido ${p.nombre}`} type="number" min="0" max={p.cantidad_pendiente} step="0.001" value={l.cantidad_facturada} onChange={e=>cambiar(l.id_producto,{cantidad_facturada:Number(e.target.value)})}/></td><td><input aria-label={`Costo total ${p.nombre}`} type="number" min="0.01" step="0.01" value={l.costo_total??n.total} onChange={e=>cambiar(l.id_producto,{costo_total:Number(e.target.value)})}/></td><td><input aria-label={`Exonerado IGV ${p.nombre}`} type="checkbox" checked={l.afectacion_igv==='EXONERADO'} onChange={e=>cambiar(l.id_producto,{afectacion_igv:e.target.checked?'EXONERADO':'GRAVADO',igv_porcentaje:e.target.checked?0:18})}/></td><td>{n.unitario.toFixed(4)}</td><td>{n.base.toFixed(2)}</td><td>{n.igv.toFixed(2)}</td><td><button type="button" aria-label={`Quitar ${p.nombre}`} onClick={()=>onChange({...value,lineas:value.lineas.filter(x=>x.id_producto!==l.id_producto)})}>Quitar</button></td></tr>
 })}</tbody></table></div>
 {productos.some(p=>!value.lineas.some(l=>l.id_producto===p.id_producto))&&<label>Volver a agregar producto<select value="" onChange={e=>{const p=productos.find(p=>p.id_producto===Number(e.target.value));if(p)onChange({...value,lineas:[...value.lineas,{id_producto:p.id_producto,cantidad_facturada:p.cantidad_pendiente,costo_total:0,precio_unitario:0,descuento:0,afectacion_igv:'GRAVADO',igv_porcentaje:18}]})}}><option value="">Seleccionar producto de la OC</option>{productos.filter(p=>!value.lineas.some(l=>l.id_producto===p.id_producto)).map(p=><option value={p.id_producto} key={p.id_producto}>{p.nombre}</option>)}</select></label>}
 <strong>Total factura: {value.moneda} {total.toFixed(2)}</strong></section>
}
