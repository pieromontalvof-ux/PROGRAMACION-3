import { act, cleanup, renderHook, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useWorkspacePersistence } from './useWorkspacePersistence'
import { blankWorkspace } from './workspaceState'

const answer = (value: object, status = 200) => new Response(JSON.stringify(value), { status })
beforeEach(() => vi.stubGlobal('fetch', vi.fn()))
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('scoped assistant workspace persistence', () => {
  it('keeps existing assistant actions available while the additive migration is pending', async () => {
    vi.mocked(fetch).mockResolvedValue(answer({ mensaje: 'Falta ejecutar 20261021_asistente_ia_workspace.sql para guardar la tarea.' }, 503))
    const { result } = renderHook(() => useWorkspacePersistence('session', blankWorkspace(), vi.fn()))
    await waitFor(() => expect(result.current.status).toBe('unavailable'))
    await act(async () => { await result.current.flush() })
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(result.current.message).toContain('sin recuperación')
  })

  it('restores the authenticated server snapshot without executing a draft', async () => {
    const saved = { ...blankWorkspace(), instruction: 'Crear producto', draftId: 'draft-id' }
    vi.mocked(fetch).mockResolvedValue(answer({ workspace: saved, revision: 3 }))
    const restore = vi.fn()
    const { result } = renderHook(() => useWorkspacePersistence('session', null, restore))
    await waitFor(() => expect(result.current.status).toBe('ready'))
    expect(restore).toHaveBeenCalledWith(saved)
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(vi.mocked(fetch).mock.calls[0][1]?.method).toBe('GET')
  })

  it('serializes a pending save before clearing so a late save cannot resurrect work', async () => {
    let finish!: (r: Response) => void
    vi.mocked(fetch).mockResolvedValueOnce(answer({ workspace: null, revision: 0 }))
    vi.mocked(fetch).mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    vi.mocked(fetch).mockResolvedValueOnce(answer({ workspace: null, revision: 2 }))
    const value = { ...blankWorkspace(), instruction: 'Crear producto' }
    const { result } = renderHook(() => useWorkspacePersistence('session', value, vi.fn()))
    await waitFor(() => expect(result.current.status).toBe('ready'))
    let saving!: Promise<void>
    act(() => { saving = result.current.flush() })
    await waitFor(() => expect(fetch).toHaveBeenCalledTimes(2))
    let clearing!: Promise<void>
    act(() => { clearing = result.current.clear() })
    expect(fetch).toHaveBeenCalledTimes(2)
    await act(async () => { finish(answer({ workspace: value, revision: 1 })); await saving; await clearing })
    const bodies = vi.mocked(fetch).mock.calls.slice(1).map(call => JSON.parse(call[1]!.body as string))
    expect(bodies[1]).toEqual({ workspace: null, revision: 1 })
  })

  it('blocks conflicting saves rather than overwriting another tab', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(answer({ workspace: null, revision: 2 }))
    vi.mocked(fetch).mockResolvedValueOnce(answer({ revision: 5, mensaje: 'Otra ventana actualizó la tarea.' }, 409))
    const { result } = renderHook(() => useWorkspacePersistence('session', blankWorkspace(), vi.fn()))
    await waitFor(() => expect(result.current.status).toBe('ready'))
    await act(async () => { await expect(result.current.flush()).rejects.toThrow('Otra ventana') })
    expect(result.current.status).toBe('conflict')
    expect(fetch).toHaveBeenCalledTimes(2)
  })

  it('ignores a restore that arrives after the scope changes', async () => {
    let finish!: (r: Response) => void
    vi.mocked(fetch).mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    vi.mocked(fetch).mockResolvedValueOnce(answer({ workspace: null, revision: 0 }))
    const restore = vi.fn()
    const { result, rerender } = renderHook(({ token }) => useWorkspacePersistence(token, null, restore),
      { initialProps: { token: 'old-profile' } })
    rerender({ token: 'new-profile' })
    await waitFor(() => expect(result.current.status).toBe('ready'))
    await act(async () => { finish(answer({ workspace: { ...blankWorkspace(), instruction: 'OLD' }, revision: 9 })) })
    expect(restore).not.toHaveBeenCalled()
  })
})
