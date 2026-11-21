import { AuthContext } from './authState'
import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'

import {
  cambiarLocalActivo as solicitarCambioLocal,
  cambiarPerfilActivo,
  iniciarSesion,
  obtenerSesion,
} from '../services/authService'
import type {
  LocalDisponible,
  OpcionMenu,
  PerfilDisponible,
  PuestoDisponible,
  RespuestaSesionActiva,
  Usuario,
} from '../types/auth'

interface AuthProviderProps {
  children: ReactNode
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [usuario, setUsuario] = useState<Usuario | null>(null)
  const [menu, setMenu] = useState<OpcionMenu[]>([])
  const [token, setToken] = useState<string | null>(null)
  const [perfilActivo, setPerfilActivo] =
    useState<PerfilDisponible | null>(null)
  const [perfilesDisponibles, setPerfilesDisponibles] =
    useState<PerfilDisponible[]>([])
  const [puestoActivo, setPuestoActivo] =
    useState<PuestoDisponible | null>(null)
  const [puestosDisponibles, setPuestosDisponibles] =
    useState<PuestoDisponible[]>([])
  const [localActivo, setLocalActivo] =
    useState<LocalDisponible | null>(null)
  const [localesDisponibles, setLocalesDisponibles] =
    useState<LocalDisponible[]>([])
  const [cargando, setCargando] = useState(true)
  const [cambiandoPerfil, setCambiandoPerfil] = useState(false)
  const [cambiandoLocal, setCambiandoLocal] = useState(false)
  const [identidadSesion, setIdentidadSesion] = useState({
    token: null as string | null,
    pendiente: false,
  })
  const sesionVigente = useRef(identidadSesion)
  const montado = useRef(true)

  function esSesionVigente(identidad: typeof identidadSesion) {
    return montado.current && sesionVigente.current === identidad
  }

  // Replace synchronously, before awaiting or rendering, to invalidate saved callbacks.
  function reemplazarIdentidad(tokenSesion: string | null, pendiente = false) {
    const identidad = { token: tokenSesion, pendiente }
    sesionVigente.current = identidad
    setIdentidadSesion(identidad)
    return identidad
  }

  function iniciarCambio() {
    const identidad = reemplazarIdentidad(sesionVigente.current.token, true)
    setCargando(false)
    setCambiandoPerfil(false)
    setCambiandoLocal(false)
    return identidad
  }

  function finalizarCambio(identidad: typeof identidadSesion) {
    if (!esSesionVigente(identidad)) return
    reemplazarIdentidad(identidad.token)
    setCambiandoPerfil(false)
    setCambiandoLocal(false)
  }

  function limpiarAlmacenamiento() {
    sessionStorage.removeItem('token')
    sessionStorage.removeItem('usuario')
    sessionStorage.removeItem('menu')
    sessionStorage.removeItem('perfil_activo')
    sessionStorage.removeItem('perfiles_disponibles')
    sessionStorage.removeItem('puesto_activo')
    sessionStorage.removeItem('puestos_disponibles')
    sessionStorage.removeItem('local_activo')
    sessionStorage.removeItem('locales_disponibles')
  }

  function limpiarSesion() {
    reemplazarIdentidad(null)
    limpiarAlmacenamiento()
    setCargando(false)
    setCambiandoPerfil(false)
    setCambiandoLocal(false)
    setToken(null)
    setUsuario(null)
    setMenu([])
    setPerfilActivo(null)
    setPerfilesDisponibles([])
    setPuestoActivo(null)
    setPuestosDisponibles([])
    setLocalActivo(null)
    setLocalesDisponibles([])
  }

  function aplicarSesion(
    respuesta: RespuestaSesionActiva,
    tokenSesion: string,
    identidad: typeof identidadSesion,
  ) {
    if (!esSesionVigente(identidad)) return
    reemplazarIdentidad(tokenSesion)
    setCargando(false)
    setCambiandoPerfil(false)
    setCambiandoLocal(false)
    sessionStorage.setItem('token', tokenSesion)
    sessionStorage.setItem('usuario', JSON.stringify(respuesta.usuario))
    sessionStorage.setItem('menu', JSON.stringify(respuesta.menu))
    sessionStorage.setItem(
      'perfil_activo',
      JSON.stringify(respuesta.perfil_activo),
    )
    sessionStorage.setItem(
      'perfiles_disponibles',
      JSON.stringify(respuesta.perfiles_disponibles),
    )
    sessionStorage.setItem(
      'puesto_activo',
      JSON.stringify(respuesta.puesto_activo),
    )
    sessionStorage.setItem(
      'puestos_disponibles',
      JSON.stringify(respuesta.puestos_disponibles),
    )
    sessionStorage.setItem(
      'local_activo',
      JSON.stringify(respuesta.local_activo),
    )
    sessionStorage.setItem(
      'locales_disponibles',
      JSON.stringify(respuesta.locales_disponibles),
    )

    setToken(tokenSesion)
    setUsuario(respuesta.usuario)
    setMenu(respuesta.menu)
    setPerfilActivo(respuesta.perfil_activo)
    setPerfilesDisponibles(respuesta.perfiles_disponibles)
    setPuestoActivo(respuesta.puesto_activo)
    setPuestosDisponibles(respuesta.puestos_disponibles)
    setLocalActivo(respuesta.local_activo)
    setLocalesDisponibles(respuesta.locales_disponibles)
  }

  useEffect(() => {
    montado.current = true

    async function restaurarSesion() {
      const tokenGuardado = sessionStorage.getItem('token')
      const identidad = reemplazarIdentidad(tokenGuardado, !!tokenGuardado)

      if (!tokenGuardado) {
        setCargando(false)
        return
      }

      try {
        const sesion = await obtenerSesion(tokenGuardado)
        aplicarSesion(sesion, tokenGuardado, identidad)
      } catch {
        if (esSesionVigente(identidad)) limpiarSesion()
      } finally {
        if (esSesionVigente(identidad)) setCargando(false)
      }
    }

    void restaurarSesion()
    return () => {
      montado.current = false
    }
  }, [])

  async function login(correo: string, clave: string) {
    if (!montado.current) return
    const identidad = iniciarCambio()
    try {
      const respuesta = await iniciarSesion(correo, clave)
      if (!esSesionVigente(identidad)) return

      if (!respuesta.token) {
        throw new Error('El servidor no devolvió un token de sesión')
      }

      aplicarSesion(respuesta, respuesta.token, identidad)
    } catch (error) {
      if (esSesionVigente(identidad)) throw error
    } finally {
      finalizarCambio(identidad)
    }
  }

  async function cambiarPerfil(
    idPerfil: number,
    idPuestoLaboral?: number,
  ) {
    if (!esSesionVigente(identidadSesion)) return
    if (!token) {
      throw new Error('No existe una sesión activa')
    }

    if (
      perfilActivo?.id_perfil === idPerfil &&
      (idPerfil !== 4 ||
        puestoActivo?.id_puesto_laboral === idPuestoLaboral)
    ) {
      return
    }

    const identidad = iniciarCambio()
    try {
      setCambiandoPerfil(true)
      const respuesta = await cambiarPerfilActivo(
        token,
        idPerfil,
        idPuestoLaboral,
      )
      if (!esSesionVigente(identidad)) return

      if (!respuesta.token) {
        throw new Error('El servidor no devolvió un token nuevo')
      }

      aplicarSesion(respuesta, respuesta.token, identidad)
    } catch (error) {
      if (esSesionVigente(identidad)) throw error
    } finally {
      finalizarCambio(identidad)
    }
  }

  async function cambiarLocal(idLocal: number) {
    if (!esSesionVigente(identidadSesion)) return
    if (!token) {
      throw new Error('No existe una sesión activa')
    }

    if (localActivo?.id_local === idLocal) return

    const identidad = iniciarCambio()
    try {
      setCambiandoLocal(true)
      const respuesta = await solicitarCambioLocal(token, idLocal)
      if (!esSesionVigente(identidad)) return

      if (!respuesta.token) {
        throw new Error('El servidor no devolvió un token nuevo')
      }

      aplicarSesion(respuesta, respuesta.token, identidad)
    } catch (error) {
      if (esSesionVigente(identidad)) throw error
    } finally {
      finalizarCambio(identidad)
    }
  }

  function logout() {
    if (!montado.current) return
    limpiarSesion()
  }

  async function actualizarSesion() {
    if (!token || !esSesionVigente(identidadSesion) || identidadSesion.pendiente) return
    try {
      const respuesta = await obtenerSesion(token)
      aplicarSesion(respuesta, token, identidadSesion)
    } catch (error) {
      if (esSesionVigente(identidadSesion)) throw error
    }
  }

  return (
    <AuthContext.Provider
      value={{
        usuario,
        menu,
        token,
        perfilActivo,
        perfilesDisponibles,
        puestoActivo,
        puestosDisponibles,
        localActivo,
        localesDisponibles,
        cargando,
        cambiandoPerfil,
        cambiandoLocal,
        login,
        cambiarPerfil,
        cambiarLocal,
        actualizarSesion,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}
