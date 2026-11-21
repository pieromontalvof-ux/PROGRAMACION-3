import { useCallback, useEffect, useRef, useState } from 'react'
import { scheduleEffect } from '../utils/scheduleEffect'

/** Shared catalog loading. A response belongs only to the session that requested it. */
export function useScopedCatalog<T>(token: string | null, fetcher: (token: string) => Promise<T>, fallback: string) {
  const [datos, setDatos] = useState<T | null>(null)
  const [cargando, setCargando] = useState(true)
  const [actualizando, setActualizando] = useState(false)
  const [error, setError] = useState('')
  const scope = useRef<{token: string | null; request: number} | null>(null)
  const cargar = useCallback(async (refresh = false) => {
    const active = scope.current
    if (!active || active.token !== token) return
    const request = ++active.request
    const current = () => scope.current === active && active.request === request
    setError(''); setCargando(!refresh); setActualizando(refresh)
    try {
      if (!token) throw new Error('No existe una sesión válida.')
      const result = await fetcher(token)
      if (current()) setDatos(result)
    } catch (failure) {
      if (current()) setError(failure instanceof Error ? failure.message : fallback)
    } finally {
      if (current()) {setCargando(false); setActualizando(false)}
    }
  }, [token, fetcher, fallback])
  useEffect(() => {
    scope.current = {token, request: 0}
    const cancel = scheduleEffect(() => {setDatos(null); void cargar()})
    return () => {cancel(); scope.current = null}
  }, [token, cargar])
  return {datos, cargando, actualizando, setActualizando, error, setError, cargar}
}
