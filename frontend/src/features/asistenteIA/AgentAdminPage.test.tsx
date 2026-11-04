import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { AgentAdminPage } from './AgentAdminPage'
import type { CarpetaAgente, DocumentoAgente } from './service'

const mocks = vi.hoisted(() => ({ api: vi.fn(), original: vi.fn(), profile: 1 }))
vi.mock('../../context/AuthContext', () => ({ useAuth: () => ({ token: 'session', perfilActivo: { id_perfil: mocks.profile } }) }))
vi.mock('./service', async original => ({ ...await original<typeof import('./service')>(), bibliotecaAgentes: mocks.api, originalDocumentoAgente: mocks.original }))
const folder: CarpetaAgente = { id: 'compras', nombre: 'Compras y reposición', descripcion: 'Pedidos', revision: 0,
  documentos: [], instrucciones: '', instrucciones_base: 'Reglas de base.', skills: [], limite_contexto: 24000,
  formatos: ['.txt'], uso: 'Referencia del agente.',
  configuracion: { instrucciones: 'Instrucciones protegidas.', skills: [{ nombre: 'Compras', archivo: 'compras/SKILL.md', contenido: 'Skill vigente.' }], accesos: { ordenes_compra: ['consultar', 'crear'] } },
  accesos_disponibles: { ordenes_compra: ['consultar', 'crear'] } }
const inspection = { revision_ia: 'signed-review', informe: { resumen: 'Lista para guardar.', informacion_faltante: [], accesos_necesarios: [], recomendaciones: [], conflictos: [] }, documentos_revisados: 0, caracteres_revisados: 100, revision: 0, puede_guardar: true }
const file: DocumentoAgente = { id: 'doc1', nombre: 'foto.png', caracteres: 0, subido_en: '2026-11-04', mime: 'image/png', original_disponible: true }

function api(data = folder) {
  mocks.api.mockImplementation(async (_token, path, _method) => path === '' ? { agentes: [data] } : data)
}

beforeEach(() => {
  mocks.profile = 1; mocks.api.mockReset(); mocks.original.mockReset(); api()
  Object.defineProperty(URL, 'createObjectURL', { configurable: true, value: vi.fn(() => 'blob:preview') })
  Object.defineProperty(URL, 'revokeObjectURL', { configurable: true, value: vi.fn() })
})
afterEach(() => { cleanup(); vi.restoreAllMocks() })

it('shows one skill editor without duplicate instructions or permission controls', async () => {
  render(<MemoryRouter><AgentAdminPage mode="archivos" /></MemoryRouter>)
  const input = await screen.findByRole('textbox', { name: 'Skill Compras' })
  expect((input as HTMLTextAreaElement).value).toBe('Skill vigente.')
  expect(screen.queryByRole('textbox', { name: 'Instrucciones del agente' })).toBeNull()
  expect(screen.queryByRole('checkbox')).toBeNull()
})

it('requires independent validation before saving edited skills and sends no permissions', async () => {
  render(<MemoryRouter><AgentAdminPage mode="archivos" /></MemoryRouter>)
  fireEvent.change(await screen.findByRole('textbox', { name: 'Skill Compras' }), { target: { value: 'Consultar plazos reales.' } })
  expect(screen.getByRole('button', { name: 'Guardar skill' }).hasAttribute('disabled')).toBe(true)
  const skills = [{ ...folder.configuracion.skills[0], contenido: 'Consultar plazos reales.' }]
  mocks.api.mockImplementation(async (_token, path) => path.endsWith('/validar') ? inspection : path.endsWith('/guardar') ? { ...folder, configuracion: { ...folder.configuracion, skills }, revision: 1 } : folder)
  fireEvent.click(screen.getByRole('button', { name: 'Validar skill' }))
  await screen.findByText('Lista para guardar.')
  expect(mocks.api.mock.calls.some(call => call[1].endsWith('/guardar'))).toBe(false)
  fireEvent.click(screen.getByRole('button', { name: 'Guardar skill' }))
  await screen.findByText('Skill guardada. Los permisos no se modificaron.')
  expect(mocks.api).toHaveBeenLastCalledWith('session', '/compras/skills/guardar', 'POST', { skills, revision: 0, revision_ia: 'signed-review' }, expect.any(AbortSignal))
})

it('keeps saving blocked when validator reports missing permissions and invalidates after edit', async () => {
  render(<MemoryRouter><AgentAdminPage mode="archivos" /></MemoryRouter>)
  await screen.findByRole('textbox', { name: 'Skill Compras' })
  const blocked = { ...inspection, puede_guardar: false, informe: { ...inspection.informe, accesos_necesarios: ['Consultar stock para calcular cobertura.'] } }
  mocks.api.mockImplementation(async (_token, path) => path.endsWith('/validar') ? blocked : folder)
  fireEvent.click(screen.getByRole('button', { name: 'Validar skill' }))
  await screen.findByText('Consultar stock para calcular cobertura.')
  expect(screen.getByRole('button', { name: 'Guardar skill' }).hasAttribute('disabled')).toBe(true)
  const permissionsLink = screen.getByRole('link', { name: /Abrir permisos de agentes/ })
  expect(permissionsLink.getAttribute('target')).toBeNull()
  expect(permissionsLink.getAttribute('href')).toBe('/home/asistente-ia/permisos?agente=compras')
  fireEvent.change(screen.getByRole('textbox', { name: 'Skill Compras' }), { target: { value: 'Usar el especialista de demanda.' } })
  expect(screen.queryByText('Consultar stock para calcular cobertura.')).toBeNull()
})

it('uses selected files to propose a skill without saving or modifying permissions', async () => {
  const withFile = { ...folder, documentos: [file] }; api(withFile)
  render(<MemoryRouter><AgentAdminPage mode="archivos" /></MemoryRouter>)
  await screen.findByText('foto.png')
  mocks.api.mockImplementation(async (_token, path) => path.endsWith('/actualizar') ? { contenido: 'Skill propuesta desde imagen.', resumen: 'Añadido procedimiento.', informacion_faltante: [], archivo_skill: 'compras/SKILL.md', fuentes: ['foto.png'], revision: 0 } : withFile)
  fireEvent.click(screen.getByRole('button', { name: 'Actualizar skill con archivos' }))
  await screen.findByText('Añadido procedimiento.')
  expect((screen.getByRole('textbox', { name: 'Skill Compras' }) as HTMLTextAreaElement).value).toBe('Skill propuesta desde imagen.')
  expect(screen.getByRole('button', { name: 'Guardar skill' }).hasAttribute('disabled')).toBe(true)
  expect(mocks.api.mock.calls.some(call => call[1].endsWith('/accesos') || call[1].endsWith('/guardar'))).toBe(false)
})

it('opens the original image and releases its blob URL when closed', async () => {
  api({ ...folder, documentos: [file] })
  mocks.original.mockResolvedValue(new Blob(['png'], { type: 'image/png' }))
  render(<MemoryRouter><AgentAdminPage mode="archivos" /></MemoryRouter>)
  const open = await screen.findByRole('button', { name: 'Ver archivo' })
  mocks.api.mockResolvedValueOnce({ contenido: '' })
  fireEvent.click(open)
  const image = await screen.findByRole('img', { name: 'foto.png' })
  expect(image.getAttribute('src')).toBe('blob:preview')
  fireEvent.click(screen.getByRole('button', { name: 'Cerrar archivo' }))
  await waitFor(() => expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:preview'))
})

it('keeps permission editing in its separate page and only saves accesses', async () => {
  render(<MemoryRouter><AgentAdminPage mode="permisos" /></MemoryRouter>)
  const checkbox = await screen.findByRole('checkbox', { name: 'Crear Ordenes compra' })
  expect(screen.queryByRole('textbox')).toBeNull()
  fireEvent.click(checkbox)
  mocks.api.mockResolvedValueOnce({ ...folder, configuracion: { ...folder.configuracion, accesos: { ordenes_compra: ['consultar'] } }, revision: 1 })
  fireEvent.click(screen.getByRole('button', { name: 'Guardar permisos' }))
  await screen.findByText('Permisos guardados. Las skills y los archivos no se modificaron.')
  expect(mocks.api).toHaveBeenLastCalledWith('session', '/compras/accesos', 'PUT', { accesos: { ordenes_compra: ['consultar'] }, revision: 0 }, expect.any(AbortSignal))
})

it('adds an available module connection, saves explicitly, and can remove it', async () => {
  api({ ...folder, accesos_disponibles: { ...folder.accesos_disponibles, promociones: ['consultar'] } })
  render(<MemoryRouter><AgentAdminPage mode="permisos" /></MemoryRouter>)
  const selector = await screen.findByLabelText('Conexión disponible')
  expect(screen.queryByRole('checkbox', { name: 'Consultar Promociones' })).toBeNull()
  fireEvent.change(selector, { target: { value: 'promociones' } })
  fireEvent.click(screen.getByRole('button', { name: 'Agregar conexión' }))
  expect((screen.getByRole('checkbox', { name: 'Consultar Promociones' }) as HTMLInputElement).checked).toBe(true)
  expect(mocks.api.mock.calls.some(call => call[2] === 'PUT')).toBe(false)
  fireEvent.click(screen.getByRole('button', { name: 'Quitar conexión Promociones' }))
  expect(screen.queryByRole('checkbox', { name: 'Consultar Promociones' })).toBeNull()
  fireEvent.change(selector, { target: { value: 'promociones' } })
  fireEvent.click(screen.getByRole('button', { name: 'Agregar conexión' }))
  fireEvent.click(screen.getByRole('button', { name: 'Guardar permisos' }))
  await waitFor(() => expect(mocks.api).toHaveBeenCalledWith('session', '/compras/accesos', 'PUT', { accesos: { ...folder.configuracion.accesos, promociones: ['consultar'] }, revision: 0 }, expect.any(AbortSignal)))
})

it('uploads a file and deletes it after confirmation', async () => {
  render(<MemoryRouter><AgentAdminPage mode="archivos" /></MemoryRouter>)
  const input = await screen.findByLabelText('Subir archivo del agente')
  mocks.api.mockResolvedValueOnce({ ...folder, documentos: [file], revision: 1 })
  fireEvent.change(input, { target: { files: [new File(['png'], 'foto.png', { type: 'image/png' })] } })
  await screen.findByText('foto.png')
  vi.spyOn(window, 'confirm').mockReturnValueOnce(true)
  mocks.api.mockResolvedValueOnce({ ...folder, revision: 2 })
  fireEvent.click(screen.getByRole('button', { name: 'Eliminar foto.png' }))
  await waitFor(() => expect(screen.queryByText('foto.png')).toBeNull())
})

it('does not request administration for a Supervisor', () => {
  mocks.profile = 3
  render(<MemoryRouter><AgentAdminPage mode="archivos" /></MemoryRouter>)
  expect(mocks.api).not.toHaveBeenCalled()
})
