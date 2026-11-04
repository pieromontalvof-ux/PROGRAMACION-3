import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import {
  Building2,
  House,
  ChevronRight,
  ChevronDown,
  LogOut,
  Menu,
  Settings,
  UserRound,
} from 'lucide-react'

import { useAuth } from '../../context/AuthContext'

interface TopbarProps {
  abrirMenu: () => void
}

export function Topbar({ abrirMenu }: TopbarProps) {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const {
    usuario,
    menu,
    perfilActivo,
    perfilesDisponibles,
    puestoActivo,
    puestosDisponibles,
    localActivo,
    localesDisponibles,
    cambiandoPerfil,
    cambiandoLocal,
    cambiarPerfil,
    cambiarLocal,
    logout,
  } = useAuth()

  const [menuUsuarioAbierto, setMenuUsuarioAbierto] = useState(false)
  const [errorCambio, setErrorCambio] = useState('')
  const [perfilPendiente, setPerfilPendiente] = useState<number | null>(null)
  const contenedorUsuario = useRef<HTMLDivElement>(null)
  const cuentaButton = useRef<HTMLButtonElement>(null)

  const nombres = usuario?.nombres ?? ''
  const apellido = usuario?.apellido_paterno ?? ''
  const perfil = perfilActivo?.nombre ?? usuario?.perfil ?? ''
  const iniciales = `${nombres.charAt(0)}${apellido.charAt(0)}`
    .toUpperCase()
    .trim()
  const activeOption = [...menu].filter(option => option.url_menu && (pathname === option.url_menu || pathname.startsWith(option.url_menu + '/')))
    .sort((a, b) => (b.url_menu?.length ?? 0) - (a.url_menu?.length ?? 0))[0]
  const pageName = pathname === '/home/tiendas' ? 'Tiendas' : pathname === '/home/asistente-ia' ? 'Conversación'
    : pathname === '/home/asistente-ia/agentes' ? 'Mapa de agentes' : pathname === '/home/asistente-ia/archivos' ? 'Archivos de agentes'
    : pathname === '/home/asistente-ia/permisos' ? 'Permisos de agentes'
    : pathname === '/home/opciones-salon' ? 'Opciones de salón' : activeOption?.nombre ?? 'Inicio'
  const parentName = pathname.startsWith('/home/asistente-ia') ? 'Asistente IA' : pathname === '/home/tiendas' || pathname === '/home/usuarios' ? 'Organización'
    : menu.find(option => option.id_opcion_menu === activeOption?.id_padre)?.nombre

  useEffect(() => {
    const cerrarAlPulsarFuera = (evento: MouseEvent) => {
      if (
        contenedorUsuario.current &&
        !contenedorUsuario.current.contains(evento.target as Node)
      ) {
        setMenuUsuarioAbierto(false)
      }
    }

    document.addEventListener('mousedown', cerrarAlPulsarFuera)
    return () => document.removeEventListener('mousedown', cerrarAlPulsarFuera)
  }, [])
  useEffect(() => {
    if (!menuUsuarioAbierto) return
    const keyboard = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { setMenuUsuarioAbierto(false); cuentaButton.current?.focus() }
    }
    document.addEventListener('keydown', keyboard)
    return () => document.removeEventListener('keydown', keyboard)
  }, [menuUsuarioAbierto])

  const seleccionarOtroPerfil = async (
    idPerfil: number,
    idPuestoLaboral?: number,
  ) => {
    try {
      setErrorCambio('')
      await cambiarPerfil(idPerfil, idPuestoLaboral)
      setPerfilPendiente(null)
      setMenuUsuarioAbierto(false)
      navigate('/home', { replace: true })
    } catch (errorDesconocido) {
      setErrorCambio(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo cambiar el perfil',
      )
    }
  }

  const seleccionarOtroLocal = async (idLocal: number) => {
    if (!idLocal || idLocal === localActivo?.id_local) return

    try {
      setErrorCambio('')
      await cambiarLocal(idLocal)
      setMenuUsuarioAbierto(false)
      navigate('/home', { replace: true })
    } catch (errorDesconocido) {
      setErrorCambio(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo cambiar el local',
      )
    }
  }

  const cerrarSesion = () => {
    setMenuUsuarioAbierto(false)
    logout()
    navigate('/login', { replace: true })
  }

  return (
    <header className="topbar">
      <div className="topbar__left">
        <button
          className="topbar__menu-button"
          type="button"
          onClick={abrirMenu}
          aria-label="Abrir menú principal"
          aria-controls="main-sidebar"
        >
          <Menu aria-hidden="true" />
        </button>

        <nav className="topbar-breadcrumb" aria-label="Ubicación actual">
          <Link to="/home" aria-label="Inicio"><House size={20} aria-hidden="true" /></Link>
          {parentName && <><ChevronRight size={15} aria-hidden="true" /><span>{parentName}</span></>}
          {pathname !== '/home' && <><span aria-hidden="true">/</span><strong aria-current="page">{pageName}</strong></>}
          {pathname === '/home' && <strong aria-current="page">Inicio</strong>}
        </nav>
      </div>

      <div className="topbar-workspace-selectors">
        {perfilesDisponibles.length > 1 && <label className="topbar-role-select">
          <span>Rol:</span>
          <select aria-label="Rol de trabajo" value={perfilPendiente ?? perfilActivo?.id_perfil ?? ''}
            disabled={cambiandoPerfil || cambiandoLocal} onChange={event => {
              const id = Number(event.target.value)
              if (id === 4) setPerfilPendiente(4)
              else { setPerfilPendiente(null); void seleccionarOtroPerfil(id) }
            }}>
            {perfilesDisponibles.map(option => <option key={option.id_perfil} value={option.id_perfil}>{option.nombre}</option>)}
          </select>
        </label>}
        {(perfilPendiente === 4 || perfilActivo?.id_perfil === 4) && <label className="topbar-position-select">
          <span>Puesto:</span>
          <select aria-label="Puesto del miembro" value={perfilActivo?.id_perfil === 4 ? puestoActivo?.id_puesto_laboral ?? '' : ''}
            disabled={cambiandoPerfil || cambiandoLocal} onChange={event => {
              if (event.target.value) void seleccionarOtroPerfil(4, Number(event.target.value))
            }}>
            <option value="">Elegir puesto</option>
            {puestosDisponibles.map(position => <option key={position.id_puesto_laboral} value={position.id_puesto_laboral}>{position.nombre}</option>)}
          </select>
        </label>}
      </div>

      {[1, 2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) && <label className="topbar-local-selector">
        <Building2 aria-hidden="true" />
        <span className="topbar-local-selector__label">Local</span>
        <select
          value={localActivo?.id_local ?? ''}
          disabled={
            cambiandoLocal ||
            cambiandoPerfil ||
            localesDisponibles.length <= 1
          }
          onChange={(evento) =>
            void seleccionarOtroLocal(Number(evento.target.value))
          }
          aria-label="Local de trabajo"
        >
          {localesDisponibles.length === 0 && (
            <option value="">Sin local</option>
          )}
          {localesDisponibles.map((local) => (
            <option key={local.id_local} value={local.id_local}>
              {local.nombre}
            </option>
          ))}
        </select>
      </label>}

      <div className="topbar-user" ref={contenedorUsuario}>
        <button
          ref={cuentaButton}
          className="topbar-user__button"
          type="button"
          onClick={() => setMenuUsuarioAbierto((estado) => !estado)}
          aria-expanded={menuUsuarioAbierto}
          aria-controls="user-options"
          aria-label={`Cuenta de ${nombres} ${apellido}`}
        >
          <div className="topbar-user__information">
            <strong>{nombres} {apellido}</strong>
            <span>
              {perfil}
              {[2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) && localActivo ? ` · ${localActivo.nombre}` : ''}
            </span>
          </div>

          <div className="topbar-user__avatar">
            {iniciales || <UserRound aria-hidden="true" />}
          </div>

          <ChevronDown
            className={`topbar-user__arrow ${
              menuUsuarioAbierto ? 'topbar-user__arrow--open' : ''
            }`}
            aria-hidden="true"
          />
        </button>

        {menuUsuarioAbierto && (
          <div className="topbar-user__dropdown" id="user-options" role="region" aria-label="Opciones de usuario">
            <div className="topbar-user__summary">
              <div className="topbar-user__avatar topbar-user__avatar--large">
                {iniciales || <UserRound aria-hidden="true" />}
              </div>
              <div>
                <strong>{nombres} {apellido}</strong>
                <span>{usuario?.correo}</span>
                {[2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) && localActivo && <small>Local: {localActivo.nombre}</small>}
              </div>
            </div>

            {errorCambio && (
              <p className="topbar-profile-selector__error">
                {errorCambio}
              </p>
            )}

            <div className="topbar-user__separator" />
            {perfilesDisponibles.length > 1 && <div className="topbar-compact-profile">
              <div className="topbar-profile-selector" role="group" aria-label="Cambiar perfil de trabajo">
                <small>PERFIL DE TRABAJO</small>
                {perfilesDisponibles.filter(option => option.id_perfil !== 4).map(option =>
                  <button key={option.id_perfil} type="button" data-profile={option.id_perfil}
                    className={option.id_perfil === perfilActivo?.id_perfil ? 'is-active' : ''}
                    disabled={cambiandoPerfil || cambiandoLocal || option.id_perfil === perfilActivo?.id_perfil}
                    onClick={() => void seleccionarOtroPerfil(option.id_perfil)}>{option.nombre}</button>)}
                {perfilesDisponibles.some(option => option.id_perfil === 4) && <label>
                  <span>Miembro · puesto de trabajo</span>
                  <select aria-label="Puesto de trabajo" value={perfilActivo?.id_perfil === 4 ? puestoActivo?.id_puesto_laboral ?? '' : ''}
                    disabled={cambiandoPerfil || cambiandoLocal} onChange={event => {
                      if (event.target.value) void seleccionarOtroPerfil(4, Number(event.target.value))
                    }}>
                    <option value="">Elegir puesto</option>
                    {puestosDisponibles.map(position => <option key={position.id_puesto_laboral} value={position.id_puesto_laboral}>{position.nombre}</option>)}
                  </select>
                </label>}
              </div>
              <div className="topbar-user__separator" />
            </div>}

            <button
              type="button"
              onClick={() => {
                setMenuUsuarioAbierto(false)
                navigate('/home/configuracion')
              }}
            >
              <Settings aria-hidden="true" />
              Configuración
            </button>

            <button
              className="topbar-user__logout"
              type="button"
              onClick={cerrarSesion}
            >
              <LogOut aria-hidden="true" />
              Cerrar sesión
            </button>
          </div>
        )}
      </div>
    </header>
  )
}
