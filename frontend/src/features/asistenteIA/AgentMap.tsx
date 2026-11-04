import { useEffect, useRef, useState, type PointerEvent, type KeyboardEvent, type CSSProperties } from 'react'
import { Bot, Network, X, Plus, Minus, Expand, Shrink, Crosshair, ArrowUpRight, Boxes, ShoppingBag, Tags, Utensils, CookingPot, BookOpen, Package, Layers, ShieldCheck, ChevronRight, BadgePercent, Sparkles, FileText, UserCheck, RotateCcw, type LucideIcon } from 'lucide-react'
import type { AgenteId, CatalogoAgentes, RespuestaAsistente } from './service'
import { nombresAgentes } from './service'
import { etiqueta } from './labels'
import { agentGraph } from './agentGraph'
import { moveBubble } from './bubbleLayout'
import './AgentMap.css'

// Only visual placement lives here; ownership and topology come from the manifest.
const layout: { id: AgenteId; x: number; y: number; icon: LucideIcon; tone: string; caption: string }[] = [
  { id: 'compras', x: 225, y: 420, icon: ShoppingBag, tone: 'forest', caption: 'Pedidos y reposición' },
  { id: 'eventos', x: 110, y: 155, icon: Network, tone: 'sage', caption: 'Agenda cercana y fuentes' },
  { id: 'recepcion', x: 105, y: 650, icon: Package, tone: 'olive', caption: 'Entregas y pendientes' },
  { id: 'inventario', x: 380, y: 185, icon: Boxes, tone: 'forest', caption: 'Stock y operación diaria' },
  { id: 'demanda', x: 510, y: 70, icon: Layers, tone: 'sage', caption: 'Ventas, consumo y cobertura' },
  { id: 'carta_recetas', x: 360, y: 650, icon: Package, tone: 'olive', caption: 'Productos, categorías y proveedores' },
  { id: 'subproductos', x: 255, y: 835, icon: CookingPot, tone: 'sage', caption: 'Preparaciones internas' },
  { id: 'presentaciones', x: 830, y: 425, icon: Layers, tone: 'forest', caption: 'Artículo, contenido y precio' },
  { id: 'categorias_carta', x: 1030, y: 235, icon: Tags, tone: 'olive', caption: 'Organización de la carta' },
  { id: 'menajes', x: 1060, y: 560, icon: Utensils, tone: 'sage', caption: 'Platos, vasos y formas de servir' },
  { id: 'recetas', x: 785, y: 745, icon: BookOpen, tone: 'olive', caption: 'Ingredientes de cada presentación' },
  { id: 'promociones', x: 790, y: 130, icon: BadgePercent, tone: 'sage', caption: 'Combos, opciones y horarios' },
]
const center = { x: 570, y: 445 }
type MapAgentId = AgenteId | 'orquestador' | 'actualizador_skills' | 'validador_skills'
function initialPosition(id: MapAgentId) {
  if (id === 'actualizador_skills') return { x: 1420, y: 360 }
  if (id === 'validador_skills') return { x: 1420, y: 505 }
  return id === 'orquestador' ? center : layout.find(node => node.id === id)
}

function curve(from: { x: number; y: number }, to: { x: number; y: number }) {
  const dx = to.x - from.x, dy = to.y - from.y
  const length = Math.hypot(dx, dy) || 1
  const control = { x: (from.x + to.x) / 2 - dy * .15, y: (from.y + to.y) / 2 + dx * .15 }
  const endLength = Math.hypot(to.x - control.x, to.y - control.y) || 1
  return `M${from.x + dx / length * 45} ${from.y + dy / length * 45} Q${control.x} ${control.y} ${to.x - (to.x - control.x) / endLength * 49} ${to.y - (to.y - control.y) / endLength * 49}`
}

export function AgentMap({ catalog, onClose, communications = [] }: { catalog: CatalogoAgentes; onClose: () => void; communications?: RespuestaAsistente['comunicaciones'] }) {
  const [selected, setSelected] = useState<MapAgentId>('orquestador')
  const [panelOpen, setPanelOpen] = useState(false)
  const [zoom, setZoom] = useState(1)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [fit, setFit] = useState(1)
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const [dragging, setDragging] = useState(false)
  const [positions, setPositions] = useState<Record<string, { x: number; y: number }>>({})
  const [heldBubble, setHeldBubble] = useState<string | null>(null)
  const bubbleDrag = useRef<{ id: MapAgentId; pointerId: number; x: number; y: number; origin: { x: number; y: number }; scale: number; moved: boolean } | null>(null)
  const suppressedClick = useRef<MapAgentId | null>(null)
  const root = useRef<HTMLElement>(null)
  const viewport = useRef<HTMLDivElement>(null)
  const panel = useRef<HTMLElement>(null)
  const panelClose = useRef<HTMLButtonElement>(null)
  const returnFocus = useRef<HTMLElement | null>(null)
  const keyboardNavigation = useRef(true)
  const drag = useRef<{ x: number; y: number; px: number; py: number } | null>(null)
  const administrative = catalog.administracion?.find(a => a.id === selected)
  const hasAdministration = Boolean(catalog.administracion?.length)
  const stageWidth = hasAdministration ? 1640 : 1200
  const agent = administrative ?? catalog.agentes.find(a => a.id === selected)
  const config = layout.find(a => a.id === selected)
  const Icon = administrative ? selected === 'actualizador_skills' ? Sparkles : ShieldCheck : config?.icon ?? Network
  const connections = agentGraph(catalog)
  const visibleConnections = connections.filter(c => c.tipo === 'dependencia')
  const requests = visibleConnections.filter(c => c.origen === selected)
  const callers = visibleConnections.filter(c => c.destino === selected)
  const latestCommunication = communications.at(-1)
  const related = new Set([selected, ...requests.map(c => c.destino), ...callers.map(c => c.origen)])

  function position(id: MapAgentId) { return positions[id] ?? initialPosition(id) }
  function placeBubble(id: MapAgentId, target: { x: number; y: number }) {
    setPositions(current => {
      const ids: MapAgentId[] = ['orquestador', ...layout.filter(node => catalog.agentes.some(agent => agent.id === node.id)).map(node => node.id)]
      const bubbles = ids.map(key => ({ id: key, ...(current[key] ?? initialPosition(key)!),
        width: key === 'orquestador' ? 204 : 230, height: key === 'orquestador' ? 204 : 230, offsetY: key === 'orquestador' ? 0 : 60 }))
      return Object.fromEntries(moveBubble(bubbles, id, target, { width: 1200, height: 1040 }).map(node => [node.id, { x: node.x, y: node.y }]))
    })
  }
  function grabBubble(e: PointerEvent<HTMLButtonElement>, id: MapAgentId) {
    if (e.button !== 0 || bubbleDrag.current) return
    const origin = position(id)
    if (!origin) return
    e.stopPropagation(); e.preventDefault()
    suppressedClick.current = null
    bubbleDrag.current = { id, pointerId: e.pointerId, x: e.clientX, y: e.clientY, origin, scale: fit * zoom, moved: false }
    e.currentTarget.setPointerCapture?.(e.pointerId)
  }
  function nudgeBubble(e: KeyboardEvent<HTMLButtonElement>, id: MapAgentId) {
    const delta: Record<string, { x: number; y: number }> = { ArrowLeft: { x: -30, y: 0 }, ArrowRight: { x: 30, y: 0 }, ArrowUp: { x: 0, y: -30 }, ArrowDown: { x: 0, y: 30 } }
    const step = delta[e.key], origin = position(id)
    if (!step || !origin) return
    e.preventDefault(); e.stopPropagation(); setPanelOpen(false)
    placeBubble(id, { x: origin.x + step.x, y: origin.y + step.y })
  }

  function selectAgent(id: MapAgentId, trigger?: HTMLElement) {
    if (trigger && suppressedClick.current === id) { suppressedClick.current = null; return }
    if (trigger && !panel.current?.contains(trigger)) returnFocus.current = trigger
    if (panelOpen && selected === id) panelClose.current?.focus({ preventScroll: true })
    setSelected(id); setPanelOpen(true)
  }
  function closePanel() {
    setPanelOpen(false)
    const trigger = returnFocus.current?.isConnected ? returnFocus.current :
      root.current?.querySelector<HTMLButtonElement>('button[aria-pressed="true"]')
    trigger?.focus({ preventScroll: true })
  }

  useEffect(() => {
    if (panelOpen) panelClose.current?.focus({ preventScroll: true })
  }, [panelOpen, selected])

  function focusNode(id: MapAgentId) {
    if (!keyboardNavigation.current) return
    const node = position(id)
    if (!node) return
    // A focused node must not remain behind the floating detail panel.
    setPanelOpen(false)
    setPan({ x: (stageWidth / 2 - node.x) * fit * zoom, y: (480 - node.y - 45) * fit * zoom })
  }

  useEffect(() => {
    const element = viewport.current
    if (!element) return
    const observer = new ResizeObserver(([entry]) => {
      if (entry.contentRect.width <= 0 || entry.contentRect.height <= 0) return
      // Include node labels and space for the floating controls, not only the SVG.
      setFit(Math.max(.1, Math.min((entry.contentRect.width - 48) / stageWidth,
        (entry.contentRect.height - 100) / 1040, 1.25)))
    })
    observer.observe(element)
    return () => observer.disconnect()
  }, [stageWidth])

  function start(e: PointerEvent<HTMLDivElement>) {
    if (e.button !== 0 || bubbleDrag.current || (e.target as HTMLElement).closest('button, select, .agent-atlas-panel, .agent-atlas-live')) return
    drag.current = { x: e.clientX, y: e.clientY, px: pan.x, py: pan.y }
    e.currentTarget.setPointerCapture(e.pointerId); setDragging(true)
  }
  function move(e: PointerEvent<HTMLDivElement>) {
    const bubble = bubbleDrag.current
    if (bubble && bubble.pointerId === e.pointerId) {
      const dx = e.clientX - bubble.x, dy = e.clientY - bubble.y
      if (!bubble.moved && Math.hypot(dx, dy) < 5) return
      bubble.moved = true; setHeldBubble(bubble.id); setPanelOpen(false)
      placeBubble(bubble.id, { x: bubble.origin.x + dx / bubble.scale, y: bubble.origin.y + dy / bubble.scale })
      return
    }
    if (drag.current) setPan({ x: drag.current.px + e.clientX - drag.current.x, y: drag.current.py + e.clientY - drag.current.y })
  }
  function stop() {
    if (bubbleDrag.current?.moved) suppressedClick.current = bubbleDrag.current.id
    bubbleDrag.current = null; setHeldBubble(null)
    drag.current = null; setDragging(false)
  }
  function reset() { setPan({ x: 0, y: 0 }); setZoom(1) }
  async function fullscreen() {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await root.current?.requestFullscreen() } catch { reset() }
  }
  useEffect(() => {
    const changed = () => { setIsFullscreen(document.fullscreenElement === root.current); reset() }
    document.addEventListener('fullscreenchange', changed)
    return () => document.removeEventListener('fullscreenchange', changed)
  }, [])

  return <section ref={root} className="agent-atlas agent-atlas-radial" aria-label="Mapa de agentes" onPointerDownCapture={() => { keyboardNavigation.current = false }} onKeyDownCapture={() => { keyboardNavigation.current = true; suppressedClick.current = null }} onKeyDown={e => {
    if (e.key === 'Escape') { e.stopPropagation(); if (panelOpen) closePanel(); else onClose() }
  }}>

    <div ref={viewport} className={`agent-atlas-viewport ${dragging ? 'is-dragging' : ''}`} onPointerDown={start} onPointerMove={move} onPointerUp={stop} onPointerCancel={stop} onLostPointerCapture={stop}>
      <div className={`agent-atlas-stage ${hasAdministration ? 'has-administration' : ''}`} style={{ width: stageWidth, '--radial-transform': `translate(-50%, -50%) translate(${pan.x}px, ${pan.y}px) scale(${fit * zoom})`, transform: `translate(-50%, -50%) translate(${pan.x}px, ${pan.y}px) scale(${fit * zoom})` } as CSSProperties}>
        <svg className="agent-atlas-wires" viewBox="0 0 1200 960" aria-hidden="true"><defs><linearGradient id="atlas-wire"><stop stopColor="#94b9a1" /><stop offset=".5" stopColor="#167b54" /><stop offset="1" stopColor="#94b9a1" /></linearGradient>
          <marker id="atlas-arrow" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto"><polygon points="0 0,7 3.5,0 7" fill="#8b9159" /></marker><marker id="atlas-arrow-selected" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto-start-reverse"><polygon points="0 0,7 3.5,0 7" fill="#258956" /></marker></defs>
          <g className="agent-atlas-rings"><circle cx="570" cy="445" r="155" /><circle cx="570" cy="445" r="290" /><circle cx="570" cy="445" r="435" /><path d="M80 445 H1110 M570 35 V920" /></g>
          {hasAdministration && <g className="agent-atlas-administration-wire"><path d="M1110 445 H1230 M1110 405 V485" /><text x="1130" y="430">Skills</text></g>}
          {connections.filter(c => c.tipo === 'coordinacion').map(c => {
            const from = position(c.origen), to = position(c.destino)
            if (!from || !to) return null
            return <path key={`${c.origen}-${c.destino}`} className={`agent-atlas-root-wire ${selected === c.destino || selected === c.origen ? 'is-lit' : ''}`} d={curve(from, to)} />
          })}
          {visibleConnections.map(c => {
            const from = position(c.origen), to = position(c.destino)
            if (!from || !to) return null
            const highlighted = selected === c.destino || selected === c.origen
            const recent = communications.some(m => (m.de === c.origen && m.a === c.destino) || (m.a === c.origen && m.de === c.destino))
            return <g key={`${c.origen}-${c.destino}`} className={`agent-atlas-branch ${highlighted ? 'is-selected' : ''} ${recent ? 'is-recent' : ''}`}><title>{nombresAgentes[c.origen]} puede solicitar {nombresAgentes[c.destino]} mediante el Coordinador. El resultado regresa tras confirmar.</title><path d={curve(from, to)} markerEnd={highlighted ? 'url(#atlas-arrow-selected)' : 'url(#atlas-arrow)'} /></g>
          })}
        </svg>
        <button className={`agent-atlas-core ${heldBubble === 'orquestador' ? 'is-held' : ''} ${selected === 'orquestador' ? 'is-selected' : ''}`} style={{ left: position('orquestador')!.x, top: position('orquestador')!.y }} onPointerDown={e => grabBubble(e, 'orquestador')} onKeyDown={e => nudgeBubble(e, 'orquestador')} onFocus={() => focusNode('orquestador')} onClick={e => selectAgent('orquestador', e.currentTarget)} aria-pressed={selected === 'orquestador'} aria-controls={panelOpen ? 'agent-atlas-detail' : undefined} aria-expanded={panelOpen && selected === 'orquestador'}><span className="agent-atlas-core-icon"><Bot size={32} strokeWidth={1.5} /></span><strong>Coordinador</strong><small>Delega · conserva tu tarea · retoma</small><span className="agent-atlas-core-label">PUNTO DE ENTRADA</span></button>
        <span className="agent-atlas-sector is-operation">OPERACIÓN</span><span className="agent-atlas-sector is-catalog">INSUMOS Y PREPARACIÓN</span><span className="agent-atlas-sector is-menu">CARTA Y VENTAS</span>
        {layout.map(node => {
          const item = catalog.agentes.find(a => a.id === node.id)
          if (!item) return null
          const NodeIcon = node.icon
          return <button key={item.id} className={`agent-atlas-node agent-atlas-tone-${node.tone} ${heldBubble === item.id ? 'is-held' : ''} ${selected === item.id ? 'is-selected' : ''} ${selected !== 'orquestador' && !related.has(item.id) ? 'is-muted' : ''} ${latestCommunication && (latestCommunication.de === item.id || latestCommunication.a === item.id) ? 'has-communication' : ''}`} style={{ left: position(item.id)!.x, top: position(item.id)!.y, "--node-x": `${position(item.id)!.x}px`, "--node-y": `${position(item.id)!.y}px` } as CSSProperties} onPointerDown={e => grabBubble(e, item.id)} onKeyDown={e => nudgeBubble(e, item.id)} onFocus={() => focusNode(item.id)} onClick={e => selectAgent(item.id, e.currentTarget)} aria-pressed={selected === item.id} aria-controls={panelOpen ? 'agent-atlas-detail' : undefined} aria-expanded={panelOpen && selected === item.id}>
            <span className="agent-atlas-node-icon"><NodeIcon size={29} strokeWidth={1.5} /></span><span className="agent-atlas-node-body"><strong>{item.nombre}</strong><small>{node.caption}</small><span className="agent-atlas-node-meta"><small>{item.skills.length} {item.skills.length === 1 ? 'habilidad' : 'habilidades'}</small><span>Explorar <ChevronRight size={12} /></span></span></span></button>
        })}
        {hasAdministration && <section className="agent-atlas-administration" aria-label="Administración de agentes">
          <header><span>ADMINISTRACIÓN DE AGENTES</span><h3>Mejora sus skills</h3><p>Trabaja sobre el agente que selecciones.</p></header>
          <div className="agent-atlas-admin-source"><FileText size={18} /><span>Skill actual + archivos</span></div>
          <span className="agent-atlas-admin-arrow" aria-hidden="true">↓</span>
          {catalog.administracion?.map(item => {
            const AdminIcon = item.id === 'actualizador_skills' ? Sparkles : ShieldCheck
            return <div key={item.id}><button className="agent-atlas-admin-node" onFocus={() => focusNode(item.id)} onClick={event => selectAgent(item.id, event.currentTarget)} aria-pressed={selected === item.id} aria-expanded={panelOpen && selected === item.id} aria-controls={panelOpen && selected === item.id ? 'agent-atlas-detail' : undefined}>
              <AdminIcon size={25} /><span><strong>{item.nombre}</strong><small>{item.id === 'actualizador_skills' ? 'Propone una skill editable' : 'Revisa y señala lo que falta'}</small></span><ChevronRight size={18} />
            </button><span className="agent-atlas-admin-arrow" aria-hidden="true">↓</span></div>
          })}
          <div className="agent-atlas-admin-save"><UserCheck size={22} /><strong>Tú guardas los cambios</strong></div>
          <p>Solo tras validar sin bloqueos. También puedes editar y validar directamente.</p>
          <footer>Aplica a las skills del Coordinador y los especialistas. Los permisos se asignan por separado.</footer>
        </section>}
      </div>
      <div className="agent-atlas-map-label"><span className="agent-atlas-map-cross">+</span><span>ECOSISTEMA BARBARIAN<small>Administración del asistente</small></span></div>
      <div className="agent-atlas-floating-legend" onPointerDown={e => e.stopPropagation()} aria-label="Leyenda del mapa"><span className="agent-atlas-edge-legend"><b /><span>Coordinación</span><b className="is-requirement" /><span>Solicita requisito →</span></span></div>
      <div className="agent-atlas-controls" onPointerDown={e => e.stopPropagation()}><button onClick={() => setZoom(z => Math.max(1, z - .15))} disabled={zoom <= 1} aria-label="Alejar mapa"><Minus size={17} /></button><span aria-live="polite">{Math.round(zoom * 100)}%</span><button onClick={() => setZoom(z => Math.min(1.9, z + .15))} disabled={zoom >= 1.9} aria-label="Acercar mapa"><Plus size={17} /></button><span className="agent-atlas-control-separator" /><button onClick={() => { setPositions({}); stop() }} title="Restablecer burbujas" aria-label="Restablecer burbujas"><RotateCcw size={18} /></button><button onClick={reset} title="Centrar mapa" aria-label="Centrar mapa"><Crosshair size={18} /></button><button onClick={() => void fullscreen()} title={isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa'} aria-label={isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa'}>{isFullscreen ? <Shrink size={18} /> : <Expand size={18} />}</button></div>
      <span className="agent-atlas-pan-hint">{administrative ? 'Propone y valida configuraciones · tú decides qué guardar' : selected === 'orquestador' ? 'Arrastra las burbujas para moverlas · arrastra el fondo para explorar' : 'Los traspasos pasan por el Coordinador · cada creación requiere confirmación'}</span>
      {latestCommunication && <div className="agent-atlas-live" role="status"><span className="agent-atlas-eyebrow">ÚLTIMO TRASPASO DE ESTA CONVERSACIÓN</span><button onClick={e => selectAgent(latestCommunication.a, e.currentTarget)}>{nombresAgentes[latestCommunication.de]} <ChevronRight size={14} /> {nombresAgentes[latestCommunication.a]} <ArrowUpRight size={14} /></button><small>{latestCommunication.motivo}</small></div>}
      {panelOpen && <aside ref={panel} className={`agent-atlas-panel ${administrative || (config && config.x > 540) ? 'is-panel-left' : ''}`} aria-labelledby="agent-atlas-panel-title" onPointerDown={e => e.stopPropagation()}>
        <header className="agent-atlas-panel-heading"><div><span className="agent-atlas-eyebrow">EXPLORAR AGENTE</span><h3 id="agent-atlas-panel-title">{agent?.nombre ?? 'Coordinador'}</h3></div><button ref={panelClose} className="agent-atlas-panel-close" onClick={closePanel} aria-label="Cerrar detalle del agente"><X size={18} /></button></header>
        <div key={selected} className="agent-atlas-panel-scroll" tabIndex={0} role="region" aria-label={`Información e instrucciones de ${agent?.nombre ?? 'Coordinador'}`}>
    <section id="agent-atlas-detail" className="agent-atlas-detail">
      <div className="agent-atlas-detail-intro"><span className="agent-atlas-detail-icon"><Icon size={24} /></span><div><span className="agent-atlas-eyebrow">{agent ? 'ESPECIALISTA SELECCIONADO' : 'EL CENTRO DE TU ASISTENTE'}</span><h3>{agent?.nombre ?? 'Coordinador'}</h3><p>{agent?.descripcion ?? 'Interpreta lo que necesitas y dirige la solicitud al especialista adecuado, conservando el contexto de la conversación.'}</p></div></div>
      {requests.length > 0 && <div className="agent-atlas-flow-parents"><span>Puede solicitar ayuda a</span><div>{requests.map(c => <button key={c.destino} onClick={() => selectAgent(c.destino)}>{nombresAgentes[c.destino]}<ChevronRight size={12} /></button>)}</div><p>Si falta un requisito, delega su creación. Después de tu confirmación recibe el resultado y continúa.</p></div>}
      {callers.length > 0 && <div className="agent-atlas-flow-parents is-return"><span>Devuelve resultados a</span><div>{callers.map(c => <button key={c.origen} onClick={() => selectAgent(c.origen)}>{nombresAgentes[c.origen]}<ChevronRight size={12} /></button>)}</div></div>}
      {agent ? <>{administrative ? <p>Apoya la configuración de cualquier agente desde Archivos de agentes. No ejecuta compras ni modifica permisos.</p> : <div className="agent-atlas-capabilities"><div><span>Puede trabajar con</span><p>{(agent.recursos_modificables ?? agent.recursos).map(etiqueta).join(' · ')}</p></div>{Boolean(agent.recursos_solo_consulta?.length) && <div><span>Consulta como referencia</span><p>{agent.recursos_solo_consulta?.map(etiqueta).join(' · ')}</p></div>}<div><span>Habilidades específicas</span><p>{agent.skills.map(s => s.nombre).join(' · ') || 'Instrucciones del especialista'}</p></div></div>}
        <details className="agent-atlas-technical" open key={agent.id}><summary><ChevronRight size={15} />Instrucciones y skills</summary><div><details open><summary>Instrucciones del agente</summary><pre>{agent.instrucciones}</pre></details>{!administrative && agent.skills.map(s => <details open key={s.archivo}><summary>{s.nombre}</summary><pre>{s.contenido}</pre></details>)}</div></details></> : <><div className="agent-atlas-coordinator-flow"><span>Tu solicitud</span><ChevronRight size={16} /><span>Coordinador</span><ChevronRight size={16} /><span>Especialista</span><ChevronRight size={16} /><span>Revisión y confirmación</span></div>
          <details className="agent-atlas-technical" open><summary>Instrucciones y skills</summary><pre>{catalog.coordinador.instrucciones ?? catalog.coordinador.descripcion}</pre>{catalog.coordinador.skills.map(skill => <details key={skill.archivo}><summary>{skill.nombre}</summary><pre>{skill.contenido}</pre></details>)}</details></>}
    </section>
        </div>
      </aside>}
    </div>
    <footer className="agent-atlas-footer"><ShieldCheck size={16} /><span>Los agentes preparan propuestas. Tú revisas y confirmas cada cambio.</span></footer>
  </section>
}
