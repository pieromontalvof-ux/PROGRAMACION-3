import { useState, type Dispatch, type SetStateAction } from 'react'
import { Plus, Unplug } from 'lucide-react'
import type { ConfiguracionAgente } from './service'
import { etiqueta } from './labels'

export function AgentConnections({ draft, setDraft, available, busy }: {
  draft: ConfiguracionAgente; setDraft: Dispatch<SetStateAction<ConfiguracionAgente | null>>
  available: Record<string, string[]>; busy: boolean
}) {
  const [choice, setChoice] = useState('')
  const assigned = Object.keys(draft.accesos)
  const options = Object.keys(available).filter(resource => !assigned.includes(resource)).sort()
  return <>
    <div className="agent-connection-add">
      <label>Conexión disponible<select value={choice} disabled={busy || !options.length} onChange={event => setChoice(event.target.value)}>
        <option value="">{options.length ? 'Seleccionar módulo' : 'No hay más conexiones disponibles'}</option>
        {options.map(resource => <option key={resource} value={resource}>{etiqueta(resource)} · Consulta</option>)}
      </select></label>
      <button disabled={busy || !options.includes(choice)} onClick={() => {
        setDraft(current => current ? { ...current, accesos: { ...current.accesos, [choice]: ['consultar'] } } : current)
        setChoice('')
      }}><Plus size={17} />Agregar conexión</button>
    </div>
    <p>Las nuevas conexiones permiten consultar datos reales. Se activan al guardar y respetan el perfil y el local de quien consulta.</p>
    <h4>Conexiones asignadas ({assigned.length})</h4>
    {!assigned.length ? <p>Este agente no tiene conexiones asignadas. Agrega un módulo disponible.</p> : <div className="agent-access-table"><table><thead><tr><th>Módulo o recurso</th>{['consultar', 'crear', 'editar'].map(action => <th key={action}>{etiqueta(action)}</th>)}<th>Conexión</th></tr></thead><tbody>
      {assigned.map(resource => <tr key={resource}><th scope="row">{etiqueta(resource)}</th>{['consultar', 'crear', 'editar'].map(action => <td key={action}>{!available[resource]?.includes(action) ? '—' : <input type="checkbox" aria-label={`${etiqueta(action)} ${etiqueta(resource)}`} disabled={busy} checked={draft.accesos[resource]?.includes(action) ?? false} onChange={event => setDraft(current => {
        if (!current) return current
        const old = current.accesos[resource] ?? []
        const actions = event.target.checked ? [...new Set([...old, action, 'consultar'])] : action === 'consultar' ? [] : old.filter(item => item !== action)
        return { ...current, accesos: { ...current.accesos, [resource]: actions } }
      })} />}</td>)}<td><button disabled={busy} aria-label={`Quitar conexión ${etiqueta(resource)}`} onClick={() => setDraft(current => {
        if (!current) return current
        const accesses = { ...current.accesos }; delete accesses[resource]
        return { ...current, accesos: accesses }
      })}><Unplug size={16} />Quitar</button></td></tr>)}
    </tbody></table></div>}
    <details className="agent-connection-help"><summary>¿Necesitas otra acción o una fuente externa?</summary>
      <p>Crear y editar registros se realiza con el especialista que ya tiene esas herramientas, con revisión humana. Agregar una conexión de consulta no añade acciones de escritura.</p>
      <p><strong>Requiere integración:</strong> una API externa, otro sistema de ventas o un campo que la aplicación todavía no expone. Debe implementarse y probarse antes de aparecer en esta lista; escribirlo en una skill no establece la conexión.</p>
    </details>
  </>
}
