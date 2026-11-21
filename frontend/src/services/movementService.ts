import type {
  DatosRegistrarMovimiento,
  GuiaMovimiento,
  RespuestaFormularioMovimiento,
  RespuestaRegistrarMovimiento,
} from '../types/movement'


const API_URL =
  import.meta.env.VITE_API_URL ??
  'http://127.0.0.1:5000/api'

interface RespuestaError {
  mensaje?: string
  msg?: string
}

async function procesarRespuesta<T>(
  respuesta: Response,
  mensajePredeterminado = 'No se pudo completar la operación.',
): Promise<T> {
  let datos: T | RespuestaError

  try {
    datos = (await respuesta.json()) as
      | T
      | RespuestaError
  } catch {
    throw new Error(
      'El servidor devolvió una respuesta no válida.',
    )
  }

  if (!respuesta.ok) {
    const error = datos as RespuestaError

    throw new Error(
      error.mensaje ??
        error.msg ??
        mensajePredeterminado,
    )
  }

  return datos as T
}

export async function obtenerSeguimientoMovimientos(token: string) {
  const respuesta = await fetch(`${API_URL}/movimientos/seguimiento`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  return procesarRespuesta<{ movimientos: GuiaMovimiento[] }>(respuesta, 'No se pudo cargar el seguimiento')
}

export async function recibirMovimiento(
  token: string,
  id: number,
  guiaProveedor: string,
  detalles: { id_producto: number; cantidad: number }[],
) {
  const respuesta = await fetch(`${API_URL}/movimientos/${id}/recibir`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ guia_proveedor: guiaProveedor, detalles }),
  })
  return procesarRespuesta<{ mensaje: string }>(respuesta, 'No se pudo recibir')
}

export async function obtenerFormularioMovimiento(
  token: string,
): Promise<RespuestaFormularioMovimiento> {
  const respuesta = await fetch(
    `${API_URL}/movimientos/formulario`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaFormularioMovimiento>(
    respuesta,
  )
}

export async function registrarMovimiento(
  token: string,
  datos: DatosRegistrarMovimiento,
): Promise<RespuestaRegistrarMovimiento> {
  const respuesta = await fetch(
    `${API_URL}/movimientos`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(datos),
    },
  )

  return procesarRespuesta<RespuestaRegistrarMovimiento>(
    respuesta,
  )
}
