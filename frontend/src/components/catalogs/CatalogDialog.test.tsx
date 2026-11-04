import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { CatalogDialog } from './CatalogDialog'

beforeEach(() => {
  for (const method of ['showModal', 'close']) {
    if (!(method in HTMLDialogElement.prototype)) Object.defineProperty(HTMLDialogElement.prototype, method,
      { configurable: true, writable: true, value: () => {} })
  }
  vi.spyOn(HTMLDialogElement.prototype, 'showModal').mockImplementation(function (this: HTMLDialogElement) { this.open = true })
  vi.spyOn(HTMLDialogElement.prototype, 'close').mockImplementation(function (this: HTMLDialogElement) { this.open = false })
})
afterEach(() => { cleanup(); vi.restoreAllMocks() })

describe('shared catalog dialog', () => {
  it('keeps form errors inside the active modal', () => {
    render(<CatalogDialog titulo="Crear" abierto error="Ingresa un nombre" guardar={() => {}} cerrar={() => {}}>Datos</CatalogDialog>)
    expect(within(screen.getByRole('dialog')).getByRole('alert').textContent).toBe('Ingresa un nombre')
  })
  it('uses a labelled modal, focuses its field and returns focus on close', () => {
    const trigger = document.createElement('button'); document.body.append(trigger); trigger.focus()
    const view = render(<CatalogDialog titulo="Crear proveedor" abierto guardar={() => {}} cerrar={() => {}}>
      <label>Nombre<input /></label>
    </CatalogDialog>)
    expect(screen.getByRole('dialog', { name: 'Crear proveedor' })).toBeTruthy()
    expect(document.activeElement).toBe(screen.getByRole('textbox', { name: 'Nombre' }))
    view.unmount()
    expect(document.activeElement).toBe(trigger)
    trigger.remove()
  })

  it('prevents dismissal while saving and permits cancellation afterward', () => {
    const close = vi.fn()
    const view = render(<CatalogDialog titulo="Crear" abierto procesando guardar={() => {}} cerrar={close}>Datos</CatalogDialog>)
    fireEvent(screen.getByRole('dialog'), new Event('cancel', { cancelable: true }))
    expect(close).not.toHaveBeenCalled()
    view.rerender(<CatalogDialog titulo="Crear" abierto guardar={() => {}} cerrar={close}>Datos</CatalogDialog>)
    fireEvent(screen.getByRole('dialog'), new Event('cancel', { cancelable: true }))
    expect(close).toHaveBeenCalledOnce()
  })
})
