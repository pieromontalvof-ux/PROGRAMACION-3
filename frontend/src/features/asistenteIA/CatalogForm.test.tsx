import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { CatalogForm, valuesFromProposal } from './CatalogForm'
import type { FormularioCatalogo } from './service'
afterEach(cleanup)

it('preserves an inactive proposal and equivalent volume when editing the optional sheet', () => {
  const data = { id_item_carta: null, nombre_item: 'Limonada especial', tipo_item: 'PREPARADO', id_categoria_carta: 1,
    id_menaje: 2, contenido: 500, unidad: 'MLT', precio: 15, activo: false }
  const form: FormularioCatalogo = { recurso: 'presentaciones', titulo: 'Revisar presentación', categorias: [{ id_categoria: 1, nombre: 'Bebidas', prefijo: 'BE', activo: true }],
    proveedores: [], unidades_medida: [{ codigo: 'LTR', nombre: 'Litro', simbolo: 'L' }], categorias_proveedor_configurables: false,
    dependencias_creables: [], menajes: [{ id_menaje: 2, nombre: 'Vaso', activo: true }], items: [], tipos: ['PREPARADO'] }
  const review = vi.fn()
  const { container } = render(<CatalogForm form={form} disabled={false} onChange={vi.fn()} onReview={review} onDependency={vi.fn()} initialValues={valuesFromProposal(data)} />)
  expect((screen.getByRole('checkbox', { name: 'Presentación activa' }) as HTMLInputElement).checked).toBe(false)
  expect((screen.getByLabelText('Unidad') as HTMLSelectElement).value).toBe('LTR')
  expect((screen.getByLabelText('Contenido (L)') as HTMLInputElement).value).toBe('0.5')
  fireEvent.submit(container.querySelector('form')!)
  expect(review).toHaveBeenCalledWith({ ...data, unidad: 'LTR', contenido: 0.5 })
})
