import { useState } from 'react'
import { Download, Workflow } from 'lucide-react'
import { nombresAgentes, obtenerActividad, type ActividadAgentes, type AgenteId } from './service'

const name = (id: string) => nombresAgentes[id as AgenteId] ?? id
const labels: Record<string, string> = { agente_inicio: 'Inicio', agente_fin: 'Resultado del agente', agente_error: 'Error del agente', delegacion: 'Delegación', retorno: 'Entrega de resultado', mensaje_entre_agentes: 'Mensaje entre agentes', herramienta_inicio: 'Herramienta invocada', herramienta_fin: 'Resultado de herramienta', respuesta_final: 'Respuesta final', ruta_respuesta: 'Área de respuesta' }
export function AgentActivity({ activity, token }: { activity: ActividadAgentes; token: string }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function download() {
    setBusy(true); setError('')
    try {
      const original = await obtenerActividad(token, activity.id)
      const url = URL.createObjectURL(new Blob([JSON.stringify(original, null, 2)], { type: 'application/json;charset=utf-8' }))
      const link = document.createElement('a'); link.href = url; link.download = `actividad-agentes-${original.id}.json`
      document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000)
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo descargar la actividad.') }
    finally { setBusy(false) }
  }
  return <details className="assistant-agent-activity">
    <summary><Workflow size={17} />Ver actividad de agentes <span>{activity.agentes.length} participantes</span></summary>
    <div className="assistant-agent-activity-body">
      <p><strong>{activity.agentes.map(name).join(' → ')}</strong></p>
      <p className="assistant-activity-meta">Solicitud {activity.id} · {new Date(activity.inicio).toLocaleString('es-PE', { timeZone: 'America/Lima' })}</p>
      <p>Entrada: {activity.entrada}</p>
      <p className="assistant-activity-meta">Origen: {activity.url}</p>
      <p className="assistant-activity-meta">{activity.nota} El Coordinador incluye la selección programada de la ruta.</p>
      {activity.truncada && <p role="status">La actividad superó el límite de eventos. Esta traza es parcial.</p>}
      <ol>{activity.eventos.map(event => <li key={event.paso}>
        <header><strong>{labels[event.tipo] ?? event.tipo}</strong><time>{new Date(event.fecha).toLocaleTimeString('es-PE', { timeZone: 'America/Lima' })}</time></header>
        <p>{event.de && event.a ? `${name(event.de)} → ${name(event.a)}` : name(event.agente)}{event.herramienta && ` · ${event.herramienta}`}{event.estado && ` · ${event.estado}`}</p>
        {event.mensaje && <p>{event.mensaje}</p>}
        {event.parametros !== undefined && <details><summary>Parámetros</summary><pre>{JSON.stringify(event.parametros, null, 2)}</pre></details>}
        {event.resultado !== undefined && <details><summary>Resultado resumido</summary><pre>{JSON.stringify(event.resultado, null, 2)}</pre></details>}
      </li>)}</ol>
      <button className="assistant-secondary" onClick={download} disabled={busy}><Download size={16} />{busy ? 'Descargando…' : 'Descargar traza JSON'}</button>
      {error && <p role="alert">{error}</p>}
    </div>
  </details>
}
