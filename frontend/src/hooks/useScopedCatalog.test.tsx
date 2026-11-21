import { act, renderHook, waitFor } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { useScopedCatalog } from './useScopedCatalog'

it('ignores responses and retained reload callbacks from an earlier session', async () => {
  let resolveOld!: (data: string[]) => void
  const fetcher = vi.fn().mockImplementationOnce(() => new Promise(resolve => {resolveOld = resolve}))
    .mockResolvedValueOnce(['new'])
  const {result, rerender, unmount} = renderHook(({token}) => useScopedCatalog<string[]>(token, fetcher, 'Error'), {initialProps: {token: 'old'}})
  await waitFor(() => expect(fetcher).toHaveBeenCalledTimes(1))
  const oldReload = result.current.cargar
  rerender({token: 'new'})
  await waitFor(() => expect(result.current.datos).toEqual(['new']))
  await act(async () => {resolveOld(['old']); await oldReload()})
  expect(result.current.datos).toEqual(['new'])
  expect(fetcher).toHaveBeenCalledTimes(2)
  unmount()
})
