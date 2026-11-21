import { describe, expect, it } from 'vitest'
import { ajustarSalsa, construirReposiciones, grupoCompleto, seleccionarProducto } from './pedidoRules'

const opcion = { id: 1, nombre: 'Salsa BBQ' }
const producto = { id: 4, nombre: 'Alitas', precio: 20, id_categoria: 1, categoria: 'Comida',
  grupo: { maximo: 1, repetir: false, opciones: [opcion] }, reponible: true }
const grupo = { id: 2, cantidad: 1, repetir: false, opciones: [producto] }

describe('reglas de pedidos de salón', () => {
  it('completa el grupo sin añadir elecciones por encima del límite', () => {
    const opciones = seleccionarProducto([], grupo, producto, 'primera')
    expect(grupoCompleto(grupo, opciones)).toBe(true)
    expect(seleccionarProducto(opciones, grupo, producto, 'segunda')).toBe(opciones)
  })

  it('vincula las reposiciones sin precio con la línea original', () => {
    const [seleccion] = seleccionarProducto([], grupo, producto, 'primera')
    const barra = { id_presentacion: null, nombre: 'Barra libre', precio: 50, cantidad: 1,
      comentario: '', opciones: [], enviada: true, ids_lineas: [42] }
    expect(construirReposiciones(barra, seleccion, { 1: 2 }, 99)).toMatchObject({
      lineas: [{ id_presentacion: 4, id_barra_libre: 42, cantidad: 2, precio: 0 }],
    })
    expect(construirReposiciones(barra, seleccion, { 1: 2 }, 100)).toHaveProperty('error')
  })

  it('aplica el máximo de salsas al conjunto de opciones', () => {
    const [seleccion] = seleccionarProducto([], grupo, producto, 'primera')
    const completa = ajustarSalsa(seleccion, opcion, 1)
    expect(ajustarSalsa(completa, { id: 2, nombre: 'Salsa picante' }, 1)).toBe(completa)
    expect(ajustarSalsa(completa, opcion, -1).opciones).toEqual([])
  })
})
