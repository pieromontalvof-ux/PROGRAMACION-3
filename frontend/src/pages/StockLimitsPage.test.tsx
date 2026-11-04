import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { AuthContext, useAuth } from '../context/AuthContext'
import { StockLimitsPage } from './StockLimitsPage'
import { StoresPage } from './StoresPage'

function auth(profile = 2): ReturnType<typeof useAuth> {
  return {
    usuario: null, token: 'stock-session', perfilActivo: { id_perfil: profile, nombre: 'Perfil', descripcion: '' },
    perfilesDisponibles: [], puestoActivo: null, puestosDisponibles: [],
    localActivo: { id_local: 1, codigo: 'TDA-001', nombre: 'Centro', direccion: null }, localesDisponibles: [],
    cargando: false, cambiandoPerfil: false, cambiandoLocal: false,
    login: async () => {}, logout: () => {}, cambiarPerfil: async () => {},
    cambiarLocal: async () => {}, actualizarSesion: async () => {},
    menu: [{ id_opcion_menu: profile === 2 ? 33 : 2, codigo: 'LIMITES_STOCK', nombre: 'Gestión',
      url_menu: null, descripcion: '', id_padre: null, icono: null, tipo_opcion: 'ENLACE', es_configurable: false, orden: 1,
      permisos: { consultar: true, crear: true, editar: true, revisar: false, cerrar: false, desactivar: true,
        reactivar: true, eliminar: true, configurar: true } }],
  }
}

const productos = [1, 2].map(id => ({ id_producto: id, codigo: `P-${id}`, nombre: `Producto ${id}`,
  categoria: 'Alimentos', unidad: 'KGM', stock_minimo: 1, stock_maximo: 2, activo: true }))
let writes: { url: string; options: RequestInit }[]
let save: (url: string, options: RequestInit) => Promise<Response>
const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status })

beforeEach(() => {
  writes = []
  save = async () => response({ mensaje: 'Límites guardados.' })
  vi.stubGlobal('fetch', async (url: string, options: RequestInit = {}) => {
    if (options.method === 'PUT') { writes.push({ url, options }); return save(url, options) }
    if (url.endsWith('/locales')) return response({ locales: [{ id_local: 1, codigo: 'TDA-001', nombre: 'Centro', direccion: 'Lima', estado_registro: 1 }] })
    return response({ id_local: 1, productos })
  })
  // jsdom has no top layer. Emulate only native open/focus; our component must
  // still invoke showModal and implement cancellation/return-to-trigger itself.
  for (const method of ['showModal', 'close']) {
    if (!(method in HTMLDialogElement.prototype)) Object.defineProperty(HTMLDialogElement.prototype, method,
      { configurable: true, writable: true, value: () => {} })
  }
  vi.spyOn(HTMLDialogElement.prototype, 'showModal').mockImplementation(function (this: HTMLDialogElement) {
    this.open = true
    this.querySelector<HTMLElement>('[autofocus], input, button')?.focus()
  })
  vi.spyOn(HTMLDialogElement.prototype, 'close').mockImplementation(function (this: HTMLDialogElement) {
    this.open = false
  })
})

afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals() })

async function openStock(index = 0) {
  render(<AuthContext.Provider value={auth()}><MemoryRouter><StockLimitsPage /></MemoryRouter></AuthContext.Provider>)
  const triggers = await screen.findAllByRole('button', { name: 'Configurar' })
  triggers[index].focus()
  fireEvent.click(triggers[index])
  return triggers[index]
}

describe('Stock limit dialog', () => {
  it('opens a named native modal with initial field focus and returns to the exact trigger on Escape', async () => {
    const trigger = await openStock(1)
    const dialog = screen.getByRole('dialog', { name: 'Configurar límites' }) as HTMLDialogElement
    expect(dialog.tagName).toBe('DIALOG')
    expect(dialog.open).toBe(true)
    expect(document.activeElement).toBe(within(dialog).getByRole('spinbutton', { name: 'Stock mínimo' }))
    fireEvent(dialog, new Event('cancel', { cancelable: true }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(document.activeElement).toBe(trigger)
  })

  it('returns focus to the trigger when cancelled with its button', async () => {
    const trigger = await openStock()
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(document.activeElement).toBe(trigger)
  })

  it.each([['1', '1'], ['-1', '2'], ['1.0001', '2'], ['1', '2.0001'], ['0', '1000000000'], ['', '2']])(
    'connects invalid bounds %s/%s to their inline error without saving', async (min, max) => {
      await openStock()
      const dialog = screen.getByRole('dialog')
      const minimum = within(dialog).getByRole('spinbutton', { name: 'Stock mínimo' })
      const maximum = within(dialog).getByRole('spinbutton', { name: 'Stock máximo' })
      fireEvent.change(minimum, { target: { value: min } })
      fireEvent.change(maximum, { target: { value: max } })
      fireEvent.submit(dialog.querySelector('form')!)
      const alert = within(dialog).getByRole('alert')
      expect(alert.id).not.toBe('')
      for (const field of [minimum, maximum]) {
        expect(field.getAttribute('aria-invalid')).toBe('true')
        expect(field.getAttribute('aria-describedby')).toBe(alert.id)
      }
      expect(screen.getAllByRole('alert')).toHaveLength(1)
      expect(writes).toHaveLength(0)
    },
  )

  it('keeps the dialog open while saving then returns focus after a successful save', async () => {
    let finish!: (result: Response) => void
    save = () => new Promise(resolve => { finish = resolve })
    const trigger = await openStock(1)
    const dialog = screen.getByRole('dialog')
    fireEvent.change(within(dialog).getByRole('spinbutton', { name: 'Stock máximo' }), { target: { value: '2.001' } })
    fireEvent.submit(dialog.querySelector('form')!)
    const cancel = new Event('cancel', { cancelable: true })
    fireEvent(dialog, cancel)
    expect(cancel.defaultPrevented).toBe(true)
    expect((dialog as HTMLDialogElement).open).toBe(true)
    expect((screen.getByRole('button', { name: 'Cancelar' }) as HTMLButtonElement).disabled).toBe(true)
    expect(writes).toHaveLength(1)
    expect(writes[0].url).toMatch(/\/limites-stock\/2$/)
    expect(JSON.parse(writes[0].options.body as string)).toEqual({ stock_minimo: 1, stock_maximo: 2.001 })
    await act(async () => { finish(response({ mensaje: 'Límites guardados.' })) })
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(screen.getByRole('status').textContent).toBe('Límites guardados.')
    expect(document.activeElement).toBe(trigger)
  })
})

describe('Store dialog names', () => {
  it('names create, edit and confirmation dialogs using their visible headings', async () => {
    render(<AuthContext.Provider value={auth(1)}><MemoryRouter><StoresPage /></MemoryRouter></AuthContext.Provider>)
    await screen.findByRole('button', { name: 'Editar Centro' })
    fireEvent.click(screen.getByRole('button', { name: 'Nueva tienda' }))
    expect(screen.getByRole('dialog', { name: 'Nueva tienda' })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar' }))
    fireEvent.click(screen.getByRole('button', { name: 'Editar Centro' }))
    expect(screen.getByRole('dialog', { name: 'Editar tienda' })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar' }))
    fireEvent.click(screen.getByRole('switch', { name: 'Desactivar Centro' }))
    expect(screen.getByRole('dialog', { name: 'Desactivar tienda' })).toBeTruthy()
  })
})
