import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { TablewarePage } from './TablewarePage'
import { administrarMenaje, obtenerMenajes } from '../services/cartaService'

vi.mock('../context/AuthContext', () => ({ useAuth: () => ({ token: 'session', perfilActivo: { id_perfil: 1 }, menu: [{ id_opcion_menu: 10, permisos: { crear: true, editar: true } }] }) }))
vi.mock('../services/cartaService', () => ({ obtenerMenajes: vi.fn(), administrarMenaje: vi.fn() }))
beforeEach(() => {
  Object.defineProperty(HTMLDialogElement.prototype, 'showModal', { configurable: true, value() { this.open = true } })
  Object.defineProperty(HTMLDialogElement.prototype, 'close', { configurable: true, value() { this.open = false } })
  vi.mocked(obtenerMenajes).mockResolvedValue({ menajes: [{ id_menaje: 1, nombre: 'Vaso 12 oz', activo: true, total_presentaciones: 0, presentaciones_activas: 0, presentaciones_inactivas: 0, total_items: 0, items: [] }], resumen: { total_menajes: 1, menajes_activos: 1, menajes_inactivos: 0, total_presentaciones: 0 } })
  vi.mocked(administrarMenaje).mockResolvedValue({ mensaje: 'Guardado' })
})
afterEach(() => { cleanup(); vi.clearAllMocks() })
it('preserves legacy capacity when only the name changes', async () => {
  const response = await obtenerMenajes('session')
  vi.mocked(obtenerMenajes).mockResolvedValue({ ...response, menajes: response.menajes.map(item => ({ ...item, capacidad: 12, unidad_capacidad: 'FLOZ_UK', origen_medidas: 'DEMO' })) })
  render(<TablewarePage />)
  fireEvent.click(await screen.findByRole('button', { name: 'Editar' }))
  fireEvent.change(screen.getByLabelText('Nombre del menaje'), { target: { value: 'Otro nombre' } })
  fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))
  await waitFor(() => expect(administrarMenaje).toHaveBeenCalledWith('session', 'editar', 'Otro nombre', 1, expect.objectContaining({ capacidad: 12, unidad_capacidad: 'FLOZ_UK' })))
})
it('does not infer measurements from names and submits empty measurements as null', async () => {
  render(<TablewarePage />)
  await screen.findByText('Sin registrar')
  fireEvent.click(screen.getByRole('button', { name: 'Editar' }))
  expect((screen.getByLabelText('Capacidad (opcional)') as HTMLInputElement).value).toBe('')
  fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))
  await waitFor(() => expect(administrarMenaje).toHaveBeenCalledWith('session', 'editar', 'Vaso 12 oz', 1, { capacidad: null, unidad_capacidad: null, diametro_cm: null, altura_cm: null, largo_cm: null, ancho_cm: null }))
})
it('offers a single fluid ounce unit and rectangular dimensions', async () => {
  render(<TablewarePage />)
  fireEvent.click(await screen.findByRole('button', { name: 'Editar' }))
  fireEvent.change(screen.getByLabelText('Capacidad (opcional)'), { target: { value: '12' } })
  fireEvent.change(screen.getByLabelText('Unidad de capacidad'), { target: { value: 'FLOZ_US' } })
  expect(screen.getByText(/354,88 mL/)).toBeTruthy()
  expect(screen.queryByRole('option', { name: /imperiales/ })).toBeNull()
  fireEvent.change(screen.getByLabelText('Largo en cm (opcional)'), { target: { value: '40' } })
  fireEvent.change(screen.getByLabelText('Ancho en cm (opcional)'), { target: { value: '30' } })
  fireEvent.change(screen.getByLabelText('Diámetro en cm (opcional)'), { target: { value: '8.5' } })
  fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))
  await waitFor(() => expect(administrarMenaje).toHaveBeenCalledWith('session', 'editar', 'Vaso 12 oz', 1, { capacidad: 12, unidad_capacidad: 'FLOZ_US', diametro_cm: 8.5, altura_cm: null, largo_cm: 40, ancho_cm: 30 }))
})

it('rejects zero measurements without sending a write', async () => {
  render(<TablewarePage />)
  fireEvent.click(await screen.findByRole('button', { name: 'Editar' }))
  fireEvent.change(screen.getByLabelText('Capacidad (opcional)'), { target: { value: '0' } })
  fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))
  expect(await screen.findByRole('alert')).toHaveProperty('textContent', 'Las medidas deben ser números mayores que cero o quedar vacías.')
  expect(administrarMenaje).not.toHaveBeenCalled()
})
