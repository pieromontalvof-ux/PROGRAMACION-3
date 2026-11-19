import { useRef, useState } from 'react'
import type { RespuestaDetalleRecepcion } from '../../types/reception'
import { registrarEntrega } from '../../services/receptionService'
import { formatearUnidad } from '../../utils/unitHelpers'
import './InvoiceFields.css'

export function InvoiceDetail({ recepcion, token, puedeRecibir, onSaved }: {
  recepcion: RespuestaDetalleRecepcion['recepcion']; token: string
  puedeRecibir: boolean; onSaved: () => Promise<void>
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
    <h3>Factura {recepcion.numero_factura} · {pendiente ? 'Entrega parcial' : 'Entrega completa'}</h3>
    {(factura.datos_ficticios || recepcion.numero_factura.startsWith('DEMO')) && <p className="invoice-note">Datos ficticios para demostración.</p>}
    <div className="invoice-summary"><p><b>Proveedor:</b> {factura.proveedor.razon_social || factura.proveedor.nombre}<br />RUC: {factura.proveedor.ruc || 'No registrado'}<br />{factura.proveedor.direccion}</p>
      <p><b>Emisión:</b> {factura.fecha_emision}<br /><b>OC:</b> {recepcion.codigo_orden}<br /><b>Moneda:</b> {factura.moneda}</p></div>
    <div className="invoice-scroll"><table className="invoice-table"><thead><tr><th>Producto</th><th>Facturado</th><th>Recibido</th><th>Pendiente</th><th>Precio sin IGV</th><th>Descuento</th><th>Afectación</th><th>IGV</th><th>Total</th></tr></thead>
      <tbody>{filas.map(l => <tr key={l.id_producto}><td>{l.nombre}<small>{l.codigo} · {formatearUnidad(l.unidad)}</small></td><td>{l.cantidad_facturada}</td><td>{l.recibido}</td><td>{Math.max(0, Math.round((l.cantidad_facturada - l.recibido) * 1000) / 1000)}</td><td>{moneda(l.precio_unitario)}</td><td>{moneda(l.descuento)}</td><td>{l.afectacion_igv === 'EXONERADO' ? 'Exonerado' : l.afectacion_igv === 'INAFECTO' ? 'Inafecto' : l.igv_porcentaje > 0 ? 'Gravado' : 'Sin clasificar'}</td><td>{moneda(l.igv)} ({l.igv_porcentaje}%)</td><td>{moneda(l.total)}</td></tr>)}</tbody></table></div>
    {factura.base_gravada !== undefined && <div className="invoice-summary"><span>Gravado: {moneda(factura.base_gravada)}</span><span>Exonerado: {moneda(factura.base_exonerada ?? 0)}</span><span>Inafecto: {moneda(factura.base_inafecta ?? 0)}</span></div>}
    <div className="invoice-summary"><span>Subtotal: {moneda(factura.subtotal)}</span><span>IGV: {moneda(factura.igv)}</span><strong>Total: {moneda(factura.total)}</strong></div>
    <details><summary>Ver entregas registradas ({recepcion.entregas?.length ?? 0})</summary>
      {(recepcion.entregas ?? []).map((e, i) => <p className="invoice-note" key={i}>{e.fecha} · Usuario #{e.usuario}: {e.detalles.map(d => `${factura.lineas.find(l => l.id_producto === d.id_producto)?.nombre ?? d.id_producto}: ${d.cantidad_recibida}`).join('; ')}</p>)}
    </details>
    {pendiente && puedeRecibir && ['ENVIADA', 'RECEPCION_PARCIAL'].includes(recepcion.estado_orden_compra) && <details><summary>Registrar otra entrega de esta factura</summary>
      <div className="invoice-delivery"><label>Fecha de entrega<input type="date" value={fecha} onChange={e => setFecha(e.target.value)} /></label>
        {filas.filter(l => l.cantidad_facturada > l.recibido).map(l => <label key={l.id_producto}>{l.nombre} ({formatearUnidad(l.unidad)})<input type="number" min="0" max={l.cantidad_facturada-l.recibido} step="0.001" value={cantidades[l.id_producto] ?? ''} onChange={e => setCantidades(a => ({ ...a, [l.id_producto]: e.target.value }))} /></label>)}
        <button disabled={guardando} onClick={() => void registrar()}>{guardando ? 'Guardando...' : 'Registrar entrega'}</button></div>
    </details>}
    {error && <p role="alert">{error}</p>}
  </section>
}
