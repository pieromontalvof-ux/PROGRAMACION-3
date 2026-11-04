import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { CatalogWorkflow, type WorkflowSnapshot } from './CatalogWorkflow'
import type { FormularioCatalogo } from './service'

const mocks = vi.hoisted(() => ({ request: vi.fn() }))
vi.mock('./service', async importOriginal => ({ ...await importOriginal<typeof import('./service')>(), solicitar: mocks.request }))
const product: FormularioCatalogo = { recurso: 'productos', titulo: 'Crear producto', categorias: [], proveedores: [],
  unidades_medida: [], categorias_proveedor_configurables: true, dependencias_creables: ['categorias_productos'], menajes: [], items: [], tipos: [] }
const category: FormularioCatalogo = { ...product, recurso: 'categorias_productos', titulo: 'Crear categoría de productos', dependencias_creables: [] }
const id = '11111111-1111-4111-8111-111111111111'
let latest: WorkflowSnapshot
const props = () => ({ token: 'session', form: product, disabled: false, onChange: vi.fn(),
  onReview: vi.fn(), onInvalidate: vi.fn(async () => {}), onNestedChange: vi.fn(), onBusy: vi.fn(), onSaved: vi.fn(),
  onSnapshot: (snapshot: WorkflowSnapshot) => { latest = snapshot } })

beforeEach(() => mocks.request.mockReset())
afterEach(cleanup)

describe('recovering nested catalog forms', () => {
  it('captures typed parent and child values and restores an unchecked proposal', async () => {
    mocks.request.mockImplementation(async (_token, route) => route === 'formulario'
      ? { formulario: category } : { respuesta: 'Revisa.', consultas: [], borrador: {
        id_borrador: id, recurso: 'categorias_productos', accion: 'crear', datos: {}, vista: { nombre: 'Nueva' }, id: null, anterior: null } })
    const first = render(<CatalogWorkflow {...props()} />)
    fireEvent.change(screen.getByRole('textbox', { name: 'Nombre' }), { target: { value: 'Atún' } })
    await waitFor(() => expect(latest.frames[0].values.nombre).toBe('Atún'))
    fireEvent.click(screen.getByRole('button', { name: 'No está mi categoría: crear una' }))
    await screen.findByRole('textbox', { name: /Prefijo/ })
    fireEvent.change(screen.getByRole('textbox', { name: 'Nombre' }), { target: { value: 'Nueva' } })
    fireEvent.change(screen.getByRole('textbox', { name: /Prefijo/ }), { target: { value: 'NUE' } })
    fireEvent.click(screen.getByRole('button', { name: 'Revisar propuesta' }))
    await screen.findByRole('checkbox')
    fireEvent.click(screen.getByRole('checkbox'))
    await waitFor(() => expect(latest.proposal?.borrador?.id_borrador).toBe(id))
    expect(latest.frames[0].values.nombre).toBe('Atún')
    expect(latest.frames[1].values.nombre).toBe('Nueva')
    expect(latest).not.toHaveProperty('checked')
    const restored = structuredClone(latest)
    first.unmount()
    render(<CatalogWorkflow {...props()} initialSnapshot={restored} />)
    expect((screen.getByRole('textbox', { name: 'Nombre' }) as HTMLInputElement).value).toBe('Nueva')
    expect((screen.getByRole('checkbox') as HTMLInputElement).checked).toBe(false)
    expect(screen.getByRole('button', { name: 'Realizar y continuar' }).hasAttribute('disabled')).toBe(true)
  })

  it('resumes an already-created requirement without sending another creation', async () => {
    mocks.request.mockResolvedValue({ formulario: { ...product,
      categorias: [{ id_categoria: 3, nombre: 'Nueva', prefijo: 'NUE', activo: true }] } })
    const saved: WorkflowSnapshot = { frames: [
      { form: product, values: { nombre: 'Atún' }, version: 0 },
      { form: category, values: { nombre: 'Nueva', prefijo: 'NUE' }, version: 0 },
    ], proposal: null, dirty: false, saved: { mensaje: 'Categoría creada.', id_categoria: 3 }, draftId: id }
    render(<CatalogWorkflow {...props()} initialSnapshot={saved} />)
    fireEvent.click(screen.getByRole('button', { name: 'Retomar paso anterior' }))
    await screen.findByRole('textbox', { name: 'Nombre' })
    expect((screen.getByRole('textbox', { name: 'Nombre' }) as HTMLInputElement).value).toBe('Atún')
    expect(mocks.request.mock.calls.map(call => call[1])).toEqual(['formulario'])
    await waitFor(() => expect(latest.frames[0].values.categoria).toBe('3'))
  })
})
