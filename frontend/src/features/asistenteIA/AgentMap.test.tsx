import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AgentMap } from './AgentMap'
import type { CatalogoAgentes } from './service'

const catalog: CatalogoAgentes = {
  coordinador: { id: 'orquestador', nombre: 'Coordinador', descripcion: 'Coordina tareas.',
    relaciones: ['menajes', 'subproductos', 'carta_recetas'], skills: [], reglas_ruta: {} },
  agentes: [
    { id: 'menajes', nombre: 'Menajes', descripcion: 'Gestiona menajes.', relaciones: ['orquestador'],
      herramientas: [], recursos: ['menajes'], recursos_modificables: ['menajes'], instrucciones: 'Revisar menajes.', skills: [] },
    { id: 'subproductos', nombre: 'Subproductos', descripcion: 'Gestiona preparaciones.', relaciones: ['orquestador'],
      herramientas: [], recursos: ['subproductos', 'productos'], recursos_modificables: ['subproductos'],
      recursos_solo_consulta: ['productos'], instrucciones: 'Revisar preparaciones.', skills: [] },
    { id: 'carta_recetas', nombre: 'Catálogo de insumos', descripcion: 'Gestiona productos.', relaciones: ['orquestador'],
      herramientas: [], recursos: ['productos'], instrucciones: 'Revisar productos.', skills: [] },
  ], limite_salon: '', regla_ejecucion: '',
}

beforeEach(() => {
  vi.stubGlobal('ResizeObserver', class { observe() {} disconnect() {} })
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('agent map navigation', () => {
  it('drags a bubble, pushes its neighbour, updates wires and suppresses the drag click', () => {
    vi.stubGlobal('PointerEvent', MouseEvent)
    const { container } = render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Subproductos.*Preparaciones internas/ })
    const other = screen.getByRole('button', { name: /Catálogo de insumos.*Productos/ })
    const wirePaths = () => [...container.querySelectorAll('.agent-atlas-root-wire')].map(wire => wire.getAttribute('d'))
    const originalWire = wirePaths()
    const originalOther = other.getAttribute('style')
    fireEvent.pointerDown(node, { button: 0, clientX: 255, clientY: 835 })
    fireEvent.pointerMove(node, { clientX: 360, clientY: 650 })
    fireEvent.pointerUp(node)
    fireEvent.click(node)
    expect(screen.queryByRole('complementary')).toBeNull()
    expect(node.style.left).not.toBe('255px')
    expect(other.getAttribute('style')).not.toBe(originalOther)
    expect(wirePaths()).not.toEqual(originalWire)
    fireEvent.click(node)
    expect(screen.getByRole('complementary', { name: 'Subproductos' })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle del agente' }))
    fireEvent.click(screen.getByRole('button', { name: 'Restablecer burbujas' }))
    expect(node.style.left).toBe('255px')
  })
  it('supports moving a focused bubble with arrow keys', () => {
    render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Subproductos.*Preparaciones internas/ })
    fireEvent.keyDown(node, { key: 'ArrowRight' })
    expect(node.style.left).toBe('285px')
    expect(screen.queryByRole('complementary')).toBeNull()
  })
  it('converts pointer movement using the fitted canvas scale', () => {
    vi.stubGlobal('PointerEvent', MouseEvent)
    vi.stubGlobal('ResizeObserver', class {
      callback: (entries: { contentRect: { width: number; height: number } }[]) => void
      constructor(callback: (entries: { contentRect: { width: number; height: number } }[]) => void) { this.callback = callback }
      observe() { this.callback([{ contentRect: { width: 648, height: 620 } }]) }
      disconnect() {}
    })
    render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Subproductos.*Preparaciones internas/ })
    fireEvent.pointerDown(node, { button: 0, clientX: 100, clientY: 100 })
    fireEvent.pointerMove(node, { clientX: 115, clientY: 100 })
    fireEvent.pointerUp(node)
    expect(node.style.left).toBe('285px')
  })
  it('preserves click selection when the pointer has not moved enough to drag', () => {
    vi.stubGlobal('PointerEvent', MouseEvent)
    render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Subproductos.*Preparaciones internas/ })
    fireEvent.pointerDown(node, { button: 0, clientX: 100, clientY: 100 })
    fireEvent.pointerMove(node, { clientX: 102, clientY: 101 })
    fireEvent.pointerUp(node)
    fireEvent.click(node)
    expect(screen.getByRole('complementary', { name: 'Subproductos' })).toBeTruthy()
    expect(node.style.left).toBe('255px')
  })
  it('shows administrative agents beside the ecosystem with a separate human-approved flow', () => {
    const administration: NonNullable<CatalogoAgentes['administracion']> = [
      { id: 'actualizador_skills', nombre: 'Actualizador de skills', descripcion: 'Propone sin guardar.', relaciones: [], herramientas: [], recursos: [], instrucciones: 'Leer archivos seleccionados.', skills: [] },
      { id: 'validador_skills', nombre: 'Validador de skills', descripcion: 'Valida sin conceder permisos.', relaciones: [], herramientas: [], recursos: [], instrucciones: 'Revisar independientemente.', skills: [] },
    ]
    render(<AgentMap catalog={{ ...catalog, administracion: administration }} onClose={() => {}} />)
    expect(screen.getByRole('region', { name: 'Administración de agentes' })).toBeTruthy()
    expect(screen.getByText('Tú guardas los cambios')).toBeTruthy()
    vi.stubGlobal('PointerEvent', MouseEvent)
    const operational = screen.getByRole('button', { name: /Subproductos.*Preparaciones internas/ })
    const originalPosition = operational.getAttribute('style')
    const administrative = screen.getByRole('button', { name: /Validador de skills.*Revisa/ })
    fireEvent.pointerDown(administrative, { button: 0, clientX: 100, clientY: 100 })
    fireEvent.pointerMove(administrative, { clientX: 140, clientY: 100 })
    fireEvent.pointerUp(administrative)
    expect(operational.getAttribute('style')).toBe(originalPosition)
    fireEvent.click(screen.getByRole('button', { name: /Validador de skills.*Revisa/ }))
    const panel = screen.getByRole('complementary', { name: 'Validador de skills' })
    expect(within(panel).getByText('Revisar independientemente.')).toBeTruthy()
  })
  it('fits the complete graph below 100% when the viewport is shorter than the canvas', () => {
    vi.stubGlobal('ResizeObserver', class {
      callback: (entries: { contentRect: { width: number; height: number } }[]) => void
      constructor(callback: (entries: { contentRect: { width: number; height: number } }[]) => void) { this.callback = callback }
      observe() { this.callback([{ contentRect: { width: 1440, height: 700 } }]) }
      disconnect() {}
    })
    const { container } = render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const transform = container.querySelector('.agent-atlas-stage')!.getAttribute('style')!
    const scale = Number(/scale\(([\d.]+)\)/.exec(transform)?.[1])
    expect(scale).toBeGreaterThan(0)
    expect(scale).toBeLessThan(1)
  })

  it('opens directly on the canvas with its legend above distinct map controls', () => {
    const { container } = render(<AgentMap catalog={catalog} onClose={() => {}} />)
    expect(container.querySelector('.agent-atlas-heading')).toBeNull()
    expect(screen.queryByRole('combobox', { name: 'Explorar agente' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Cerrar mapa de agentes' })).toBeNull()
    const legend = screen.getByText('Coordinación')
    expect(legend.closest('.agent-atlas-viewport')).toBeTruthy()
    const center = screen.getByRole('button', { name: 'Centrar mapa' })
    const fullscreen = screen.getByRole('button', { name: 'Pantalla completa' })
    expect(center.querySelector('svg')?.outerHTML).not.toBe(fullscreen.querySelector('svg')?.outerHTML)
  })
  it('shows events and reception as separate selectable specialists', () => {
    const operationalCatalog: CatalogoAgentes = {
      ...catalog,
      coordinador: { ...catalog.coordinador, relaciones: [...catalog.coordinador.relaciones, 'eventos', 'recepcion'] },
      agentes: [...catalog.agentes,
        { id: 'eventos', nombre: 'Eventos cercanos', descripcion: 'Consulta fuentes externas.',
          relaciones: ['orquestador'], herramientas: ['web_search'], recursos: ['eventos_cercanos'],
          instrucciones: 'Solo lectura.', skills: [] },
        { id: 'recepcion', nombre: 'Recepción', descripcion: 'Compara entregas y pendientes.',
          relaciones: ['orquestador'], herramientas: ['consultar'], recursos: ['recepciones'],
          instrucciones: 'Verificación física humana.', skills: [] },
      ],
    }
    render(<AgentMap catalog={operationalCatalog} onClose={() => {}} />)
    expect(screen.getByRole('button', { name: /Eventos cercanos.*Agenda cercana/ })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /Recepción.*Entregas y pendientes/ }))
    expect(screen.getByRole('complementary', { name: 'Recepción' })).toBeTruthy()
  })
  it('opens an agent directly from its node and focuses its non-modal details', () => {
    render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Subproductos.*Preparaciones internas/ })
    fireEvent.click(node)
    const panel = screen.getByRole('complementary', { name: 'Subproductos' })
    expect(panel.getAttribute('aria-modal')).toBeNull()
    expect(document.activeElement).toBe(within(panel).getByRole('button', { name: 'Cerrar detalle del agente' }))
    expect(within(panel).getByRole('button', { name: 'Catálogo de insumos' })).toBeTruthy()
    fireEvent.keyDown(panel, { key: 'Escape' })
    expect(screen.queryByRole('complementary')).toBeNull()
    expect(document.activeElement).toBe(node)
  })

  it('uses server graph topology even when it differs from the old map', () => {
    const serverCatalog = { ...catalog, conexiones: [
      { origen: 'orquestador', destino: 'subproductos', tipo: 'coordinacion' },
      { origen: 'subproductos', destino: 'menajes', tipo: 'dependencia' },
    ] } as CatalogoAgentes
    render(<AgentMap catalog={serverCatalog} onClose={() => {}} />)
    fireEvent.click(screen.getByRole('button', { name: /Subproductos.*Preparaciones internas/ }))
    const panel = screen.getByRole('complementary', { name: 'Subproductos' })
    expect(within(panel).getByRole('button', { name: 'Menajes' })).toBeTruthy()
    expect(within(panel).queryByRole('button', { name: 'Catálogo de insumos' })).toBeNull()
  })

  it('returns focus to the selected node when its panel closes', () => {
    render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Menajes.*Platos, vasos/ })
    fireEvent.click(node)
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle del agente' }))
    expect(document.activeElement).toBe(node)
  })

  it('recenters a keyboard-focused node and closes the map with Escape outside details', () => {
    const close = vi.fn()
    const { container } = render(<AgentMap catalog={catalog} onClose={close} />)
    const before = container.querySelector('.agent-atlas-stage')!.getAttribute('style')
    fireEvent.focus(screen.getByRole('button', { name: /Menajes.*Platos, vasos/ }))
    expect(container.querySelector('.agent-atlas-stage')!.getAttribute('style')).not.toBe(before)
    fireEvent.keyDown(screen.getByRole('button', { name: /Menajes.*Platos, vasos/ }), { key: 'Escape' })
    expect(close).toHaveBeenCalledOnce()
  })

  it('keeps a node stationary on pointer focus so its click target stays under the pointer', () => {
    const { container } = render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Menajes.*Platos, vasos/ })
    const before = container.querySelector('.agent-atlas-stage')!.getAttribute('style')
    fireEvent.pointerDown(node)
    fireEvent.focus(node)
    expect(container.querySelector('.agent-atlas-stage')!.getAttribute('style')).toBe(before)
    fireEvent.click(node)
    expect(screen.getByRole('complementary', { name: 'Menajes' })).toBeTruthy()
  })

  it('focuses the panel again when the already selected node is clicked', () => {
    render(<AgentMap catalog={catalog} onClose={() => {}} />)
    const node = screen.getByRole('button', { name: /Menajes.*Platos, vasos/ })
    fireEvent.pointerDown(node)
    fireEvent.click(node)
    node.focus()
    fireEvent.click(node)
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Cerrar detalle del agente' }))
  })
})
