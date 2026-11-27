import { API_BASE_URL } from '../config'
export async function salonApi<Respuesta = any>(
  ruta: string,
  datos?: unknown,
  metodo = 'POST',
  signal?: AbortSignal,
): Promise<Respuesta> {
  const token = sessionStorage.getItem('salon_token')
  if (!token) throw new Error('Inicia sesión en Salón para continuar.')

  const api = API_BASE_URL
  const respuesta = await fetch(`${api}/salon/${ruta}`, {
    method: datos ? metodo : 'GET',
    signal,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: datos ? JSON.stringify(datos) : undefined,
  })
  const contenido = await respuesta.json()
  if (!respuesta.ok) {
    throw new Error(contenido.mensaje ?? contenido.msg ?? 'No se pudo completar la operación')
  }
  return contenido
}
