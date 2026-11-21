import { createContext, useContext } from 'react'
import type { LocalDisponible, OpcionMenu, PerfilDisponible, PuestoDisponible, Usuario } from '../types/auth'

interface AuthContextType {
  usuario: Usuario | null
  menu: OpcionMenu[]
  token: string | null
  perfilActivo: PerfilDisponible | null
  perfilesDisponibles: PerfilDisponible[]
  puestoActivo: PuestoDisponible | null
  puestosDisponibles: PuestoDisponible[]
  localActivo: LocalDisponible | null
  localesDisponibles: LocalDisponible[]
  cargando: boolean
  cambiandoPerfil: boolean
  cambiandoLocal: boolean
  login: (correo: string, clave: string) => Promise<void>
  cambiarPerfil: (
    idPerfil: number,
    idPuestoLaboral?: number,
  ) => Promise<void>
  cambiarLocal: (idLocal: number) => Promise<void>
  actualizarSesion: () => Promise<void>
  logout: () => void
}

export const AuthContext = createContext<AuthContextType | undefined>(
  undefined,
)

export function useAuth() {
  const contexto = useContext(AuthContext)

  if (!contexto) {
    throw new Error('useAuth debe utilizarse dentro de AuthProvider')
  }

  return contexto
}
