import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { StatusFilters } from './StatusFilters'

afterEach(cleanup)

it('changes the requested state and exposes the selected filter', () => {
  const onChange = vi.fn()
  const options = [
    { value: 'todos', label: 'Todos', count: 4 },
    { value: 'activos', label: 'Activos', count: 3 },
    { value: 'inactivos', label: 'Inactivos', count: 1 },
  ]
  const view = render(<StatusFilters value="todos" onChange={onChange} options={options} />)
  expect(screen.getByRole('button', { name: 'Todos 4' }).getAttribute('aria-pressed')).toBe('true')
  fireEvent.click(screen.getByRole('button', { name: 'Inactivos 1' }))
  expect(onChange).toHaveBeenCalledWith('inactivos')
  view.rerender(<StatusFilters value="inactivos" onChange={onChange} options={options} />)
  expect(screen.getByRole('button', { name: 'Inactivos 1' }).getAttribute('aria-pressed')).toBe('true')
  expect(screen.getByRole('button', { name: 'Todos 4' }).getAttribute('aria-pressed')).toBe('false')
})
