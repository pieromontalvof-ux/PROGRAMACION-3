import type { FacturaProveedorEntrada, LineaFacturaProveedor, ProductoPendienteRecepcion } from '../../types/reception'
import { formatearUnidad } from '../../utils/unitHelpers'
import './InvoiceFields.css'

// Fixed-point arithmetic matches the backend's decimal HALF_UP rounding.
function importeCentimos(l: LineaFacturaProveedor): number {
  if (![l.cantidad_facturada, l.precio_unitario, l.descuento, l.igv_porcentaje].every(n => Number.isFinite(n) && n >= 0 && n <= 999999999)) return NaN
  const bruto = (BigInt(Math.round(l.cantidad_facturada * 1000)) * BigInt(Math.round(l.precio_unitario * 1000000)) + 5000000n) / 10000000n
  const base = bruto - BigInt(Math.round(l.descuento * 100))
  const igv = (base * BigInt(Math.round(l.igv_porcentaje * 100)) + 5000n) / 10000n
  return Number(base + igv)
}

export function InvoiceFields({ productos, value, onChange }: {
  productos: ProductoPendienteRecepcion[]
  value: FacturaProveedorEntrada
  onChange: (v: FacturaProveedorEntrada) => void
}) {
  const afectar = (id: number, tipo: 'GRAVADO' | 'EXONERADO' | 'INAFECTO') => onChange({ ...value,
    lineas: value.lineas.map(l => l.id_producto === id ? { ...l, afectacion_igv: tipo, igv_porcentaje: tipo === 'GRAVADO' ? (l.igv_porcentaje || 18) : 0 } : l) })
  const cambiar = (id: number, campo: string, valor: number) => onChange({ ...value,
    lineas: value.lineas.map(l => l.id_producto === id ? { ...l, [campo]: valor } : l) })
  const total = value.lineas.reduce((s, l) => s + importeCentimos(l), 0) / 100
  return <section className="invoice-fields">
    <div className="invoice-fields-header">
      <label>Fecha de emisión<input type="date" required value={value.fecha_emision} onChange={e => onChange({ ...value, fecha_emision: e.target.value })} /></label>
      <label>Moneda<select value={value.moneda} onChange={e => onChange({ ...value, moneda: e.target.value as 'PEN' | 'USD' })}><option value="PEN">Soles (PEN)</option><option value="USD">Dólares (USD)</option></select></label>
    </div>
    <p>Precios sin IGV por unidad de inventario. El descuento es un importe por línea; indica el impuesto que figura en tu factura.</p>
    <div className="invoice-scroll"><table className="invoice-table"><thead><tr><th>Producto / unidad</th><th>Facturado</th><th>Precio unitario</th><th>Descuento</th><th>Afectación</th><th>IGV (%)</th><th>Total</th></tr></thead>
      <tbody>{value.lineas.map(l => {
        const p = productos.find(p => p.id_producto === l.id_producto)!
        return <tr key={l.id_producto}><td>{p.nombre}<small>Por {formatearUnidad(p.unidad)}</small></td>
          {(['cantidad_facturada', 'precio_unitario', 'descuento'] as const).map(campo => <td key={campo}><input
            aria-label={`${campo.replaceAll('_', ' ')} ${p.nombre}`} type="number" min="0"
            max={campo === 'cantidad_facturada' ? p.cantidad_pendiente : undefined}
            step={campo === 'precio_unitario' ? '0.000001' : campo === 'cantidad_facturada' ? '0.001' : '0.01'}
            value={Number.isFinite(l[campo]) ? l[campo] : ''} onChange={e => cambiar(l.id_producto, campo, Number(e.target.value))} /></td>)}
          <td><select aria-label={`Afectación ${p.nombre}`} value={l.afectacion_igv ?? (l.igv_porcentaje ? 'GRAVADO' : '')} onChange={e => afectar(l.id_producto, e.target.value as 'GRAVADO' | 'EXONERADO' | 'INAFECTO')} required>
            <option value="" disabled>Selecciona</option><option value="GRAVADO">Gravado</option><option value="EXONERADO">Exonerado</option><option value="INAFECTO">Inafecto</option></select></td>
          <td><input aria-label={`igv porcentaje ${p.nombre}`} type="number" min={l.afectacion_igv === 'EXONERADO' || l.afectacion_igv === 'INAFECTO' ? 0 : 0.01} max="100" step="0.01" disabled={l.afectacion_igv === 'EXONERADO' || l.afectacion_igv === 'INAFECTO'} value={l.igv_porcentaje} onChange={e => cambiar(l.id_producto, 'igv_porcentaje', Number(e.target.value))} /></td>
          <td>{(importeCentimos(l) / 100).toFixed(2)}</td></tr>
      })}</tbody></table></div>
    <strong>Total factura: {value.moneda} {Number.isFinite(total) ? total.toFixed(2) : '—'}</strong>
  </section>
}
