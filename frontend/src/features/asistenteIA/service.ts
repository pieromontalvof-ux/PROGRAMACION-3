export interface EstadoAsistente {
  estado: 'disponible' | 'sin_configurar'
  ia_disponible: boolean
  dictado_disponible: boolean
  ejecucion_disponible: boolean
  capacidades?: Record<string, string[]>
  modulos_consultables: { nombre: string; ruta: string }[]
}
export interface Borrador {
  id_borrador: string
  recurso: string
  accion: string
  id: number | null
  datos: Record<string, unknown>
  vista: Record<string, unknown>
  anterior: Record<string, unknown> | null
}
export interface Consulta {
  recurso: string; total: number; desde: number; hay_mas: boolean
  registros: Record<string, unknown>[]
  contexto?: Record<string, unknown>
}
export interface RespuestaAsistente {
  respuesta: string; borrador: Borrador | null; consultas: Consulta[]
}
export async function solicitar<T>(token: string, ruta: string, body: object | FormData, signal?: AbortSignal): Promise<T> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const form = body instanceof FormData
  const r = await fetch(`${api}/asistente-ia/${ruta}`, {
    method: 'POST', signal,
    headers: { Authorization: `Bearer ${token}`, ...(!form ? { 'Content-Type': 'application/json' } : {}) },
    body: form ? body : JSON.stringify(body),
  })
  let data
  try { data = await r.json() } catch { throw new Error('El servidor no respondió correctamente. Si confirmaste un cambio, revisa el módulo antes de repetirlo.') }
  if (!r.ok) throw new Error(data.mensaje ?? data.msg ?? 'No se pudo completar la solicitud.')
  return data
}
export async function obtenerEstadoAsistente(token: string, signal: AbortSignal): Promise<EstadoAsistente> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const respuesta = await fetch(`${api}/asistente-ia/estado`, { headers: { Authorization: `Bearer ${token}` }, signal })
  const datos = await respuesta.json()
  if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo verificar el acceso')
  return datos
}
