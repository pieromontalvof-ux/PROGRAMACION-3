import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { StoresPage } from './StoresPage'
import { useAuth } from '../context/authState'

vi.mock('../context/authState', () => ({ useAuth: vi.fn() }))
const stores = [
  { id_local: 1, codigo: 'TDA-001', nombre: 'Centro', direccion: 'Calle Uno', estado_registro: 1 },
  { id_local: 2, codigo: 'TDA-002', nombre: 'Norte', direccion: 'Calle Dos', estado_registro: 0 },
]
beforeEach(() => {
  vi.mocked(useAuth).mockReturnValue({ token: 'test', perfilActivo: { id_perfil: 1 },
    menu: [{ id_opcion_menu: 2, permisos: { consultar: true, crear: true, editar: true, eliminar: true } }],
    actualizarSesion: vi.fn(),
  } as unknown as ReturnType<typeof useAuth>)
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ locales: stores }))))
  for (const method of ['showModal', 'close']) {
    if (!(method in HTMLDialogElement.prototype)) Object.defineProperty(HTMLDialogElement.prototype, method,
      { configurable: true, writable: true, value: () => {} })
  }
  vi.spyOn(HTMLDialogElement.prototype, 'showModal').mockImplementation(function (this: HTMLDialogElement) { this.open = true })
  vi.spyOn(HTMLDialogElement.prototype, 'close').mockImplementation(function (this: HTMLDialogElement) { this.open = false })
})
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals() })

describe('store reference layout', () => {
  it('filters real store rows by status and search', async () => {
    render(<MemoryRouter><StoresPage /></MemoryRouter>)
    await screen.findByText('Centro')
    fireEvent.click(screen.getByRole('button', { name: /^Inactivas/ }))
    expect(screen.queryByText('Centro')).toBeNull()
    expect(screen.getByText('Norte')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /^Todas/ }))
    fireEvent.change(screen.getByRole('textbox', { name: 'Buscar tiendas' }), { target: { value: 'Calle Uno' } })
    expect(screen.getByText('Centro')).toBeTruthy()
    expect(screen.queryByText('Norte')).toBeNull()
  })

  it('asks for confirmation before changing an active store', async () => {
    render(<MemoryRouter><StoresPage /></MemoryRouter>)
    await screen.findByText('Centro')
    fireEvent.click(screen.getByRole('switch', { name: 'Desactivar Centro' }))
    await waitFor(() => expect(screen.getByRole('dialog', { name: 'Desactivar tienda' })).toBeTruthy())
    expect(vi.mocked(fetch).mock.calls).toHaveLength(1)
    expect(screen.getByRole('switch', { name: 'Desactivar Centro' }).getAttribute('aria-checked')).toBe('true')
  })
})
