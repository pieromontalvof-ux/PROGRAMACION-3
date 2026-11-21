import { scheduleEffect } from '../../utils/scheduleEffect'
import { useCallback, useEffect, useRef, useState } from 'react'
import { obtenerProductosCatalogo } from '../../services/catalogService'
import type { RespuestaCatalogoProductos } from '../../types/catalog'

/** Carga de catálogo aislada por sesión; las respuestas antiguas no actualizan la vista. */
export function useProducts(token: string | null) {
  const [datos, setDatos] = useState<RespuestaCatalogoProductos | null>(null)
  const [cargando, setCargando] = useState(true)
  const [actualizando, setActualizando] = useState(false)
  const [error, setError] = useState('')
  const active = useRef<AbortController | null>(null)
  const session = useRef<string | null | undefined>(undefined)

  const cargarProductos = useCallback(async (refresh = false) => {
    if (session.current !== token) return
    active.current?.abort()
    const controller = new AbortController()
    active.current = controller
    setError('')
    setCargando(!refresh)
    setActualizando(refresh)
    if (!token) {
      setDatos(null); setError('No existe una sesión válida.')
      setCargando(false); setActualizando(false)
      return
    }
    try {
      const response = await obtenerProductosCatalogo(token, controller.signal)
      if (!controller.signal.aborted) setDatos(response)
    } catch (failure) {
      if (!controller.signal.aborted) setError(failure instanceof Error ? failure.message : 'No fue posible cargar los productos.')
    } finally {
      if (!controller.signal.aborted) { setCargando(false); setActualizando(false) }
    }
  }, [token])

  useEffect(() => scheduleEffect(() => {
    session.current = token
    setDatos(null)
    void cargarProductos()
    return () => { session.current = undefined; active.current?.abort() }

    }), [cargarProductos, token])

  return { datos, cargando, actualizando, setActualizando, error, setError, cargarProductos }
}
