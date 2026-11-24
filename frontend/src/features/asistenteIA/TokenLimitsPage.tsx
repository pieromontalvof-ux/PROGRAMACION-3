import { useEffect, useRef, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../../context/authState'
import './TokenLimitsPage.css'

type Limits = { diario: number | null; mensual: number | null }
type Assignment = { id: number; nombre: string }
type Policy = Limits & { consultas_habilitadas: boolean; activo: boolean; global_diario: number | null; global_mensual: number | null }
type User = Limits & { id_usuario: number; nombre: string; correo: string; personalizado: boolean; consumo_diario: number; consumo_mensual: number; pendiente: number; roles?: Assignment[]; locales?: Assignment[] }
type Report = { configuracion: Policy; usuarios: User[]; dia: string; mes: string; roles?: Assignment[]; locales?: Assignment[] }
const format = (n: number) => Number(n).toLocaleString('es-PE')

async function api<T>(token: string, path = '', data?: unknown, signal?: AbortSignal, remove = false): Promise<T> {
  const base = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const response = await fetch(`${base}/asistente-ia/limites${path}`, {
    method: remove ? 'DELETE' : data === undefined ? 'GET' : 'PUT', signal,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: data === undefined ? undefined : JSON.stringify(data),
  })
  const result = await response.json()
  if (!response.ok) throw new Error(response.status === 404
    ? 'El servidor todavía no tiene disponible esta sección. Reinicia el backend con la versión actual y vuelve a intentar.'
    : result.mensaje ?? 'No se pudo actualizar el consumo.')
  return result
}

export function TokenLimitsPage() {
  const { token, perfilActivo } = useAuth()
  if (perfilActivo?.id_perfil !== 1) return <Navigate to="/home/asistente-ia" replace />
  return <Administration key={token} token={token!} />
}

function LimitInput({ label, value, change }: { label: string; value: number | null; change: (n: number | null) => void }) {
  return <label>{label}<input type="number" min="0" max="1000000000000" step="1" value={value ?? ''}
    placeholder="Sin límite" onChange={event => change(event.target.value === '' ? null : Number(event.target.value))} /></label>
}

function Administration({ token }: { token: string }) {
  const [report, setReport] = useState<Report | null>(null)
  const [policy, setPolicy] = useState<Policy | null>(null)
  const [selected, setSelected] = useState<User | null>(null)
  const [search, setSearch] = useState('')
  const [localFilter, setLocalFilter] = useState('')
  const [roleFilter, setRoleFilter] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [reload, setReload] = useState(0)
  const editor = useRef<HTMLFormElement>(null)
  const selectedId = selected?.id_usuario
  useEffect(() => {
    if (selectedId === undefined) return
    editor.current?.scrollIntoView?.({ block: 'center', behavior: 'smooth' })
    editor.current?.querySelector<HTMLInputElement>('input')?.focus({ preventScroll: true })
  }, [selectedId])
  useEffect(() => {
    const controller = new AbortController()
    void api<Report>(token, '', undefined, controller.signal).then(data => {
      setReport(data); setPolicy(previous => previous ?? data.configuracion)
    }).catch(e => { if (!controller.signal.aborted) setError(e.message) })
    return () => controller.abort()
  }, [token, reload])
  async function save(path: string, data: unknown, remove = false) {
    setBusy(true); setError(''); setMessage('')
    try {
      await api(token, path, data, undefined, remove)
      setMessage('Límites guardados. Se aplicarán antes de las próximas llamadas.'); if (path) setSelected(null); setReload(n => n + 1)
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo guardar.') }
    finally { setBusy(false) }
  }
  const users = report?.usuarios.filter(user =>
    `${user.nombre} ${user.correo}`.toLowerCase().includes(search.toLowerCase())
    && (!localFilter || user.locales?.some(local => local.id === Number(localFilter)))
    && (!roleFilter || user.roles?.some(role => role.id === Number(roleFilter)))) ?? []
  async function toggleAssistant() {
    if (!report) return
    setBusy(true); setError(''); setMessage('')
    try {
      const enabled = !report.configuracion.consultas_habilitadas
      await api(token, '/estado', { habilitado: enabled })
      setReport({ ...report, configuracion: { ...report.configuracion, consultas_habilitadas: enabled } })
      setPolicy(previous => previous ? { ...previous, consultas_habilitadas: enabled } : previous)
      setMessage(enabled ? 'Asistente activado.' : 'Asistente apagado.')
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo cambiar el estado.') }
    finally { setBusy(false) }
  }
  return <main className="token-limits">
    <header><h1>Límites y consumo</h1></header>
    {error && <p role="alert" className="token-error">{error}</p>}
    {message && <p role="status">{message}</p>}
    {!report || !policy ? error
      ? <button onClick={() => { setError(''); setReload(n => n + 1) }}>Reintentar</button>
      : <p role="status">Cargando configuración…</p> : <>
      <section className="token-power"><h2>Estado general</h2>
        <strong role="status">{report.configuracion.consultas_habilitadas ? 'Asistente activado' : 'Asistente apagado'}</strong>
        <button className={report.configuracion.consultas_habilitadas ? 'token-power-off' : ''} type="button" disabled={busy} onClick={() => void toggleAssistant()}>
          {report.configuracion.consultas_habilitadas ? 'Apagar asistente' : 'Activar asistente'}
        </button>
      </section>
      <section><h2>Configuración general</h2>
        <form onSubmit={event => { event.preventDefault(); void save('', policy) }}>
          <label className="token-toggle"><input type="checkbox" checked={policy.activo} onChange={e => setPolicy({ ...policy, activo: e.target.checked })} />Aplicar los límites ({policy.activo ? 'activados' : 'desactivados'})</label>
          <fieldset disabled={busy}><legend>Cuota predeterminada por usuario</legend>
            <LimitInput label="Tokens por día" value={policy.diario} change={diario => setPolicy({ ...policy, diario })} />
            <LimitInput label="Tokens por mes" value={policy.mensual} change={mensual => setPolicy({ ...policy, mensual })} />
          </fieldset>
          <fieldset disabled={busy}><legend>Tope compartido de toda la aplicación</legend>
            <LimitInput label="Tope diario general" value={policy.global_diario} change={global_diario => setPolicy({ ...policy, global_diario })} />
            <LimitInput label="Tope mensual general" value={policy.global_mensual} change={global_mensual => setPolicy({ ...policy, global_mensual })} />
          </fieldset>
          <button disabled={busy}>Guardar configuración</button>
        </form>
      </section>
      <section><h2>Consumo por usuario</h2>
        <p><strong>Total de hoy: {format(users.reduce((sum, user) => sum + Number(user.consumo_diario), 0))} tokens</strong> · Total del mes: {format(users.reduce((sum, user) => sum + Number(user.consumo_mensual), 0))} tokens</p>
        <div className="token-toolbar"><label>Buscar usuario<input type="search" value={search} onChange={e => setSearch(e.target.value)} /></label>
          <label>Filtrar por local<select value={localFilter} onChange={e => { setLocalFilter(e.target.value); setSelected(null) }}><option value="">Todos los locales</option>{report.locales?.map(local => <option key={local.id} value={local.id}>{local.nombre}</option>)}</select></label>
          <label>Filtrar por rol<select value={roleFilter} onChange={e => { setRoleFilter(e.target.value); setSelected(null) }}><option value="">Todos los roles</option>{report.roles?.map(role => <option key={role.id} value={role.id}>{role.nombre}</option>)}</select></label>
          <button disabled={busy} onClick={() => { setError(''); setReload(n => n + 1) }}>Actualizar consumo</button>
          <button type="button" disabled={busy} onClick={() => { setSearch(''); setLocalFilter(''); setRoleFilter(''); setSelected(null) }}>Limpiar filtros</button>
        </div>
        <div className="token-table"><table><thead><tr><th>Usuario</th><th>Roles</th><th>Locales</th><th>Hoy / límite</th><th>Mes / límite</th><th>Reservas pendientes</th><th>Cuota</th><th>Acción</th></tr></thead>
          <tbody>{users.map(user => <tr key={user.id_usuario}><td>{user.nombre}<small>{user.correo}</small></td>
            <td>{user.roles?.map(role => role.nombre).join(', ') || '—'}</td>
            <td>{user.locales?.map(local => local.nombre).join(', ') || '—'}</td>
            <td>{format(user.consumo_diario)} / {user.diario === null ? 'Sin límite' : format(user.diario)}</td>
            <td>{format(user.consumo_mensual)} / {user.mensual === null ? 'Sin límite' : format(user.mensual)}</td>
            <td>{format(user.pendiente)}</td><td>{user.personalizado ? 'Personalizada' : 'Predeterminada'}</td>
            <td><button aria-label={`Editar cuota de ${user.nombre}`} disabled={busy} onClick={() => setSelected({ ...user })}>Editar</button></td></tr>)}</tbody></table></div>
        {!users.length && <p>No hay usuarios que coincidan con la búsqueda.</p>}
        {selected && <form ref={editor} className="token-editor" onSubmit={e => { e.preventDefault(); void save(`/usuarios/${selected.id_usuario}`, { diario: selected.diario, mensual: selected.mensual }) }}>
          <h3>Cuota de {selected.nombre}</h3>
          <fieldset disabled={busy}><legend>Límites personalizados</legend>
            <LimitInput label="Tokens diarios del usuario" value={selected.diario} change={diario => setSelected({ ...selected, diario })} />
            <LimitInput label="Tokens mensuales del usuario" value={selected.mensual} change={mensual => setSelected({ ...selected, mensual })} />
          </fieldset><button disabled={busy}>Guardar cuota</button>
          {selected.personalizado && <button type="button" disabled={busy} onClick={() => void save(`/usuarios/${selected.id_usuario}`, undefined, true)}>Usar cuota predeterminada</button>}
          <button type="button" disabled={busy} onClick={() => setSelected(null)}>Cancelar</button>
        </form>}
      </section>
    </>}
  </main>
}
