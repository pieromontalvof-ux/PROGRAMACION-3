import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { AssistantWorkspace } from './AssistantWorkspace'
import type { RespuestaAsistente } from './service'
import { blankWorkspace } from './workspaceState'

const mocks = vi.hoisted(() => ({ request: vi.fn(), status: vi.fn() }))
vi.mock('../../context/AuthContext', () => ({
  useAuth: () => ({ token: 'test-session', perfilActivo: { id_perfil: 1, nombre: 'Administrador' }, localActivo: null }),
}))
vi.mock('./service', async importOriginal => ({
  ...await importOriginal<typeof import('./service')>(),
  solicitar: mocks.request,
  obtenerEstadoAsistente: mocks.status,
}))

function proposal(nested: boolean): RespuestaAsistente {
  return {
    respuesta: 'Revisa la propuesta.', agente: nested ? 'presentaciones' : 'recetas', consultas: [],
    continuacion: nested ? 'child-step' : 'root-step',
    ...(nested ? { tarea_pendiente: 'Crear receta de hamburguesa' } : {}),
    borrador: { id_borrador: 'confirmed-draft', recurso: nested ? 'presentaciones' : 'recetas',
      accion: 'crear', id: null, datos: {}, vista: { nombre: 'Hamburguesa' }, anterior: null },
  }
}

async function prepare() {
  render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  await waitFor(() => expect(mocks.status).toHaveBeenCalled())
  fireEvent.change(screen.getByRole('textbox', { name: 'Consulta o corrección' }), { target: { value: 'Crear receta' } })
  await waitFor(() => expect(screen.getByRole('button', { name: 'Enviar' }).hasAttribute('disabled')).toBe(false))
  fireEvent.click(screen.getByRole('button', { name: 'Enviar' }))
  await screen.findByRole('checkbox')
  fireEvent.click(screen.getByRole('checkbox'))
  fireEvent.click(screen.getByRole('button', { name: 'Realizar' }))
}

beforeEach(() => {
  mocks.request.mockReset()
  mocks.status.mockReset().mockResolvedValue({ estado: 'disponible', ia_disponible: true,
    dictado_disponible: false, ejecucion_disponible: true, capacidades: {}, modulos_consultables: [] })
  Element.prototype.scrollIntoView = vi.fn()
  let revision = 0
  vi.stubGlobal('fetch', vi.fn(async (_url, options) => new Response(JSON.stringify({
    workspace: null, revision: options?.method === 'PUT' ? ++revision : revision,
  }))))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('assistant confirmed workflow continuation', () => {
  it('sends a typed query with Enter', async () => {
    mocks.request.mockResolvedValue({ respuesta: 'Consulta recibida.', consultas: [], borrador: null })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const input = await screen.findByRole('textbox', { name: 'Consulta o corrección' })
    await waitFor(() => expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.change(input, { target: { value: 'Consultar stock' } })
    fireEvent.keyDown(input, { key: 'Enter', code: 'Enter' })
    await screen.findByText('Consulta recibida.')
    expect(mocks.request).toHaveBeenCalledTimes(1)
    expect(mocks.request.mock.calls[0][2].instruccion).toBe('Consultar stock')
  })

  it('keeps Shift+Enter for newlines and ignores empty Enter and composition', async () => {
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const input = await screen.findByRole('textbox', { name: 'Consulta o corrección' })
    await waitFor(() => expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.keyDown(input, { key: 'Enter' })
    fireEvent.change(input, { target: { value: 'Primera línea' } })
    expect(fireEvent.keyDown(input, { key: 'Enter', shiftKey: true })).toBe(true)
    fireEvent.keyDown(input, { key: 'Enter', isComposing: true })
    expect(mocks.request).not.toHaveBeenCalled()
  })

  it('sends the signed purchasing flow when selecting an analysis option', async () => {
    const result: RespuestaAsistente = { respuesta: 'Elige un análisis.', consultas: [], borrador: null,
      flujo_compra: 'signed-purchasing-flow', agente: 'eventos',
      opciones: [{ etiqueta: 'Desde la última orden', instruccion: 'Analizar desde la última orden enviada' }] }
    const restored = { ...blankWorkspace(), result, review: result.respuesta, original: result.respuesta }
    vi.mocked(fetch).mockResolvedValue(new Response(JSON.stringify({ workspace: restored, revision: 4 })))
    mocks.request.mockResolvedValue({ respuesta: 'Informe del periodo.', consultas: [], borrador: null,
      flujo_compra: 'next-purchasing-step', agente: 'demanda' })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const option = await screen.findByRole('button', { name: 'Desde la última orden' })
    await waitFor(() => expect(option.hasAttribute('disabled')).toBe(false))
    fireEvent.click(option)
    await screen.findByText('Informe del periodo.')
    expect(mocks.request.mock.calls[0][2]).toMatchObject({
      instruccion: 'Analizar desde la última orden enviada', flujo_compra: 'signed-purchasing-flow' })
  })

  it('recovers a pending draft without restoring approval or automatically executing it', async () => {
    const restored = { ...blankWorkspace(), result: proposal(false), draftId: 'confirmed-draft',
      review: 'Crear receta de hamburguesa', original: 'Crear receta de hamburguesa', lastPrompt: 'Crear receta' }
    vi.mocked(fetch).mockResolvedValue(new Response(JSON.stringify({ workspace: restored, revision: 4 })))
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const checkbox = await screen.findByRole('checkbox')
    expect((checkbox as HTMLInputElement).checked).toBe(false)
    expect(screen.getByRole('button', { name: 'Realizar' }).hasAttribute('disabled')).toBe(true)
    expect(mocks.request).not.toHaveBeenCalled()
  })

  it('recovers a completed prerequisite with only the option to return to its parent', async () => {
    const restored = { ...blankWorkspace(), result: { ...proposal(true), borrador: null },
      confirmed: true, resumeDraft: 'confirmed-draft', draftId: 'confirmed-draft',
      review: 'Presentación creada.', original: 'Presentación creada.' }
    vi.mocked(fetch).mockResolvedValue(new Response(JSON.stringify({ workspace: restored, revision: 4 })))
    mocks.request.mockResolvedValue({ respuesta: 'Continuamos con los ingredientes.', consultas: [],
      borrador: null, agente: 'recetas', continuacion: 'root-step' })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const retry = await screen.findByRole('button', { name: 'Retomar tarea pendiente' })
    await waitFor(() => expect(retry.hasAttribute('disabled')).toBe(false))
    fireEvent.click(retry)
    await screen.findByText('Continuamos con los ingredientes.')
    expect(mocks.request.mock.calls.map(call => call[1])).toEqual(['continuar'])
  })

  it('finishes a root draft without trying to return to a nonexistent parent', async () => {
    mocks.request.mockImplementation(async (_token, route) => {
      if (route === 'preparar') return proposal(false)
      if (route === 'realizar') return { mensaje: 'Receta creada.' }
      throw new Error('No hay un padre pendiente.')
    })
    await prepare()
    await screen.findByText('Realizado')
    expect(mocks.request.mock.calls.filter(call => call[1] === 'continuar')).toHaveLength(0)
    fireEvent.change(screen.getByRole('textbox', { name: 'Consulta o corrección' }), { target: { value: 'Otra consulta' } })
    fireEvent.click(screen.getByRole('button', { name: 'Enviar' }))
    await waitFor(() => expect(mocks.request.mock.calls.filter(call => call[1] === 'preparar')).toHaveLength(2))
    expect(mocks.request.mock.calls.filter(call => call[1] === 'preparar')[1][2].continuacion).toBeUndefined()
  })

  it('returns a confirmed prerequisite to its parent', async () => {
    mocks.request.mockImplementation(async (_token, route) => {
      if (route === 'preparar') return proposal(true)
      if (route === 'realizar') return { mensaje: 'Presentación creada.' }
      return { respuesta: 'Continuamos con los ingredientes.', consultas: [], borrador: null,
        agente: 'recetas', continuacion: 'root-step' }
    })
    await prepare()
    await screen.findByText('Continuamos con los ingredientes.')
    expect(mocks.request).toHaveBeenCalledWith('test-session', 'continuar', {
      continuacion: 'child-step', id_borrador: 'confirmed-draft',
    }, expect.any(AbortSignal))
    expect(mocks.request.mock.calls.filter(call => call[1] === 'realizar')).toHaveLength(1)
  })

  it('retries only the return when resuming fails after a successful creation', async () => {
    let attempts = 0
    mocks.request.mockImplementation(async (_token, route) => {
      if (route === 'preparar') return proposal(true)
      if (route === 'realizar') return { mensaje: 'Presentación creada.' }
      if (++attempts === 1) throw new Error('Conexión interrumpida al retomar.')
      return { respuesta: 'Continuamos con los ingredientes.', consultas: [], borrador: null,
        agente: 'recetas', continuacion: 'root-step' }
    })
    await prepare()
    const retry = await screen.findByRole('button', { name: 'Retomar tarea pendiente' })
    await waitFor(() => expect(retry.hasAttribute('disabled')).toBe(false))
    fireEvent.click(retry)
    await screen.findByText('Continuamos con los ingredientes.')
    expect(mocks.request.mock.calls.filter(call => call[1] === 'realizar')).toHaveLength(1)
    expect(mocks.request.mock.calls.filter(call => call[1] === 'continuar')).toHaveLength(2)
  })
})
