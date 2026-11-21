import { render, screen, waitFor, cleanup } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { useAuth } from '../context/authState'
import { DiagnosticsPage } from './DiagnosticsPage'

vi.mock('../context/authState', () => ({useAuth: vi.fn()}))
afterEach(() => {cleanup(); vi.unstubAllGlobals()})
const renderPage = () => render(<MemoryRouter initialEntries={['/diagnostico']}><Routes>
  <Route path="/diagnostico" element={<DiagnosticsPage />} />
  <Route path="/home" element={<p>Inicio</p>} />
</Routes></MemoryRouter>)

it('redirects a non-administrator without requesting technical data', async () => {
  vi.mocked(useAuth).mockReturnValue({token:'manager', perfilActivo:{id_perfil:2}} as ReturnType<typeof useAuth>)
  const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher)
  renderPage()
  expect(await screen.findByText('Inicio')).toBeTruthy()
  expect(fetcher).not.toHaveBeenCalled()
})

it('shows normalized routes and aborts its request when unmounted', async () => {
  vi.mocked(useAuth).mockReturnValue({token:'admin', perfilActivo:{id_perfil:1}} as ReturnType<typeof useAuth>)
  const fetcher=vi.fn().mockResolvedValue({ok:true,json:async()=>({requests:2,errors:1,capacity:500,retention_seconds:900,
    routes:[{method:'GET',route:'/api/productos/<int:id>',requests:2,errors:1,p95_ms:35}]})})
  vi.stubGlobal('fetch',fetcher)
  const view=renderPage()
  await waitFor(()=>expect(screen.getByText('/api/productos/<int:id>')).toBeTruthy())
  const signal=fetcher.mock.calls[0][1].signal
  view.unmount()
  expect(signal.aborted).toBe(true)
})
