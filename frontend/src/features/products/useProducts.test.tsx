import { act, renderHook, waitFor } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { useProducts } from './useProducts'
import { obtenerProductosCatalogo } from '../../services/catalogService'
import type { RespuestaCatalogoProductos } from '../../types/catalog'

vi.mock('../../services/catalogService', () => ({ obtenerProductosCatalogo: vi.fn() }))

it('aborts old requests and ignores late results after changing session', async () => {
  let resolveOld!: (value: RespuestaCatalogoProductos) => void
  const current = { productos: [] } as unknown as RespuestaCatalogoProductos
  vi.mocked(obtenerProductosCatalogo)
    .mockImplementationOnce(() => new Promise(resolve => { resolveOld = resolve }))
    .mockResolvedValueOnce(current)
  const { result, rerender, unmount } = renderHook(({ token }) => useProducts(token), { initialProps: { token: 'old' } })
  await waitFor(() => expect(obtenerProductosCatalogo).toHaveBeenCalledTimes(1))
  const oldSignal = vi.mocked(obtenerProductosCatalogo).mock.calls[0][1]!
  const oldReload = result.current.cargarProductos
  rerender({ token: 'new' })
  await waitFor(() => expect(result.current.datos).toBe(current))
  expect(oldSignal.aborted).toBe(true)
  await act(async () => oldReload(true))
  expect(obtenerProductosCatalogo).toHaveBeenCalledTimes(2)
  await act(async () => resolveOld({ productos: [{ nombre: 'old' }] } as unknown as RespuestaCatalogoProductos))
  expect(result.current.datos).toBe(current)
  const newSignal = vi.mocked(obtenerProductosCatalogo).mock.calls[1][1]!
  unmount()
  expect(newSignal.aborted).toBe(true)
})
