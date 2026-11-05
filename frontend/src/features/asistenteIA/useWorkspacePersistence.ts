import { useCallback, useEffect, useRef, useState } from 'react'
import { blankWorkspace, type WorkspaceState } from './workspaceState'

type Status = 'loading' | 'ready' | 'saving' | 'error' | 'conflict' | 'unavailable'
type Reply = { workspace: WorkspaceState | null; revision: number; mensaje?: string }
const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
// The authoritative trace stays on the server; recovery saves its reference.
function serialize(value: unknown) {
  return JSON.stringify(value, (key, item) => key === 'actividad' && item ? { id: item.id } : item)
}

export function useWorkspacePersistence(token: string | null, value: WorkspaceState | null,
  restore: (value: WorkspaceState) => void) {
  const [status, setStatus] = useState<Status>('loading')
  const [message, setMessage] = useState('')
  const [reloadKey, setReloadKey] = useState(0)
  const latest = useRef(value)
  const restoreRef = useRef(restore)
  latest.current = value; restoreRef.current = restore
  const active = useRef<object | null>(null)
  const phase = useRef<Status>('loading')
  const revision = useRef(0)
  const saved = useRef('null')
  const hydrating = useRef(false)
  const ignored = useRef<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const queue = useRef<Promise<void>>(Promise.resolve())
  const serialized = serialize(value)

  const cancelTimer = useCallback(() => {
    if (timer.current) clearTimeout(timer.current)
    timer.current = null
  }, [])

  useEffect(() => {
    const identity = {}; active.current = identity
    const controller = new AbortController()
    phase.current = 'loading'; setStatus('loading'); setMessage('')
    ignored.current = null; hydrating.current = false; queue.current = Promise.resolve()
    if (!token) { phase.current = 'ready'; setStatus('ready'); return }
    void fetch(`${api}/asistente-ia/workspace`, { method: 'GET', signal: controller.signal,
      headers: { Authorization: `Bearer ${token}` } }).then(async response => {
      const data: Reply = await response.json()
      if (active.current !== identity) return
      if (response.status === 503 && data.mensaje?.includes('20261021_asistente_ia_workspace.sql')) {
        phase.current = 'unavailable'; setStatus('unavailable')
        setMessage('Falta activar el guardado de progreso en PostgreSQL. Puedes continuar sin recuperación al recargar.')
        return
      }
      if (!response.ok) throw new Error(data.mensaje ?? 'No se pudo recuperar el progreso.')
      if (active.current !== identity) return
      revision.current = data.revision; saved.current = serialize(data.workspace)
      if (data.workspace) { hydrating.current = true; restoreRef.current(data.workspace) }
      phase.current = 'ready'; setStatus('ready'); setMessage(data.mensaje ?? '')
    }).catch(error => {
      if (active.current !== identity || controller.signal.aborted) return
      phase.current = 'error'; setStatus('error')
      setMessage(error instanceof Error ? error.message : 'No se pudo recuperar el progreso.')
    })
    return () => { active.current = null; controller.abort(); cancelTimer() }
  }, [token, reloadKey, cancelTimer])

  const enqueue = useCallback((next: WorkspaceState | null, force = false) => {
    cancelTimer()
    const identity = active.current
    const work = queue.current.catch(() => {}).then(async () => {
      if (!token || !identity || active.current !== identity) return
      if (phase.current === 'unavailable') return
      if (phase.current === 'loading' || phase.current === 'error') throw new Error('El progreso todavía no está disponible. Reintenta la recuperación.')
      if (phase.current === 'conflict') throw new Error('Otra ventana actualizó esta tarea. Recarga el progreso antes de continuar.')
      const text = serialize(next)
      if (!force && text === saved.current) return
      phase.current = 'saving'; setStatus('saving')
      try {
        const response = await fetch(`${api}/asistente-ia/workspace`, {
          method: 'PUT', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: serialize({ workspace: next, revision: revision.current }),
        })
        const data: Reply = await response.json()
        if (active.current !== identity) return
        if (!response.ok) {
          if (response.status === 409) { phase.current = 'conflict'; setStatus('conflict') }
          throw new Error(data.mensaje ?? 'No se pudo guardar el progreso.')
        }
        revision.current = data.revision; saved.current = text
        phase.current = 'ready'; setStatus('ready'); setMessage('')
      } catch (error) {
        if (active.current !== identity) return
        if (phase.current !== 'conflict') { phase.current = 'error'; setStatus('error') }
        setMessage(error instanceof Error ? error.message : 'No se pudo guardar el progreso.')
        throw error
      }
    })
    queue.current = work
    return work
  }, [token, cancelTimer])

  useEffect(() => {
    cancelTimer()
    if (phase.current !== 'ready' || ignored.current === serialized) return
    ignored.current = null
    if (hydrating.current) {
      // The application fills defaults and receives fresh option lists during
      // restore, so its canonical JSON can differ from the stored projection.
      saved.current = serialized; hydrating.current = false
      return
    }
    if (serialized === saved.current) return
    timer.current = setTimeout(() => { void enqueue(latest.current).catch(() => {}) }, 500)
    return cancelTimer
  }, [serialized, status, enqueue, cancelTimer])

  const flush = useCallback((next?: WorkspaceState | null) => enqueue(next === undefined ? latest.current : next, true), [enqueue])
  const clear = useCallback(async () => {
    cancelTimer()
    ignored.current = serialize(latest.current)
    await enqueue(null, true)
    hydrating.current = false
  }, [enqueue, cancelTimer])
  const reload = useCallback(() => {
    cancelTimer(); restoreRef.current(blankWorkspace()); setReloadKey(key => key + 1)
  }, [cancelTimer])
  return { status, message, flush, clear, reload }
}
