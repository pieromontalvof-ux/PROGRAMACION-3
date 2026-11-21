import { asPromotion, optionLabel, money, schedule } from './promotionSummary'

export function PromotionReview({ value }: { value: unknown }) {
  const p = asPromotion(value)
  if (!p) return null
  return <section className="assistant-promotion-summary" aria-label="Resumen de promoción">
    <div className="assistant-promotion-heading"><h3>{p.nombre || 'Promoción'}</h3><strong>{money(p.precio)}</strong></div>
    <p className="assistant-promotion-meta">{p.activo === true ? 'Activa' : p.activo === false ? 'Inactiva' : 'Estado por definir'} · {schedule(p)}</p>
    <div className="assistant-table-wrap"><table className="assistant-data-table"><thead><tr><th scope="col">Incluye</th><th scope="col">Productos</th></tr></thead>
      <tbody>{p.grupos.map((g, i) => <tr key={i}><th scope="row">{g.opciones.length === 1 ? 'Incluye' : 'Elige'} {g.cantidad_elegir}</th><td>
        {g.opciones.map((o,j) => <div key={j}>{j > 0 && <span className="assistant-promotion-or">o </span>}{optionLabel(o)}</div>)}
        {g.opciones.length > 1 && g.cantidad_elegir > 1 && <small>{g.permite_repetir ? 'Puedes repetir una opción.' : 'Elige opciones diferentes.'}</small>}
      </td></tr>)}</tbody></table></div>
  </section>
}
