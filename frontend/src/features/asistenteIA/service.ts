export interface EstadoAsistente {
  consultas_habilitadas?: boolean
  estado: 'disponible' | 'sin_configurar'
  ia_disponible: boolean
  dictado_disponible: boolean
  ejecucion_disponible: boolean
  capacidades?: Record<string, string[]>
  modulos_consultables: { nombre: string; ruta: string }[]
}
export interface Borrador {
  id_borrador: string
  recurso: string
  accion: string
  id: number | null
  datos: Record<string, unknown>
  vista: Record<string, unknown>
  anterior: Record<string, unknown> | null
}
export interface Consulta {
  recurso: string; total: number; desde: number; hay_mas: boolean
  registros: Record<string, unknown>[]
  contexto?: Record<string, unknown>
}
export type AgenteId = 'carta_recetas' | 'inventario' | 'compras' | 'recepcion' | 'eventos' | 'demanda' | 'categorias_carta' | 'menajes' | 'presentaciones' | 'subproductos' | 'recetas' | 'promociones'
export const nombresAgentes: Record<AgenteId | 'orquestador', string> = {
  carta_recetas: 'Catálogos y usuarios', inventario: 'Inventario', compras: 'Compras y reposición',
  recepcion: 'Recepción', eventos: 'Eventos cercanos', demanda: 'Demanda y rotación',
  categorias_carta: 'Categorías de carta', menajes: 'Menajes', presentaciones: 'Presentaciones de venta',
  subproductos: 'Subproductos', recetas: 'Recetas', promociones: 'Promociones', orquestador: 'Coordinador',
}
export interface RespuestaAsistente {
  respuesta: string; borrador: Borrador | null; consultas: Consulta[]
  agente?: AgenteId | 'orquestador'
  formulario?: FormularioCatalogo
  opciones?: { etiqueta: string; instruccion: string }[]
  continuacion?: string
  flujo_compra?: string
  tarea_pendiente?: string
  comunicaciones?: { de: AgenteId; a: AgenteId; motivo: string }[]
  actividad?: ActividadAgentes
  nota_actividad?: string
}
export interface ActividadAgentes {
  id: string; inicio: string; fin: string; entrada: string; url: string
  estado: string; agentes: string[]; respuesta_final: string; truncada: boolean; nota: string
  eventos: { paso: number; fecha: string; tipo: string; agente: string; de?: string; a?: string
    mensaje?: string; herramienta?: string; parametros?: unknown; resultado?: unknown; estado?: string }[]
}
export async function obtenerActividad(token: string, id: string): Promise<ActividadAgentes> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const response = await fetch(`${api}/asistente-ia/actividad/${encodeURIComponent(id)}`, { headers: { Authorization: `Bearer ${token}` } })
  const data = await response.json()
  if (!response.ok) throw new Error(data.mensaje ?? 'No se pudo descargar la actividad.')
  return data
}
export type RecursoFormulario = 'categorias_productos' | 'proveedores' | 'productos' | 'categorias_carta' | 'menajes' | 'presentaciones'
export interface FormularioCatalogo {
  recurso: RecursoFormulario
  titulo: string
  categorias: { id_categoria: number; nombre: string; prefijo: string; activo: boolean }[]
  proveedores: { id_proveedor: number; nombre: string; activo: boolean; ids_categorias: number[] }[]
  unidades_medida: { codigo: string; nombre: string; simbolo: string }[]
  categorias_proveedor_configurables: boolean
  dependencias_creables: RecursoFormulario[]
  menajes: { id_menaje: number; nombre: string; activo: boolean }[]
  items: { id_item_carta: number; nombre: string; tipo: string; id_categoria_carta: number; activo: boolean }[]
  tipos: string[]
}
export interface SkillAgente { nombre: string; archivo: string; contenido: string }
export interface DocumentoAgente { id: string; nombre: string; caracteres: number; subido_en: string; activo?: boolean; mime?: string; bytes?: number; original_disponible?: boolean }
export interface ConfiguracionAgente { instrucciones: string; skills: SkillAgente[]; accesos: Record<string, string[]> }
export interface InformeConfiguracion { resumen: string; informacion_faltante: string[]; accesos_necesarios: string[]; recomendaciones: string[]; conflictos: string[] }
export interface RevisionConfiguracion { revision_ia: string; informe: InformeConfiguracion; documentos_revisados: number; caracteres_revisados: number; revision: number; puede_guardar?: boolean }
export interface PropuestaSkill { contenido: string; resumen: string; informacion_faltante: string[]; archivo_skill: string; fuentes: string[]; revision: number }
export interface CarpetaAgente {
  id: string; nombre: string; descripcion: string; revision: number; documentos: DocumentoAgente[]
  instrucciones: string; instrucciones_base: string; skills: SkillAgente[]; limite_contexto: number; formatos: string[]; uso: string
  configuracion: ConfiguracionAgente; accesos_disponibles: Record<string, string[]>
  ultima_revision?: { informe: InformeConfiguracion; fecha: string; aplicado_por: number } | null
}
export async function bibliotecaAgentes<T>(token: string, path = '', method = 'GET', body?: object | FormData, signal?: AbortSignal): Promise<T> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const form = body instanceof FormData
  const response = await fetch(`${api}/asistente-ia/biblioteca${path}`, {
    method, signal, headers: { Authorization: `Bearer ${token}`, ...(!form && body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? form ? body : JSON.stringify(body) : undefined,
  })
  const result = await response.json()
  if (!response.ok) throw new Error(result.mensaje ?? 'No se pudo acceder a los archivos del agente.')
  return result as T
}
export async function originalDocumentoAgente(token: string, agent: string, document: string, signal?: AbortSignal): Promise<Blob> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const response = await fetch(`${api}/asistente-ia/biblioteca/${agent}/documentos/${document}/original`, { signal, headers: { Authorization: `Bearer ${token}` } })
  if (!response.ok) { const error = await response.json(); throw new Error(error.mensaje ?? 'No se pudo abrir el archivo.') }
  return response.blob()
}
export interface AgenteAsistente {
  id: AgenteId; nombre: string; descripcion: string
  relaciones: string[]; herramientas: string[]; recursos: string[]
  instrucciones: string; skills: SkillAgente[]
  recursos_modificables?: string[]; recursos_solo_consulta?: string[]
}
export interface CatalogoAgentes {
  administracion?: (Omit<AgenteAsistente, 'id'> & { id: 'actualizador_skills' | 'validador_skills' })[]
  conexiones?: ConexionAgentes[]
  coordinador: {
    id: string; nombre: string; descripcion: string; relaciones: string[]
    skills: SkillAgente[]; reglas_ruta: Record<string, string[]>
    instrucciones?: string
  }
  agentes: AgenteAsistente[]; limite_salon: string; regla_ejecucion: string
}
export interface ConexionAgentes {
  origen: AgenteId | 'orquestador'
  destino: AgenteId | 'orquestador'
  tipo: 'coordinacion' | 'dependencia'
}
export async function solicitar<T>(token: string, ruta: string, body: object | FormData, signal?: AbortSignal): Promise<T> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const form = body instanceof FormData
  const r = await fetch(`${api}/asistente-ia/${ruta}`, {
    method: 'POST', signal,
    headers: { Authorization: `Bearer ${token}`, ...(!form ? { 'Content-Type': 'application/json' } : {}) },
    body: form ? body : JSON.stringify(body),
  })
  let data
  try { data = await r.json() } catch { throw new Error('El servidor no respondió correctamente. Si confirmaste un cambio, revisa el módulo antes de repetirlo.') }
  if (!r.ok) throw new Error(data.mensaje ?? data.msg ?? 'No se pudo completar la solicitud.')
  return data
}
export async function obtenerAgentesAsistente(token: string, signal: AbortSignal): Promise<CatalogoAgentes> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const respuesta = await fetch(`${api}/asistente-ia/agentes`, {
    headers: { Authorization: `Bearer ${token}` }, signal,
  })
  const datos = await respuesta.json()
  if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo consultar el catálogo de agentes')
  return datos as CatalogoAgentes
}
export async function obtenerEstadoAsistente(token: string, signal: AbortSignal): Promise<EstadoAsistente> {
  const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
  const respuesta = await fetch(`${api}/asistente-ia/estado`, { headers: { Authorization: `Bearer ${token}` }, signal })
  const datos = await respuesta.json()
  if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo verificar el acceso')
  return datos
}
