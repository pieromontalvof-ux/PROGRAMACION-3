import { salonApi } from '../../services/salonService'
import type { Carta, Linea, Pedido, Sesion } from './pedidoTypes'

export function obtenerPedido(mesa: string | undefined, signal: AbortSignal) {
  return salonApi<Pedido>(`mesas/${mesa}/pedido`, undefined, 'GET', signal)
}

export function obtenerCartaPedido(signal: AbortSignal) {
  return salonApi<Carta>('carta', undefined, 'GET', signal)
}

export function obtenerSesionPedido(signal: AbortSignal) {
  return salonApi<Sesion>('me', undefined, 'GET', signal)
}

export function cancelarPedido(mesa: string | undefined, version: number) {
  return salonApi(`mesas/${mesa}/pedido`, { version }, 'DELETE')
}

export function eliminarLineasPedido(mesa: string | undefined, autorizacion: string, idsLineas?: number[]) {
  return salonApi<{ pedido: Pedido }>(`mesas/${mesa}/eliminar`, { autorizacion, ids_lineas: idsLineas })
}

export function enviarPedido(mesa: string | undefined, version: number, clave: string, lineas: Linea[]) {
  return salonApi<Pedido>(`mesas/${mesa}/pedido`, {
    version,
    enviar: true,
    envio_clave: clave,
    lineas: lineas.map(linea => linea.id_promocion ? {
      id_promocion: linea.id_promocion,
      cantidad: 1,
      selecciones: linea.selecciones_promocion?.map(seleccion => ({
        id_grupo: seleccion.id_grupo,
        id_presentacion: seleccion.id_presentacion,
        opciones: seleccion.opciones.map(opcion => opcion.id),
      })),
    } : {
      id_presentacion: linea.id_presentacion,
      cantidad: linea.cantidad,
      comentario: linea.comentario,
      opciones: linea.opciones.map(opcion => opcion.id),
      id_barra_libre: linea.id_barra_libre ?? null,
    }),
  }, 'PUT')
}
