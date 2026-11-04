import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import { FormattedAnswer } from './FormattedAnswer'
afterEach(cleanup)

it('renders event sources as clickable links and blocks unsafe URLs', () => {
  render(<FormattedAnswer text={'[Más información](https://eventos.example.org/agenda) y [malicioso](javascript:alert)'} />)
  expect(screen.getByRole('link', { name: 'Más información' }).getAttribute('href')).toBe('https://eventos.example.org/agenda')
  expect(screen.queryByRole('link', { name: 'malicioso' })).toBeNull()
})
