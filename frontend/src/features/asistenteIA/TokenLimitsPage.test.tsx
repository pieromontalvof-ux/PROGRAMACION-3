import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { useAuth } from '../../context/authState'
import { TokenLimitsPage } from './TokenLimitsPage'

vi.mock('../../context/authState', () => ({ useAuth: vi.fn() }))
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals() })
const report = { dia: '2026-11-24', mes: '2026-11-01', configuracion: { consultas_habilitadas: true, activo: false, diario: null, mensual: null, global_diario: null, global_mensual: null },
  usuarios: [{ id_usuario: 2, nombre: 'Ana Prueba', correo: 'ana@test.invalid', diario: null, mensual: null, personalizado: false, consumo_diario: 100, consumo_mensual: 300, pendiente: 0 }] }
function auth(role: number) {
  vi.mocked(useAuth).mockReturnValue({ token: 'test', perfilActivo: { id_perfil: role } } as ReturnType<typeof useAuth>)
}
it('switches the assistant off separately from token limits', async () => {
  auth(1)
  const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => report })
  vi.stubGlobal('fetch', fetcher)
  render(<MemoryRouter><TokenLimitsPage /></MemoryRouter>)
  fireEvent.click(await screen.findByRole('button', { name: 'Apagar asistente' }))
  await waitFor(() => expect(fetcher).toHaveBeenCalledWith(expect.stringContaining('/limites/estado'), expect.objectContaining({ method: 'PUT', body: JSON.stringify({ habilitado: false }) })))
})
it('does not fetch private consumption for a manager', () => {
  auth(2)
  const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher)
  render(<MemoryRouter><TokenLimitsPage /></MemoryRouter>)
  expect(fetcher).not.toHaveBeenCalled()
})
it('combines user, local and role filters without splitting the shared quota', async () => {
  auth(1)
  const data = { ...report,
    locales: [{ id: 1, nombre: 'Barranco' }, { id: 2, nombre: 'Sheraton' }],
    roles: [{ id: 2, nombre: 'Gerente' }, { id: 3, nombre: 'Supervisor' }],
    usuarios: [
      { ...report.usuarios[0], locales: [{ id: 1, nombre: 'Barranco' }], roles: [{ id: 2, nombre: 'Gerente' }] },
      { ...report.usuarios[0], id_usuario: 3, nombre: 'Otra persona', locales: [{ id: 2, nombre: 'Sheraton' }], roles: [{ id: 3, nombre: 'Supervisor' }] },
    ] }
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => data }))
  render(<MemoryRouter><TokenLimitsPage /></MemoryRouter>)
  await screen.findByText('Ana Prueba')
  fireEvent.change(screen.getByRole('combobox', { name: 'Filtrar por local' }), { target: { value: '1' } })
  expect(screen.queryByText('Otra persona')).toBeNull()
  fireEvent.change(screen.getByRole('combobox', { name: 'Filtrar por rol' }), { target: { value: '3' } })
  expect(screen.queryByText('Ana Prueba')).toBeNull()
  fireEvent.change(screen.getByRole('combobox', { name: 'Filtrar por local' }), { target: { value: '' } })
  expect(screen.getByText('Otra persona')).toBeTruthy()
})
it('saves explicit zero and shows user consumption', async () => {
  auth(1)
  const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => report }); vi.stubGlobal('fetch', fetcher)
  render(<MemoryRouter><TokenLimitsPage /></MemoryRouter>)
  await screen.findByText('Ana Prueba')
  fireEvent.click(screen.getByRole('button', { name: 'Editar cuota de Ana Prueba' }))
  fireEvent.change(screen.getByLabelText('Tokens diarios del usuario'), { target: { value: '0' } })
  fireEvent.click(screen.getByRole('button', { name: 'Guardar cuota' }))
  await waitFor(() => expect(fetcher).toHaveBeenCalledWith(expect.stringContaining('/limites/usuarios/2'), expect.objectContaining({ method: 'PUT', body: JSON.stringify({ diario: 0, mensual: null }) })))
})
it('shows backend errors instead of claiming it saved', async () => {
  auth(1)
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, json: async () => ({ mensaje: 'Acceso denegado' }) }))
  render(<MemoryRouter><TokenLimitsPage /></MemoryRouter>)
  expect((await screen.findByRole('alert')).textContent).toContain('Acceso denegado')
  expect(screen.queryByText('Cargando configuración…')).toBeNull()
})

it('adds numeric database totals instead of concatenating strings and focuses the editor', async () => {
  auth(1)
  const data = { ...report, usuarios: [
    { ...report.usuarios[0], consumo_diario: '1764', consumo_mensual: '1764' },
    { ...report.usuarios[0], id_usuario: 3, nombre: 'Otro usuario', consumo_diario: '0', consumo_mensual: '0' },
  ] }
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => data }))
  render(<MemoryRouter><TokenLimitsPage /></MemoryRouter>)
  await screen.findByText('Ana Prueba')
  expect(screen.getByText(/Total de hoy:/).textContent).toBe(`Total de hoy: ${Number(1764).toLocaleString('es-PE')} tokens`)
  fireEvent.click(screen.getByRole('button', { name: 'Editar cuota de Ana Prueba' }))
  expect(document.activeElement).toBe(screen.getByLabelText('Tokens diarios del usuario'))
})
