import { useEffect, useState } from 'react'
import { Outlet, Navigate, useLocation } from 'react-router-dom'

import { Sidebar } from './Sidebar'
import { Topbar } from './Topbar'
import { useAuth } from '../../context/AuthContext'

import './MainLayout.css'

export function MainLayout() {
  const { token, cambiandoLocal, cambiandoPerfil, perfilActivo } = useAuth()
  const { pathname } = useLocation()
  const bloqueado = ![2, 3, 4].includes(perfilActivo?.id_perfil ?? 0)
    && (pathname === '/home/stock' || ['/home/inventarios/', '/home/movimientos/', '/home/ordenes-compra/', '/home/recepciones/'].some(ruta => pathname.startsWith(ruta)))
  const [sidebarMovilAbierto, setSidebarMovilAbierto] =
    useState(false)
  useEffect(() => {
    const resize = () => { if (window.innerWidth > 920) setSidebarMovilAbierto(false) }
    window.addEventListener('resize', resize)
    return () => window.removeEventListener('resize', resize)
  }, [])

  return (
    <div className="main-layout">
      <a className="skip-link" href="#main-content">Saltar al contenido</a>
      <Sidebar
        abiertoEnMovil={sidebarMovilAbierto}
        cerrarEnMovil={() => setSidebarMovilAbierto(false)}
      />

      <div className="main-layout__right" inert={sidebarMovilAbierto}>
        <Topbar
          abrirMenu={() => setSidebarMovilAbierto(true)}
        />

        <div className="main-layout__content" id="main-content" tabIndex={-1}>
          {cambiandoLocal || cambiandoPerfil ? (
            <p role="status" className="session-loading">Cambiando sesión…</p>
          ) : (
            bloqueado ? <Navigate to="/home" replace /> : <Outlet key={token} />
          )}
        </div>
      </div>
    </div>
  )
}
