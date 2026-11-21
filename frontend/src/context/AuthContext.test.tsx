import { StrictMode, useLayoutEffect } from 'react'
import { act, cleanup, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { AuthProvider } from './AuthContext'
import { useAuth } from './authState'
import type { RespuestaSesionActiva } from '../types/auth'

type Auth = ReturnType<typeof useAuth>
interface Request {
  url: string
  options?: RequestInit
  resolve: (response: Response) => void
  reject: (reason: Error) => void
}

let auth: Auth
let requests: Request[]

function session(token = 'original', profile = 1, local = 1): RespuestaSesionActiva {
  const perfil = { id_perfil: profile, nombre: `Perfil ${profile}`, descripcion: '' }
  const tienda = { id_local: local, codigo: `L${local}`, nombre: `Local ${local}`, direccion: null }
  return {
    requiere_seleccion_perfil: false,
    token,
    usuario: {
      id_usuario: 1, dni: '12345678', nombres: token, apellido_paterno: 'Prueba',
      apellido_materno: null, correo: 'test@example.com', id_puesto_laboral: null,
      puesto_laboral: null, id_perfil: profile, perfil: perfil.nombre,
    },
    perfil_activo: perfil, perfiles_disponibles: [perfil],
    puesto_activo: null, puestos_disponibles: [],
    local_activo: tienda, locales_disponibles: [tienda], menu: [],
  }
}

function Consumer() {
  const current = useAuth()
  useLayoutEffect(() => { auth = current })
  return <output>{JSON.stringify({ token: current.token, profile: current.perfilActivo?.id_perfil,
    local: current.localActivo?.id_local, loading: current.cargando,
    profilePending: current.cambiandoPerfil, localPending: current.cambiandoLocal })}</output>
}

function mount(strict = false) {
  const tree = <AuthProvider><Consumer /></AuthProvider>
  return render(strict ? <StrictMode>{tree}</StrictMode> : tree)
}

// Attach the rejection handler immediately so deliberately late failures stay handled.
function start(action: () => Promise<void>) {
  let result!: Promise<unknown>
  act(() => { result = action().catch((error: unknown) => error) })
  return result
}

async function respond(request: Request, value: RespuestaSesionActiva | Error) {
  await act(async () => {
    if (value instanceof Error) request.reject(value)
    else request.resolve(new Response(JSON.stringify(value), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    }))
  })
}

async function login(value = session()) {
  const operation = start(() => auth.login('test@example.com', 'secret'))
  await respond(requests.at(-1)!, value)
  await operation
}

function expectSession(token: string | null, profile?: number, local?: number) {
  const displayed = JSON.parse(screen.getByRole('status').textContent!)
  expect(displayed.token).toBe(token)
  expect(sessionStorage.getItem('token')).toBe(token)
  if (profile !== undefined) {
    expect(displayed.profile).toBe(profile)
    expect(JSON.parse(sessionStorage.getItem('perfil_activo')!).id_perfil).toBe(profile)
  }
  if (local !== undefined) {
    expect(displayed.local).toBe(local)
    expect(JSON.parse(sessionStorage.getItem('local_activo')!).id_local).toBe(local)
  }
  if (token === null) {
    expect(sessionStorage.getItem('usuario')).toBeNull()
    expect(sessionStorage.getItem('local_activo')).toBeNull()
  }
}

beforeEach(() => {
  sessionStorage.clear()
  requests = []
  vi.stubGlobal('fetch', (url: string, options?: RequestInit) => new Promise<Response>((resolve, reject) => {
    requests.push({ url, options, resolve, reject })
  }))
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('AuthProvider session ownership', () => {
  it('allows a current session refresh to update the rendered and persisted session', async () => {
    mount()
    await login()
    const operation = start(() => auth.actualizarSesion())
    const request = requests.at(-1)!
    expect(request.options?.headers).toEqual({ Authorization: 'Bearer original' })
    await respond(request, session('original', 1, 2))
    await operation
    expectSession('original', 1, 2)
  })

  it('does not restore a session when an in-flight refresh finishes after logout', async () => {
    mount()
    await login()
    const operation = start(() => auth.actualizarSesion())
    const request = requests.at(-1)!
    act(() => auth.logout())
    await respond(request, session())
    await operation
    expectSession(null)
  })

  it('does not send an obsolete token when a saved render refresh callback runs after logout', async () => {
    mount()
    await login()
    const savedRefresh = auth.actualizarSesion
    act(() => auth.logout())
    const count = requests.length
    const operation = start(savedRefresh)
    expect(requests).toHaveLength(count)
    await operation
    expectSession(null)
  })

  it('does not let an old refresh overwrite a later login, even with a reused token', async () => {
    mount()
    await login()
    const operation = start(() => auth.actualizarSesion())
    const request = requests.at(-1)!
    act(() => auth.logout())
    await login(session('original', 2, 2))
    await respond(request, session())
    await operation
    expectSession('original', 2, 2)
  })

  it.each(['profile', 'local'] as const)('invalidates refreshes as soon as a %s transition starts', async (kind) => {
    mount()
    await login()
    const refresh = start(() => auth.actualizarSesion())
    const request = requests.at(-1)!
    const transition = start(() => kind === 'profile' ? auth.cambiarPerfil(2) : auth.cambiarLocal(2))
    const change = requests.at(-1)!
    await respond(request, session('original', 9, 9))
    await refresh
    expectSession('original', 1, 1)
    expect(kind === 'profile' ? auth.cambiandoPerfil : auth.cambiandoLocal).toBe(true)
    await respond(change, session('changed', 2, 2))
    await transition
    expectSession('changed', 2, 2)
  })

  it.each(['profile', 'local'] as const)('does not refresh the old scope while a %s transition is pending', async (kind) => {
    mount()
    await login()
    const transition = start(() => kind === 'profile' ? auth.cambiarPerfil(2) : auth.cambiarLocal(2))
    const change = requests.at(-1)!
    const count = requests.length
    const refresh = start(() => auth.actualizarSesion())
    expect(requests).toHaveLength(count)
    await refresh
    await respond(change, session('changed', 2, 2))
    await transition
    expectSession('changed', 2, 2)
  })

  it.each(['profile', 'local'] as const)('rejects a saved render refresh after a completed %s change with the same token', async (kind) => {
    mount()
    await login()
    const savedRefresh = auth.actualizarSesion
    const transition = start(() => kind === 'profile' ? auth.cambiarPerfil(2) : auth.cambiarLocal(2))
    await respond(requests.at(-1)!, session('original', 2, 2))
    await transition
    const count = requests.length
    const refresh = start(savedRefresh)
    expect(requests).toHaveLength(count)
    await refresh
    expectSession('original', 2, 2)
  })

  it.each(['profile', 'local'] as const)('does not apply a %s response after logout', async (kind) => {
    mount()
    await login()
    const operation = start(() => kind === 'profile' ? auth.cambiarPerfil(2) : auth.cambiarLocal(2))
    const request = requests.at(-1)!
    act(() => auth.logout())
    await respond(request, session('changed', 2, 2))
    await operation
    expectSession(null)
    expect(auth.cambiandoPerfil).toBe(false)
    expect(auth.cambiandoLocal).toBe(false)
  })

  it('lets a newer local transition win over a pending profile transition', async () => {
    mount()
    await login()
    const profile = start(() => auth.cambiarPerfil(2))
    const oldRequest = requests.at(-1)!
    const local = start(() => auth.cambiarLocal(2))
    const newRequest = requests.at(-1)!
    await respond(oldRequest, session('old', 2, 1))
    await profile
    expect(auth.cambiandoLocal).toBe(true)
    expectSession('original', 1, 1)
    await respond(newRequest, session('new', 1, 2))
    await local
    expectSession('new', 1, 2)
  })

  it('does not apply a login response after logout', async () => {
    mount()
    const operation = start(() => auth.login('test@example.com', 'secret'))
    act(() => auth.logout())
    await respond(requests[0], session())
    await operation
    expectSession(null)
  })

  it('keeps the newest login when an earlier login completes last', async () => {
    mount()
    const first = start(() => auth.login('first@example.com', 'secret'))
    const second = start(() => auth.login('second@example.com', 'secret'))
    await respond(requests[1], session('second', 2, 2))
    await second
    await respond(requests[0], session('first'))
    await first
    expectSession('second', 2, 2)
  })

  it.each(['success', 'failure'] as const)('ignores a late restoration %s after a newer login', async (outcome) => {
    sessionStorage.setItem('token', 'saved')
    mount()
    const restore = requests[0]
    await login(session('new', 2, 2))
    await respond(restore, outcome === 'failure' ? new Error('expired token') : session('saved'))
    expectSession('new', 2, 2)
    expect(auth.cargando).toBe(false)
  })

  it('does not restore a saved session after logout', async () => {
    sessionStorage.setItem('token', 'saved')
    mount()
    act(() => auth.logout())
    await respond(requests[0], session('saved'))
    expectSession(null)
    expect(auth.cargando).toBe(false)
  })

  it('clears an invalid current saved session and finishes loading', async () => {
    sessionStorage.setItem('token', 'saved')
    mount()
    await respond(requests[0], new Error('expired token'))
    expectSession(null)
    expect(auth.cargando).toBe(false)
  })

  it('keeps current refresh errors visible to its caller', async () => {
    mount()
    await login()
    const operation = start(() => auth.actualizarSesion())
    await respond(requests.at(-1)!, new Error('network error'))
    expect(await operation).toEqual(new Error('network error'))
    expectSession('original', 1, 1)
  })

  it('does not persist a pending login after the provider unmounts', async () => {
    const view = mount()
    const operation = start(() => auth.login('test@example.com', 'secret'))
    view.unmount()
    await respond(requests[0], session())
    await operation
    expect(sessionStorage.getItem('token')).toBeNull()
  })

  it('ignores the disposed StrictMode restoration after a later restoration succeeds', async () => {
    sessionStorage.setItem('token', 'saved')
    mount(true)
    expect(requests).toHaveLength(2)
    await respond(requests[1], session('saved', 2, 2))
    await respond(requests[0], new Error('disposed request failed'))
    expectSession('saved', 2, 2)
    expect(auth.cargando).toBe(false)
  })
})
