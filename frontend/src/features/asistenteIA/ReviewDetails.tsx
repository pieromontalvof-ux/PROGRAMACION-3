import { etiqueta, valorDeCampo } from './labels'
import { revisionVisible } from './reviewDisplay'
import { PurchaseOrderReview,type PurchaseEditHandlers } from './PurchaseOrderReview'
import { asPromotion, PromotionReview } from './PromotionReview'

export function ReviewDetails({ value,resource,purchase }: { value: unknown;resource?:string;purchase?:PurchaseEditHandlers }) {
  if (resource==='promociones' && asPromotion(value)) return <PromotionReview value={value} />
  if (resource==='ordenes_compra' && value && typeof value==='object') {
    const products=(value as Record<string,unknown>).productos
    if (Array.isArray(products) && products.every(row=>row && typeof row==='object' && !Array.isArray(row))) {
      return <PurchaseOrderReview rows={products} purchase={purchase} />
    }
  }
  return <Details value={revisionVisible(value)} />
}

function Details({ value }: { value: unknown }) {
  if (value === null || value === undefined) return <span>Sin asignar</span>
  if (typeof value === 'boolean') return <span>{value ? 'Sí' : 'No'}</span>
  if (Array.isArray(value)) return <ul className="assistant-values">{value.map((v, i) => <li key={i}><Details value={v} /></li>)}</ul>
  if (typeof value === 'object') return <dl className="assistant-fields">{Object.entries(value).map(([key, v]) =>
    <div key={key}><dt>{etiqueta(key)}</dt><dd><Details value={valorDeCampo(key, v)} /></dd></div>)}</dl>
  return <span>{String(value)}</span>
}
