import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { Sidebar } from './Sidebar'
import { Topbar } from './Topbar'
import { useAuth } from '../../context/AuthContext'
import type { OpcionMenu } from '../../types/auth'

vi.mock('../../context/AuthContext', () => ({ useAuth: vi.fn() }))
const cambiarPerfil = vi.fn().mockResolvedValue(undefined)
const item = (id: number, nombre: string, url: string | null, parent: number | null = null): OpcionMenu => ({
  id_opcion_menu: id, nombre, url_menu: url, id_padre: parent, codigo: nombre,
  descripcion: '', icono: null, tipo_opcion: url ? 'ENLACE' : 'GRUPO', es_configurable: false, orden: id,
  permisos: { consultar: true, crear: false, editar: false, revisar: false, cerrar: false,
    desactivar: false, reactivar: false, eliminar: false, configurar: false },
})
function setup() {
  vi.mocked(useAuth).mockReturnValue({
    menu: [item(3, 'Catálogo', null), item(4, 'Productos', '/home/productos', 3),
      item(6, 'Proveedores', '/home/proveedores', 3), item(15, 'Stock', '/home/stock')],
    usuario: { nombres: 'Ana', apellido_paterno: 'Prueba' },
    perfilActivo: { id_perfil: 2, nombre: 'Gerente' },
    perfilesDisponibles: [{ id_perfil: 2, nombre: 'Gerente' }, { id_perfil: 3, nombre: 'Supervisor' }],
    puestosDisponibles: [], puestoActivo: null, localesDisponibles: [], localActivo: null,
    cambiandoLocal: false, cambiandoPerfil: false, cambiarPerfil, logout: vi.fn(),
  } as unknown as ReturnType<typeof useAuth>)
}
afterEach(() => { cleanup(); vi.clearAllMocks() })

describe('navigation usability', () => {
  it('groups conversation and administration links under Assistant IA for administrators', () => {
    setup()
    const auth = vi.mocked(useAuth).getMockImplementation()!()
    vi.mocked(useAuth).mockReturnValue({ ...auth, perfilActivo: { id_perfil: 1, nombre: 'Administrador', descripcion: '' } })
    render(<MemoryRouter initialEntries={['/home/asistente-ia/archivos']}><Sidebar abiertoEnMovil={false} cerrarEnMovil={() => {}} /></MemoryRouter>)
    expect(screen.getByRole('button', { name: 'Asistente IA' })).toBeTruthy()
    expect(screen.getByRole('link', { name: 'Conversación' }).getAttribute('href')).toBe('/home/asistente-ia')
    expect(screen.getByRole('link', { name: 'Mapa de agentes' }).getAttribute('href')).toBe('/home/asistente-ia/agentes')
    expect(screen.getByRole('link', { name: 'Archivos de agentes' }).getAttribute('href')).toBe('/home/asistente-ia/archivos')
    expect(screen.getByRole('link', { name: 'Permisos de agentes' }).getAttribute('href')).toBe('/home/asistente-ia/permisos')
  })

  it('keeps agent administration links hidden from operational profiles', () => {
    setup()
    render(<MemoryRouter initialEntries={['/home/asistente-ia']}><Sidebar abiertoEnMovil={false} cerrarEnMovil={() => {}} /></MemoryRouter>)
    expect(screen.getByRole('link', { name: 'Conversación' })).toBeTruthy()
    expect(screen.queryByRole('link', { name: 'Mapa de agentes' })).toBeNull()
    expect(screen.queryByRole('link', { name: 'Archivos de agentes' })).toBeNull()
    expect(screen.queryByRole('link', { name: 'Permisos de agentes' })).toBeNull()
  })

  it('offers a compact role selector and shows the current page', () => {
    setup()
    render(<MemoryRouter initialEntries={['/home/productos']}><Topbar abrirMenu={() => {}} /></MemoryRouter>)
    expect(screen.getByRole('navigation', { name: 'Ubicación actual' }).textContent).toContain('Productos')
    fireEvent.change(screen.getByRole('combobox', { name: 'Rol de trabajo' }), { target: { value: '3' } })
    expect(cambiarPerfil).toHaveBeenCalledWith(3, undefined)
  })
  it('searches nested permitted routes without requiring the parent to match', () => {
    setup()
    render(<MemoryRouter><Sidebar abiertoEnMovil={false} cerrarEnMovil={() => {}} /></MemoryRouter>)
    fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar en el menú' }), { target: { value: 'provee' } })
    expect(screen.getByRole('link', { name: 'Proveedores' })).toBeTruthy()
    expect(screen.queryByRole('link', { name: 'Productos' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar búsqueda del menú' }))
    fireEvent.click(screen.getByRole('button', { name: 'Inventario' }))
    expect(screen.getByRole('link', { name: 'Stock' })).toBeTruthy()
  })

  it('closes the mobile menu with Escape', () => {
    setup()
    const close = vi.fn()
    render(<MemoryRouter><Sidebar abiertoEnMovil cerrarEnMovil={close} /></MemoryRouter>)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(close).toHaveBeenCalledOnce()
  })

  it('offers profile changes in the compact user dropdown', () => {
    setup()
    render(<MemoryRouter><Topbar abrirMenu={() => {}} /></MemoryRouter>)
    fireEvent.click(screen.getByRole('button', { name: /Cuenta de Ana/ }))
    const region = screen.getByRole('region', { name: 'Opciones de usuario' })
    const button = region.querySelector<HTMLButtonElement>('[data-profile="3"]')!
    fireEvent.click(button)
    expect(cambiarPerfil).toHaveBeenCalledWith(3, undefined)
  })
})
