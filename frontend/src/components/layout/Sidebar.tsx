import { useEffect, useMemo, useRef, useState } from 'react'
import { NavLink } from 'react-router-dom'
import { X, Search, LayoutGrid, Store } from 'lucide-react'

import { useAuth } from '../../context/authState'
import {
  construirArbolMenu,
  type OpcionMenuConHijos,
} from '../../utils/menuHelpers'

import barbarianLogo from '../../assets/brand/barbarian-logo.png'
import barbarianWordmark from '../../assets/brand/barbarian-wordmark.png'

import { SidebarItem } from './SidebarItem'

interface SidebarProps {
  abiertoEnMovil: boolean
  cerrarEnMovil: () => void
}

export function Sidebar({
  abiertoEnMovil,
  cerrarEnMovil,
}: SidebarProps) {
  const { menu, perfilActivo } = useAuth()
  const [search, setSearch] = useState('')
  const sidebar = useRef<HTMLElement>(null)
  const closeRef = useRef(cerrarEnMovil)
  useEffect(() => { closeRef.current = cerrarEnMovil }, [cerrarEnMovil])
  const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
  const term = normalize(search)
  const matches = (value: string) => normalize(value).includes(term)

  useEffect(() => {
    if (!abiertoEnMovil) return
    const previous = document.activeElement as HTMLElement | null
    sidebar.current?.querySelector<HTMLInputElement>('input')?.focus()
    const keyboard = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); closeRef.current(); return }
      if (event.key !== 'Tab') return
      const focusable = Array.from(sidebar.current?.querySelectorAll<HTMLElement>('a, button, input') ?? [])
        .filter(element => !element.closest('[hidden]') && !element.hasAttribute('disabled'))
      const first = focusable[0], last = focusable.at(-1)
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus() }
    }
    document.addEventListener('keydown', keyboard)
    return () => { document.removeEventListener('keydown', keyboard); if (previous?.isConnected) previous.focus() }
  }, [abiertoEnMovil])

  const menuJerarquico: OpcionMenuConHijos[] = useMemo(
    () => {
      const opciones = menu.filter(o => [2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) || ![15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 31, 32, 36, 37, 38].includes(o.id_opcion_menu))
      const movimientos = opciones.find(o => o.id_opcion_menu === 20 && o.permisos.consultar)
      if (movimientos) opciones.push({...movimientos, id_opcion_menu: -20, codigo: 'SEGUIMIENTO_MOVIMIENTOS', nombre: 'Prestamos y devoluciones', url_menu: '/home/movimientos/seguimiento', orden: movimientos.orden + 1})
      return construirArbolMenu(opciones)
    },
    [menu, perfilActivo]
  )

  const filterTree = (items: OpcionMenuConHijos[]): OpcionMenuConHijos[] => items.flatMap(item => {
    if (matches(item.nombre)) return [item]
    const hijos = filterTree(item.hijos)
    return hijos.length ? [{ ...item, hijos }] : []
  })
  const visibleMenu = filterTree(menuJerarquico)
  const assistantOptions: OpcionMenuConHijos[] = perfilActivo ? [{
    id_opcion_menu: -100, codigo: 'ASISTENTE_IA', nombre: 'Asistente IA', url_menu: null,
    descripcion: '', id_padre: null, icono: null, tipo_opcion: 'GRUPO', es_configurable: false, orden: 0,
    permisos: { consultar: true, crear: false, editar: false, revisar: false, cerrar: false, desactivar: false, reactivar: false, eliminar: false, configurar: false },
    hijos: [
      { id: -101, nombre: 'Conversación', ruta: '/home/asistente-ia' },
      ...(perfilActivo.id_perfil === 1 ? [
        { id: -102, nombre: 'Mapa de agentes', ruta: '/home/asistente-ia/agentes' },
        { id: -103, nombre: 'Archivos de agentes', ruta: '/home/asistente-ia/archivos' },
        { id: -104, nombre: 'Permisos de agentes', ruta: '/home/asistente-ia/permisos' },
      ] : []),
    ].map(child => ({ id_opcion_menu: child.id, codigo: String(child.id), nombre: child.nombre,
      url_menu: child.ruta, descripcion: '', id_padre: -100, icono: null, tipo_opcion: 'ENLACE',
      es_configurable: false, orden: 0, permisos: { consultar: true, crear: false, editar: false, revisar: false, cerrar: false, desactivar: false, reactivar: false, eliminar: false, configurar: false }, hijos: [] })),
  }] : []
  const visibleAssistant = filterTree(assistantOptions)

  return (
    <>
      <div
        className={`sidebar-overlay ${
          abiertoEnMovil ? 'sidebar-overlay--visible' : ''
        }`}
        onClick={cerrarEnMovil}
        aria-hidden="true"
      />

      <aside
        ref={sidebar}
        id="main-sidebar"
        role={abiertoEnMovil ? 'dialog' : undefined}
        aria-modal={abiertoEnMovil || undefined}
        aria-label="Navegación principal"
        className={`sidebar ${
          abiertoEnMovil ? 'sidebar--mobile-open' : ''
        }`}
      >
        <header className="sidebar-brand">
          <div className="sidebar-brand__images">
            <img
              className="sidebar-brand__logo"
              src={barbarianLogo}
              alt=""
              aria-hidden="true"
            />

            <img
              className="sidebar-brand__wordmark"
              src={barbarianWordmark}
              alt="Barbarian"
            />
          </div>

          <button
            className="sidebar-brand__close"
            type="button"
            onClick={cerrarEnMovil}
            aria-label="Cerrar menú"
          >
            <X aria-hidden="true" />
          </button>
        </header>

        <nav
          className="sidebar-navigation"
          aria-label="Menú principal"
        >
          <div className="sidebar-search">
            <Search aria-hidden="true" />
            <input type="search" aria-label="Buscar en el menú" placeholder="Buscar un módulo…"
              value={search} onChange={event => setSearch(event.target.value)} />
            {search && <button type="button" className="sidebar-search__clear" aria-label="Limpiar búsqueda del menú"
              onClick={() => setSearch('')}><X size={15} aria-hidden="true" /></button>}
          </div>
          {menuJerarquico.length > 0 || perfilActivo ? (
            <ul className="sidebar-menu">
              {matches('Tiendas') && perfilActivo?.id_perfil === 1 && menu.some(m => m.id_opcion_menu === 2 && m.permisos.consultar) &&
                <li className="sidebar-item"><NavLink to="/home/tiendas" onClick={cerrarEnMovil} className={({ isActive }) => `sidebar-link ${isActive ? 'sidebar-link--active' : ''}`}><span className="sidebar-link__main"><Store className="sidebar-link__icon" aria-hidden="true" /><span className="sidebar-link__text">Tiendas</span></span></NavLink></li>}
              {visibleAssistant.map(option => <SidebarItem key={option.id_opcion_menu} opcion={option} alNavegar={cerrarEnMovil} forzarAbierto={Boolean(term)} />)}
              {matches('Opciones de salon') && perfilActivo?.id_perfil===2 && <li className="sidebar-item"><NavLink to="/home/opciones-salon" onClick={cerrarEnMovil} className={({isActive})=>`sidebar-link ${isActive?'sidebar-link--active':''}`}><span className="sidebar-link__main"><LayoutGrid className="sidebar-link__icon" aria-hidden="true"/><span className="sidebar-link__text">Opciones de salón</span></span></NavLink></li>}
              {visibleMenu.map((opcion) => (
                <SidebarItem
                  forzarAbierto={Boolean(term)}
                  key={opcion.id_opcion_menu}
                  opcion={opcion}
                  alNavegar={cerrarEnMovil}
                />
              ))}
            </ul>
          ) : (
            <p className="sidebar-empty">
              No tienes opciones disponibles.
            </p>
          )}
          {term && visibleMenu.length === 0 && visibleAssistant.length === 0 && !matches('Opciones de salon') && !matches('Tiendas') &&
            <p className="sidebar-empty" role="status">No hay módulos con ese nombre.</p>}
        </nav>

        <footer className="sidebar-footer">
          <span className="sidebar-footer__indicator" />

          <div>
            <strong>Sistema conectado</strong>
            <small>Barbarian Inventory</small>
          </div>
        </footer>
      </aside>
    </>
  )
}
