import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import { AnswerContent } from './AnswerContent'
import type { Consulta } from './service'

afterEach(cleanup)
const recipes: Consulta = { recurso: 'recetas', desde: 0, total: 3, hay_mas: false,
  registros: ['Alitas BBQ', 'Tequeños', 'Papas fritas'].map((item_carta, index) => ({
    id_receta: index + 1, item_carta, contenido: 1, unidad_presentacion: 'NIU', componentes: [],
  })) }

it('preserves both promotion options and warnings before collapsed supporting recipes', () => {
  const { container } = render(<AnswerContent text={'## Opción 1: Combo para compartir\nDos chilcanos con alitas BBQ.\n\n## Opción 2: Noche de piqueos\nCerveza con tequeños y papas.\n\nAdvertencia: falta validar el margen y las existencias de todos los locales.'}
    queries={[{ recurso: 'presentaciones', desde: 0, total: 2, hay_mas: false, registros: [{ nombre: 'Chilcano' }, { nombre: 'Cerveza' }] }, recipes]} />)
  expect(screen.getByRole('heading', { name: 'Opción 1: Combo para compartir' })).toBeTruthy()
  expect(screen.getByRole('heading', { name: 'Opción 2: Noche de piqueos' })).toBeTruthy()
  expect(screen.getByText(/falta validar el margen/)).toBeTruthy()
  const details = container.querySelector('details')
  expect(details?.open).toBe(false)
  expect(screen.getByRole('heading', { name: 'Alitas BBQ' }).closest('details')).toBe(details)
  expect(screen.getByRole('heading', { name: 'Opción 1: Combo para compartir' }).closest('details')).toBeNull()
  expect(screen.getByRole('heading', { name: 'Opción 2: Noche de piqueos' }).closest('details')).toBeNull()
  fireEvent.click(screen.getByText('Ver recetas consultadas'))
  expect(details?.open).toBe(true)
  expect(screen.getByRole('heading', { name: 'Alitas BBQ' })).toBeTruthy()
  expect(screen.getByRole('heading', { name: 'Tequeños' })).toBeTruthy()
  expect(screen.getByRole('heading', { name: 'Papas fritas' })).toBeTruthy()
})

it('preserves recipe-only narrative and preparation warnings alongside recipe cards', () => {
  render(<AnswerContent text="Advertencia: verifica las alergias antes de preparar las recetas." queries={[recipes]} />)
  expect(screen.getByText(/verifica las alergias/)).toBeTruthy()
  expect(screen.getByRole('heading', { name: 'Alitas BBQ' })).toBeTruthy()
})

it('collapses supporting recipes during a recipe adjustment without repeating cards openly',()=>{
  const {container}=render(<AnswerContent text="Mojito: que cantidad quieres evaluar?" queries={[recipes]} />)
  const details=container.querySelector('details')
  expect(details).toBeTruthy()
  expect(details?.open).toBe(false)
  expect(screen.getByText('Mojito: que cantidad quieres evaluar?').closest('details')).toBeNull()
})
