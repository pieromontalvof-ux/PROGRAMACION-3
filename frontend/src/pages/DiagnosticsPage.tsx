import { useEffect, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../context/authState'
import './DiagnosticsPage.css'

interface Metrics {
  requests: number; errors: number; capacity: number; retention_seconds: number
  routes: {method: string; route: string; requests: number; errors: number; p95_ms: number}[]
}

export function DiagnosticsPage() {
  const { token, perfilActivo } = useAuth()
  const [result, setResult] = useState<{token: string | null; data?: Metrics; error?: string} | null>(null)
  const [version, setVersion] = useState(0)
  const allowed = perfilActivo?.id_perfil === 1
  useEffect(() => {
    if (!allowed || !token) return
    const controller = new AbortController()
    fetch(`${import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'}/diagnostico`, {
      headers: { Authorization: `Bearer ${token}` }, signal: controller.signal,
    }).then(async response => {
      const data = await response.json()
      if (!response.ok) throw new Error(data.mensaje ?? 'No se pudo cargar el diagnóstico')
      if (!controller.signal.aborted) setResult({token, data})
    }).catch(error => {
      if (!controller.signal.aborted) setResult({token, error: error.message})
    })
    return () => controller.abort()
  }, [allowed, token, version])
  if (!allowed) return <Navigate to="/home" replace />
  const current = result?.token === token ? result : null
  return <section className="diagnostics-page">
    <header><div><h1>Diagnóstico del sistema</h1><p>Actividad técnica reciente del backend.</p></div>
      <button onClick={() => setVersion(value => value + 1)}>Actualizar</button></header>
    {current?.error && <p role="alert">{current.error}</p>}
    {!current && <p role="status">Cargando diagnóstico…</p>}
    {current?.data && <>
      <div className="diagnostics-counters"><article><span>Solicitudes</span><strong>{current.data.requests}</strong></article>
        <article><span>Errores del servidor</span><strong>{current.data.errors}</strong></article></div>
      <p>Últimos {current.data.retention_seconds / 60} minutos, hasta {current.data.capacity} solicitudes de este proceso. Se reinicia al reiniciar el servidor.</p>
      <div className="diagnostics-table"><table><thead><tr><th>Operación</th><th>Ruta</th><th>Solicitudes</th><th>Errores</th><th>Tiempo p95 (ms)</th></tr></thead>
        <tbody>{current.data.routes.map(row => <tr key={row.method + row.route}><td>{row.method}</td><td>{row.route}</td><td>{row.requests}</td><td>{row.errors}</td><td>{row.p95_ms}</td></tr>)}</tbody></table></div>
      <p>El tiempo p95 indica cuánto tardó el 95% de las solicitudes. No se guardan mensajes, documentos ni credenciales en estas métricas.</p>
    </>}
  </section>
}
