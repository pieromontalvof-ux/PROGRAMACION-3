import { money } from './receipt'

export interface DailySalesClosure {
  fecha: string
  simulacion: boolean
  cantidad: number
  efectivo: number
  tarjeta: number
  total: number
}

export function DailySalesClosures({ cierres }: { cierres: DailySalesClosure[] }) {
  if (!cierres.length) return null

  return <details className="journal-list journal-daily-closures" open={cierres.length === 1}>
    <summary>Cierres diarios de ventas ({cierres.length})</summary>
    <p className="journal-muted">Totales del día completo, por fecha de Lima.</p>
    <div className="journal-sales-scroll">
      <table className="journal-sales-table">
        <thead><tr><th scope="col">Fecha</th><th scope="col">Ventas</th><th scope="col">Efectivo</th>
          <th scope="col">Tarjeta</th><th scope="col">Total</th></tr></thead>
        <tbody>{cierres.map(cierre => <tr key={cierre.fecha}>
          <th scope="row"><time dateTime={cierre.fecha}>{cierre.fecha}</time>
            {cierre.simulacion && <small> · Simulación</small>}</th>
          <td>{cierre.cantidad}</td><td>{money(cierre.efectivo)}</td>
          <td>{money(cierre.tarjeta)}</td><td>{money(cierre.total)}</td>
        </tr>)}</tbody>
      </table>
    </div>
  </details>
}
