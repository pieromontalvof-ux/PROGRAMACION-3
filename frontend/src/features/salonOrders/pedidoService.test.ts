import { afterEach, expect, it, vi } from 'vitest'
import { cancelarPedido, enviarPedido, obtenerPedido } from './pedidoService'

afterEach(() => {
  sessionStorage.clear()
  vi.unstubAllGlobals()
})

it('mantiene el contrato de carga, envío y cancelación con la API', async () => {
  const red = vi.fn(async () => Response.json({ lineas: [] }))
  vi.stubGlobal('fetch', red)
  sessionStorage.setItem('salon_token', 'sesion-de-prueba')
  const signal = new AbortController().signal
  const ruta = expect.stringMatching(/\/salon\/mesas\/M1\/pedido$/)

  await obtenerPedido('M1', signal)
  expect(red).toHaveBeenNthCalledWith(1, ruta, expect.objectContaining({ method: 'GET', signal }))

  const base = { nombre: 'Alitas', precio: 0, cantidad: 2, comentario: '', opciones: [], enviada: false }
  await enviarPedido('M1', 7, 'reintento', [
    { ...base, id_presentacion: 3, id_barra_libre: 12 },
    { ...base, id_presentacion: null, id_promocion: 4, selecciones_promocion: [{
      id_grupo: 5, id_presentacion: 3, nombre: 'Alitas', grupo: null, reponible: true,
      opciones: [{ id: 8, nombre: 'BBQ' }],
    }] },
  ])
  expect(red).toHaveBeenNthCalledWith(2, ruta, expect.objectContaining({
    method: 'PUT',
    body: JSON.stringify({
      version: 7, enviar: true, envio_clave: 'reintento',
      lineas: [
        { id_presentacion: 3, cantidad: 2, comentario: '', opciones: [], id_barra_libre: 12 },
        { id_promocion: 4, cantidad: 1, selecciones: [{ id_grupo: 5, id_presentacion: 3, opciones: [8] }] },
      ],
    }),
  }))

  await cancelarPedido('M1', 7)
  expect(red).toHaveBeenNthCalledWith(3, ruta, expect.objectContaining({
    method: 'DELETE', body: JSON.stringify({ version: 7 }),
  }))
})
