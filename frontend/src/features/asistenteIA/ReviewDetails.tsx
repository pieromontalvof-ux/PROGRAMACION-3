import { etiqueta } from './labels'

export function ReviewDetails({ value }: { value: unknown }) {
  if (value === null || value === undefined) return <span>Sin asignar</span>
  if (typeof value === 'boolean') return <span>{value ? 'Sí' : 'No'}</span>
  if (Array.isArray(value)) return <ol className="assistant-values">{value.map((v, i) => <li key={i}><ReviewDetails value={v} /></li>)}</ol>
  if (typeof value === 'object') return <dl className="assistant-fields">{Object.entries(value).map(([key, v]) =>
    <div key={key}><dt>{etiqueta(key)}</dt><dd><ReviewDetails value={v} /></dd></div>)}</dl>
  return <span>{String(value)}</span>
}
