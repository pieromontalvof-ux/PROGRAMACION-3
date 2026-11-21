import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { CatalogForm } from './CatalogForm'
import { valuesFromProposal } from './catalogFormValues'
import type { FormularioCatalogo } from './service'
import { ReviewDetails } from './ReviewDetails'
afterEach(cleanup)

it('distinguishes portioned from prepared and preserves each selected code', () => {
  const data = { id_item_carta: null, nombre_item: 'Limonada', tipo_item: 'PORCIONADO', id_categoria_carta: 1,
    id_menaje: 2, contenido: 0.5, unidad: 'LTR', precio: 15, activo: true }
  const form: FormularioCatalogo = { recurso: 'presentaciones', titulo: 'Revisar', categorias: [{ id_categoria: 1, nombre: 'Bebidas', prefijo: 'BE', activo: true }], proveedores: [], unidades_medida: [{ codigo: 'LTR', nombre: 'Litro', simbolo: 'L' }], categorias_proveedor_configurables: false, dependencias_creables: [], menajes: [{ id_menaje: 2, nombre: 'Chop', activo: true }], items: [], tipos: ['DIRECTO','PREPARADO','PORCIONADO'] }
  const review = vi.fn()
  const { container } = render(<CatalogForm form={form} disabled={false} onChange={vi.fn()} onReview={review} onDependency={vi.fn()} initialValues={valuesFromProposal(data)} />)
  const select = screen.getByLabelText('Tipo de artículo') as HTMLSelectElement
  expect(select.selectedOptions[0].text).toBe('Porcionado')
  expect(screen.getAllByRole('option', { name: 'Preparado' })).toHaveLength(1)
  fireEvent.submit(container.querySelector('form')!)
  expect(review).toHaveBeenLastCalledWith(data)
  fireEvent.change(select, { target: { value: 'PREPARADO' } })
  fireEvent.submit(container.querySelector('form')!)
  expect(review).toHaveBeenLastCalledWith({ ...data, tipo_item: 'PREPARADO' })
})

it('uses clear labels for a new article and its type in the summary', () => {
  render(<ReviewDetails resource="presentaciones" value={{ id_item_carta: null, tipo_item: 'PORCIONADO' }} />)
  expect(screen.getByText('Crear artículo nuevo')).toBeTruthy()
  expect(screen.getByText('Porcionado')).toBeTruthy()
})

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
