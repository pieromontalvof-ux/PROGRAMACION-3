import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import { FormattedAnswer } from './FormattedAnswer'

afterEach(cleanup)
const table = (prefix: string, count = 23) => `| Producto | Cantidad |\n| --- | --- |\n${Array.from({ length: count }, (_, i) => `| ${prefix} ${i + 1} | ${i + 1} |`).join('\n')}`

it('starts with five rows and expands to ten, twenty or all loaded rows', () => {
  render(<FormattedAnswer text={table('Producto')} />)
  expect(screen.getAllByRole('row')).toHaveLength(6)
  expect(screen.getByText('Mostrando 5 de 23')).toBeTruthy()
  const selector = screen.getByRole('combobox', { name: 'Mostrar filas' })
  for (const [value, count] of [['10', 10], ['20', 20], ['all', 23]] as const) {
    fireEvent.change(selector, { target: { value } })
    expect(screen.getAllByRole('row')).toHaveLength(count + 1)
    expect(screen.getByText(`Mostrando ${count} de 23`)).toBeTruthy()
  }
})

it('keeps each table independent and resets when the answer changes', () => {
  const { rerender } = render(<FormattedAnswer text={`${table('A')}\n\n${table('B')}`} />)
  fireEvent.change(screen.getAllByRole('combobox')[0], { target: { value: 'all' } })
  expect(within(screen.getAllByRole('table')[0]).getAllByRole('row')).toHaveLength(24)
  expect(within(screen.getAllByRole('table')[1]).getAllByRole('row')).toHaveLength(6)
  rerender(<FormattedAnswer text={table('Nueva')} />)
  expect(screen.getAllByRole('row')).toHaveLength(6)
})

it('preserves escaped pipe cells and treats HTML as text', () => {
  render(<FormattedAnswer text={'| Producto | Cantidad |\n| --- | --- |\n| Sal \\| fina | <img src=x onerror=alert(1)> |'} />)
  expect(screen.getByRole('cell', { name: 'Sal | fina' })).toBeTruthy()
  expect(screen.getByRole('cell', { name: '<img src=x onerror=alert(1)>' })).toBeTruthy()
  expect(screen.queryByRole('img')).toBeNull()
  expect(screen.queryByRole('combobox')).toBeNull()
})

it('keeps compact four column event tables fully visible', () => {
  const rows = Array.from({ length: 8 }, (_, i) => `| ${i} | Congreso ${i} | Congreso | Hotel |`).join('\n')
  render(<FormattedAnswer text={`| Día | Evento publicado | Tipo | Lugar |\n| --- | --- | --- | --- |\n${rows}`} />)
  expect(screen.getAllByRole('row')).toHaveLength(9)
  expect(screen.queryByRole('combobox')).toBeNull()
})
