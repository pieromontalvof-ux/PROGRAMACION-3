import { formatearUnidad } from '../../utils/unitHelpers'
import { Boxes, ChevronRight, Info } from 'lucide-react'
import type { Consulta } from './service'
import { RecipeCards } from './RecipeCards'
import { FormattedAnswer } from './FormattedAnswer'
import {legacyPurchaseSummary} from './purchaseSummary'
import {legacyPromotionSummary} from './promotionSummary'

const number = (value: unknown) => typeof value === 'number'
  ? value.toLocaleString('es-PE', { maximumFractionDigits: 3 }) : '—'

export function AnswerContent({ text, queries = [] }: { text: string; queries?: Consulta[] }) {
  const last = queries.at(-1)
  const eventReport = queries.filter(q => q.recurso === 'eventos_cercanos').at(-1)?.registros[0]
  const purchaseSummary = queries.some(q => q.recurso === 'demanda_rotacion' || q.recurso === 'pedido_sugerido')
  const fallback = <>
    <FormattedAnswer text={legacyPromotionSummary(text)??legacyPurchaseSummary(text)??text} />
    {typeof eventReport?.detalle === 'string' && eventReport.detalle && <details className="assistant-event-details">
      <summary><ChevronRight size={16} aria-hidden="true" />Ver revisión de eventos</summary>
      <FormattedAnswer text={eventReport.detalle} />
    </details>}
  </>
  if (last?.recurso === 'recetas') {
    if (!last.registros.length || last.registros.length > 3) return fallback
    const cards = <RecipeCards queries={queries} fallback={null} />
    return <>
      {fallback}
      {<details className="assistant-event-details">
        <summary><ChevronRight size={16} aria-hidden="true" />Ver recetas consultadas</summary>
        {cards}
      </details>}
    </>
  }
  if (last?.recurso !== 'stock' || eventReport || purchaseSummary || !last.registros.length) return fallback

  // Keep the most recent result and its preceding pages, not earlier searches.
  const pages = [last]
  for (let i = queries.length - 2; i >= 0 && pages[0].desde > 0; i--) {
    const page = queries[i]
    if (page.recurso !== 'stock' || page.total !== last.total || page.desde + page.registros.length !== pages[0].desde) break
    pages.unshift(page)
  }
  const products = [...new Map(pages.flatMap(p => p.registros).map(p => [p.id_producto, p])).values()]
  const categories = [...new Set(products.map(p => String(p.categoria ?? 'Productos')))]
  const below = products.filter(p => typeof p.stock_actual === 'number' && typeof p.stock_minimo === 'number' && p.stock_actual < p.stock_minimo).length
  // Preserve explanations and warnings, replace the repeated product listing with real rows.
  const names = products.map(p => String(p.nombre ?? p.producto ?? '').toLocaleLowerCase()).filter(Boolean)
  const explanation = text.split('\n').filter(line => {
    const listing = /^\s*(?:[-*+] |\d+[.)] |\|)/.test(line)
    const productRow = names.some(name => line.toLocaleLowerCase().includes(name))
    const tableHeader = /^\s*\|/.test(line) && (/producto|stock|disponible|mínimo/i.test(line) || /^[\s|:-]+$/.test(line))
    return !(listing && productRow) && !tableHeader
  }).join('\n').trim()
  return <>
    {explanation && <FormattedAnswer text={explanation} />}
    <section className="assistant-stock-card">
      <header><span className="assistant-stock-icon"><Boxes size={23} /></span><div>
        <h3>{below === products.length ? 'Productos bajo el mínimo' : 'Existencias de productos'}</h3>
        <p>{products.length} de {last.total} productos · {categories.length} categorías mostradas</p>
      </div></header>
      {categories.map(category => <section className="assistant-stock-category" key={category}>
        <h4>{category}<span>{products.filter(p => String(p.categoria ?? 'Productos') === category).length}</span></h4>
        <div className="assistant-table-wrap" tabIndex={0} role="region" aria-label={`Existencias de ${category}`}>
          <table className="assistant-data-table"><thead><tr><th scope="col">Producto</th><th scope="col">Disponible</th><th scope="col">Mínimo</th><th scope="col">Falta para el mínimo</th></tr></thead>
            <tbody>{products.filter(p => String(p.categoria ?? 'Productos') === category).map(p => {
              const deficit = typeof p.stock_actual === 'number' && typeof p.stock_minimo === 'number' ? Math.max(0, p.stock_minimo - p.stock_actual) : null
              return <tr key={String(p.id_producto)}><th scope="row">{String(p.nombre ?? p.producto ?? 'Producto')}</th>
                <td>{number(p.stock_actual)} <small>{formatearUnidad(p)}</small></td>
                <td>{number(p.stock_minimo)} <small>{formatearUnidad(p)}</small></td>
                <td><span className={deficit && deficit > 0 ? 'assistant-stock-low' : 'assistant-stock-ok'}>{number(deficit)} <small>{formatearUnidad(p)}</small></span></td></tr>
            })}</tbody></table>
        </div>
      </section>)}
      {products.length < last.total && <footer><Info size={17} />Se muestran {products.length} de {last.total} productos. Puedes pedir que continúe con los restantes.</footer>}
    </section>
  </>
}
