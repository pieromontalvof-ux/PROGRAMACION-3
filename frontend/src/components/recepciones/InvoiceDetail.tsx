import { useRef, useState } from 'react'
import type { RespuestaDetalleRecepcion } from '../../types/reception'
import { registrarEntrega } from '../../services/receptionService'
import { formatearUnidad } from '../../utils/unitHelpers'
import './InvoiceFields.css'
import {FactApiPanel} from '../FactApiPanel'

export function InvoiceDetail({ recepcion, token, puedeRecibir, onSaved, edicion }: {
  recepcion: RespuestaDetalleRecepcion['recepcion']; token: string
  puedeRecibir: boolean; onSaved: () => Promise<void>
  edicion?: { activa:boolean; numero:string; fecha:string; cantidades:Record<number,string>;
    numeroCambio:(v:string)=>void; fechaCambio:(v:string)=>void; cantidadCambio:(id:number,v:string)=>void }
}) {
  const [cantidades, setCantidades] = useState<Record<number, string>>({})
  const [fecha, setFecha] = useState(() => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(new Date()))
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const clave = useRef(crypto.randomUUID())
  const factura = recepcion.factura
  if (!factura) return <p className="invoice-note">Recepción anterior: no se registraron precios ni importes de factura.</p>
  const moneda = (n: number) => `${factura.moneda} ${n.toFixed(2)}`
  const filas = factura.lineas.map(l => ({ ...l, recibido: recepcion.detalles.find(d => d.id_producto === l.id_producto)?.cantidad_recibida ?? 0 }))
  const pendiente = filas.some(l => l.cantidad_facturada > l.recibido)
  const registrar = async () => {
    const detalles = filas.filter(l => Number(cantidades[l.id_producto]) > 0).map(l => ({ id_producto: l.id_producto, cantidad_recibida: Number(cantidades[l.id_producto]) }))
    if (!detalles.length) { setError('Indica al menos una cantidad recibida.'); return }
    try {
      setGuardando(true); setError('')
      await registrarEntrega(token, recepcion.id_factura_recepcion, { fecha, detalles, clave: clave.current })
      setCantidades({}); clave.current = crypto.randomUUID(); await onSaved()
    } catch(e) { setError(e instanceof Error ? e.message : 'No se pudo registrar la entrega.') }
    finally { setGuardando(false) }
  }
  return <section className="invoice-detail">
    <h3>Factura {edicion?.activa ? <input aria-label="Número de factura" value={edicion.numero} onChange={e=>edicion.numeroCambio(e.target.value)}/> : recepcion.numero_factura} · {pendiente ? 'Entrega parcial' : 'Entrega completa'}</h3>
    <p><b>Fecha de recepción:</b> {edicion?.activa ? <input aria-label="Fecha de recepción" type="date" value={edicion.fecha} onChange={e=>edicion.fechaCambio(e.target.value)}/> : recepcion.fecha_recepcion}</p>
    <div className="invoice-summary"><p><b>Proveedor:</b> {factura.proveedor.razon_social || factura.proveedor.nombre}<br />RUC: {factura.proveedor.ruc || 'No registrado'}<br />{factura.proveedor.direccion}</p>
      <p><b>Fecha de factura del proveedor:</b> {factura.fecha_emision}<br /><b>OC:</b> {recepcion.codigo_orden}<br /><b>Moneda:</b> {factura.moneda}</p></div>
    {pendiente && <p className="invoice-note">Los importes corresponden a la factura completa; aún faltan productos de esta entrega.</p>}
    <FactApiPanel key={recepcion.id_factura_recepcion} origin="COMPRA" source={recepcion.id_factura_recepcion} token={token}/><div className="invoice-scroll"><table className="invoice-table"><thead><tr><th>Producto</th><th>Recibido</th><th>Costo total</th><th>Unitario sin IGV</th><th>Importe sin IGV</th><th>IGV</th></tr></thead>
      <tbody>{filas.map(l => <tr key={l.id_producto}><td>{l.nombre}<small>{l.codigo} · {formatearUnidad(l.unidad)}</small></td><td>{edicion?.activa ? (()=>{const d=recepcion.detalles.find(d=>d.id_producto===l.id_producto);return d?<input aria-label={`Recibido ${l.nombre}`} type="number" min="0.001" max={d.maximo_permitido} step="0.001" value={edicion.cantidades[d.id_factura_recepcion_detalle]??''} onChange={e=>edicion.cantidadCambio(d.id_factura_recepcion_detalle,e.target.value)}/>:l.recibido})() : l.recibido}</td><td>{moneda(l.total)}</td><td>{factura.moneda} {l.precio_unitario.toFixed(4)}</td><td>{moneda(l.subtotal)}</td><td>{l.afectacion_igv === 'EXONERADO' ? 'Exonerado' : l.afectacion_igv === 'INAFECTO' ? 'Inafecto' : moneda(l.igv)}</td></tr>)}</tbody></table></div>
    <div className="invoice-summary"><span>Subtotal: {moneda(factura.subtotal)}</span><span>IGV: {moneda(factura.igv)}</span><strong>Total: {moneda(factura.total)}</strong></div>
    {!edicion?.activa && pendiente && puedeRecibir && ['ENVIADA', 'RECEPCION_PARCIAL'].includes(recepcion.estado_orden_compra) && <details><summary>Registrar otra entrega de esta factura</summary>
      <div className="invoice-delivery"><label>Fecha de entrega<input type="date" value={fecha} onChange={e => setFecha(e.target.value)} /></label>
        {filas.filter(l => l.cantidad_facturada > l.recibido).map(l => <label key={l.id_producto}>{l.nombre} ({formatearUnidad(l.unidad)})<input type="number" min="0" max={l.cantidad_facturada-l.recibido} step="0.001" value={cantidades[l.id_producto] ?? ''} onChange={e => setCantidades(a => ({ ...a, [l.id_producto]: e.target.value }))} /></label>)}
        <button disabled={guardando} onClick={() => void registrar()}>{guardando ? 'Guardando...' : 'Registrar entrega'}</button></div>
    </details>}
    {error && <p role="alert">{error}</p>}
  </section>
}
