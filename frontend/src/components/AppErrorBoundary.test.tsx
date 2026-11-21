import { render, screen, fireEvent } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { AppErrorBoundary } from './AppErrorBoundary'

it('contains a rendering failure and can recover without reloading or changing stored session', () => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
  let fail = true
  function Child() { if (fail) throw new Error('private details'); return <p>Recuperado</p> }
  render(<AppErrorBoundary><Child /></AppErrorBoundary>)
  expect(screen.getByRole('alert').textContent).not.toContain('private details')
  expect(screen.getByRole('button', { name: 'Recargar aplicación' })).toBeTruthy()
  fail = false
  fireEvent.click(screen.getByRole('button', { name: 'Volver a intentar' }))
  expect(screen.getByText('Recuperado')).toBeTruthy()
  vi.restoreAllMocks()
})
