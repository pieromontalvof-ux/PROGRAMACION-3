import { StatusFilters } from '../components/catalogs/StatusFilters'
import {
  AlertTriangle,
  ChevronDown,
  RefreshCw,
  Search,
  Utensils,
} from 'lucide-react'
import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { useAuth } from '../context/authState'
import { obtenerMenajes, administrarMenaje, type AccionMenaje } from '../services/cartaService'
import type { RespuestaMenajes, MenajeDetalle, UnidadCapacidad } from '../types/carta'
import { CatalogDialog } from '../components/catalogs/CatalogDialog'
import { permisosDe } from '../utils/permissionHelpers'

import './CartaCatalogPages.css'

type EstadoFiltro = 'todos' | 'activos' | 'inactivos'

const unidadesCapacidad: Record<UnidadCapacidad, { nombre: string; factor: number }> = {
  MLT: { nombre: 'mL', factor: 1 },
  LTR: { nombre: 'L', factor: 1000 },
  FLOZ_US: { nombre: 'Onzas líquidas (oz)', factor: 29.5735295625 },
  FLOZ_UK: { nombre: 'fl oz (imperiales)', factor: 28.4130625 },
}
const formatearMedida = (valor: number) => valor.toLocaleString('es-ES', { maximumFractionDigits: 2, useGrouping: false })

function medidasTexto(item: MenajeDetalle) {
  const capacidad = item.capacidad != null && item.unidad_capacidad
    ? `${formatearMedida(item.capacidad)} ${unidadesCapacidad[item.unidad_capacidad].nombre}` : null
  const dimensiones = [item.diametro_cm != null ? `Ø ${formatearMedida(item.diametro_cm)} cm` : null,
    item.largo_cm != null ? `largo ${formatearMedida(item.largo_cm)} cm` : null,
    item.ancho_cm != null ? `ancho ${formatearMedida(item.ancho_cm)} cm` : null,
    item.altura_cm != null ? `alto ${formatearMedida(item.altura_cm)} cm` : null].filter(Boolean).join(' · ')
  return [capacidad, dimensiones].filter(Boolean)
}

export function TablewarePage() {
  const { token, menu, perfilActivo } = useAuth()
  const permisos = permisosDe(menu, 10)
  const administrador = perfilActivo?.id_perfil === 1
  const [operacion, setOperacion] = useState<{ accion: AccionMenaje; item?: MenajeDetalle } | null>(null)
  const [nombre, setNombre] = useState('')
  const [capacidad, setCapacidad] = useState('')
  const [capacidadEditada, setCapacidadEditada] = useState(false)
  const [unidadCapacidad, setUnidadCapacidad] = useState<UnidadCapacidad>('MLT')
  const [diametro, setDiametro] = useState('')
  const [altura, setAltura] = useState('')
  const [largo, setLargo] = useState('')
  const [ancho, setAncho] = useState('')
  const [procesando, setProcesando] = useState(false)
  const [errorModal, setErrorModal] = useState('')
  const [mensaje, setMensaje] = useState('')
  function abrir(accion: AccionMenaje, item?: MenajeDetalle) {
    setOperacion({ accion, item }); setNombre(item?.nombre ?? ''); setErrorModal(''); setMensaje('')
    setCapacidad(item?.capacidad?.toString() ?? '')
    setCapacidadEditada(false)
    setUnidadCapacidad(item?.unidad_capacidad ?? 'MLT')
    setDiametro(item?.diametro_cm?.toString() ?? '')
    setAltura(item?.altura_cm?.toString() ?? '')
    setLargo(item?.largo_cm?.toString() ?? '')
    setAncho(item?.ancho_cm?.toString() ?? '')
    if (item?.unidad_capacidad === 'FLOZ_UK' && item.capacidad != null) {
      setCapacidad((item.capacidad * unidadesCapacidad.FLOZ_UK.factor).toFixed(3))
      setUnidadCapacidad('MLT')
    }
  }
  async function guardar() {
    if (!token || !operacion || procesando) return
    const editandoMedidas = operacion.accion === 'crear' || operacion.accion === 'editar'
    if (editandoMedidas && [capacidad, diametro, altura, largo, ancho].some(valor => valor !== '' && (!Number.isFinite(Number(valor)) || Number(valor) <= 0))) {
      setErrorModal('Las medidas deben ser números mayores que cero o quedar vacías.')
      return
    }
    setProcesando(true); setErrorModal('')
    try {
      const medidas = editandoMedidas ? {
        capacidad: capacidad === '' ? null : Number(capacidad),
        unidad_capacidad: capacidad === '' ? null : unidadCapacidad,
        diametro_cm: diametro === '' ? null : Number(diametro),
        altura_cm: altura === '' ? null : Number(altura),
        largo_cm: largo === '' ? null : Number(largo),
        ancho_cm: ancho === '' ? null : Number(ancho),
      } : undefined
      if (medidas && !capacidadEditada && operacion.item?.unidad_capacidad === 'FLOZ_UK') {
        medidas.capacidad = operacion.item.capacidad ?? null
        medidas.unidad_capacidad = 'FLOZ_UK'
      }
      const respuesta = await administrarMenaje(token, operacion.accion, nombre, operacion.item?.id_menaje, medidas)
      setOperacion(null); setMensaje(respuesta.mensaje); setAbierto(null)
      await cargar(true)
    } catch (e) { setErrorModal(e instanceof Error ? e.message : 'No se pudo guardar') }
    finally { setProcesando(false) }
  }
  const [datos, setDatos] =
    useState<RespuestaMenajes | null>(null)
  const [busqueda, setBusqueda] = useState('')
  const [estado, setEstado] =
    useState<EstadoFiltro>('todos')
  const [abierto, setAbierto] = useState<number | null>(null)
  const [cargando, setCargando] = useState(true)
  const [actualizando, setActualizando] = useState(false)
  const [error, setError] = useState('')

  const cargar = useCallback(
    async (actualizacion = false) => {
      if (!token) {
        setError('No existe una sesión válida.')
        setCargando(false)
        return
      }

      try {
        setError('')
        if (actualizacion) setActualizando(true)
        else setCargando(true)
        setDatos(await obtenerMenajes(token))
      } catch (desconocido) {
        setError(
          desconocido instanceof Error
            ? desconocido.message
            : 'No se pudieron cargar los menajes.',
        )
      } finally {
        setCargando(false)
        setActualizando(false)
      }
    },
    [token],
  )

  useEffect(() => {
    void cargar()
  }, [cargar])

  const filtrados = useMemo(() => {
    const texto = busqueda.trim().toLocaleLowerCase('es')

    return (datos?.menajes ?? []).filter((item) => {
      const coincideTexto =
        !texto ||
        item.nombre.toLocaleLowerCase('es').includes(texto) ||
        item.items.some((nombre) =>
          nombre.toLocaleLowerCase('es').includes(texto),
        )

      const coincideEstado =
        estado === 'todos' ||
        (estado === 'activos' && item.activo) ||
        (estado === 'inactivos' && !item.activo)

      return coincideTexto && coincideEstado
    })
  }, [busqueda, datos, estado])

  if (cargando) {
    return (
      <section className="carta-catalog-state">
        <RefreshCw className="carta-catalog-spin" />
        <div>
          <h1>Cargando menajes</h1>
          <p>Consultando los formatos de servicio.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="carta-catalog-state carta-catalog-state--error">
        <AlertTriangle />
        <div>
          <h1>No se pudieron cargar los menajes</h1>
          <p>{error}</p>
          <button type="button" onClick={() => void cargar()}>
            Intentar nuevamente
          </button>
        </div>
      </section>
    )
  }

  if (!datos) return null

  return (
    <section className="carta-catalog-page tableware-page">
      <header className="carta-catalog-header">
        <div>
          <span className="carta-catalog-eyebrow">
            CATÁLOGO DE VENTA
          </span>
          <h1>Menajes <span className="catalog-title-count">{datos.resumen.total_menajes} menajes</span></h1>
          <p>
            Consulta los recipientes y formatos utilizados
            para servir las presentaciones de la carta.
          </p>
        </div>
      </header>

      <div className="catalog-overview-tools">
        <StatusFilters value={estado} onChange={setEstado} options={[
          { value: 'todos', label: 'Todos', count: datos.resumen.total_menajes },
          { value: 'activos', label: 'Activos', count: datos.resumen.menajes_activos },
          { value: 'inactivos', label: 'Inactivos', count: datos.resumen.menajes_inactivos },
        ]} />
        <div className="catalog-admin-actions">
        {administrador && permisos.crear && <button className="catalog-admin-new" type="button" onClick={() => abrir('crear')}>Nuevo menaje</button>}
        <button
          className="carta-catalog-refresh"
          type="button"
          disabled={actualizando}
          onClick={() => void cargar(true)}
        >
          <RefreshCw className={actualizando ? 'carta-catalog-spin' : ''} />
          {actualizando ? 'Actualizando...' : 'Actualizar'}
        </button>
        </div>
      </div>

      <section className="carta-catalog-content" title="Para desactivar o eliminar un menaje, cambia primero el menaje de todas sus presentaciones en Carta → Presentaciones de venta, incluidas las inactivas.">
        {mensaje && <p role="status">{mensaje}</p>}
        {error && <p role="alert">{error}</p>}

        <div className="carta-catalog-filters">
          <label>
            <Search />
            <input
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              placeholder="Buscar menaje o artículo asociado"
            />
          </label>
          <button
            type="button"
            onClick={() => {
              setBusqueda('')
              setEstado('todos')
            }}
          >
            Limpiar
          </button>
        </div>

        <div className="carta-catalog-table-wrap" role="region" aria-label="Listado de menajes" tabIndex={0}>
          <table className="carta-catalog-table">
            <thead>
              <tr>
                <th>Menaje</th>
                <th>Ítems asociados</th>
                <th>Presentaciones</th>
                <th>Activas</th>
                <th>Inactivas</th>
                <th>Estado</th>
                <th>Detalle</th>
                {administrador && <th>Acciones</th>}
              </tr>
            </thead>
            <tbody>
              {filtrados.map((item) => {
                const estaAbierto = abierto === item.id_menaje

                return (
                  <Fragment key={item.id_menaje}>
                    <tr>
                      <td>
                        <span className="carta-name-icon">
                          <Utensils />
                          <strong>{item.nombre}</strong>
                        </span>
                        <div>{medidasTexto(item).length ? medidasTexto(item).map(medida => <div key={medida}><small>{medida}</small></div>) : <small>Sin registrar</small>}</div>
                        {item.origen_medidas === 'DEMO' && <small>Medidas de ejemplo</small>}
                      </td>
                      <td>{item.total_items}</td>
                      <td><strong>{item.total_presentaciones}</strong></td>
                      <td><span className="carta-count active">{item.presentaciones_activas}</span></td>
                      <td><span className="carta-count inactive">{item.presentaciones_inactivas}</span></td>
                      <td>
                        <span className={item.activo ? 'carta-status active' : 'carta-status inactive'}>
                          {item.activo ? 'Activo' : 'Inactivo'}
                        </span>
                      </td>
                      <td>
                        <button
                          className="carta-detail-button"
                          type="button"
                          aria-expanded={estaAbierto}
                          aria-label={`${estaAbierto ? 'Ocultar' : 'Ver'} artículos de ${item.nombre}`}
                          onClick={() =>
                            setAbierto(
                              estaAbierto ? null : item.id_menaje,
                            )
                          }
                        >
                          <ChevronDown className={estaAbierto ? 'open' : ''} />
                        </button>
                      </td>
                      {administrador && <td><div className="catalog-admin-actions">
                        {permisos.editar && <button type="button" onClick={() => abrir('editar', item)}>Editar</button>}
                        {item.activo && permisos.desactivar && <button type="button" className="danger" disabled={item.total_presentaciones > 0} title={item.total_presentaciones > 0 ? 'Tiene presentaciones asignadas' : 'Desactivar menaje'} onClick={() => abrir('desactivar', item)}>Desactivar</button>}
                        {!item.activo && permisos.reactivar && <button type="button" onClick={() => abrir('reactivar', item)}>Reactivar</button>}
                        {permisos.eliminar && <button type="button" className="danger" disabled={item.total_presentaciones > 0} title={item.total_presentaciones > 0 ? 'Tiene presentaciones asignadas' : 'Eliminar menaje'} onClick={() => abrir('eliminar', item)}>Eliminar</button>}
                      </div></td>}
                    </tr>
                    {estaAbierto && (
                      <tr className="carta-detail-row">
                        <td colSpan={administrador ? 8 : 7}>
                          <div className="carta-detail-content">
                            <strong>Artículos que utilizan {item.nombre}</strong>
                            <div>
                              {item.items.length ? (
                                item.items.map((nombre) => (
                                  <span key={nombre}>{nombre}</span>
                                ))
                              ) : (
                                <p>No tiene artículos asociados.</p>
                              )}
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                )
              })}
              {filtrados.length === 0 && (
                <tr>
                  <td colSpan={administrador ? 8 : 7} className="carta-empty">
                    No se encontraron menajes.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
      <CatalogDialog abierto={!!operacion} procesando={procesando} titulo={operacion?.accion === 'crear' ? 'Nuevo menaje' : operacion?.accion === 'editar' ? 'Editar menaje' : operacion?.accion === 'eliminar' ? 'Eliminar menaje' : operacion?.accion === 'reactivar' ? 'Reactivar menaje' : 'Desactivar menaje'} guardar={guardar} cerrar={() => setOperacion(null)}>
        {errorModal && <p role="alert">{errorModal}</p>}
          {operacion?.item?.origen_medidas === 'DEMO' && <p>Estas medidas son de ejemplo. Puedes reemplazarlas por las medidas reales de tu menaje.</p>}
        {operacion?.accion === 'crear' || operacion?.accion === 'editar' ? <>
          <label>Nombre del menaje<input required maxLength={100} value={nombre} onChange={e => setNombre(e.target.value)} /></label>
          <label>Capacidad (opcional)<input type="number" min="0" step="any" value={capacidad} onChange={e => { setCapacidad(e.target.value); setCapacidadEditada(true) }} aria-describedby="menaje-capacidad-ayuda" /></label>
          <label>Unidad de capacidad<select value={unidadCapacidad} onChange={e => { setUnidadCapacidad(e.target.value as UnidadCapacidad); setCapacidadEditada(true) }}>
            {Object.entries(unidadesCapacidad).filter(([codigo]) => codigo !== 'FLOZ_UK').map(([codigo, unidad]) => <option key={codigo} value={codigo}>{unidad.nombre}</option>)}
          </select></label>
          <p id="menaje-capacidad-ayuda">{capacidad !== '' && Number.isFinite(Number(capacidad)) && Number(capacidad) > 0
            ? `Equivalencia: ${formatearMedida(Number(capacidad) * unidadesCapacidad[unidadCapacidad].factor)} mL. ` : ''}fl oz indica volumen, no onzas de peso.</p>
          <label>Diámetro en cm (opcional)<input type="number" min="0" step="any" value={diametro} onChange={e => setDiametro(e.target.value)} /></label>
          <label>Altura en cm (opcional)<input type="number" min="0" step="any" value={altura} onChange={e => setAltura(e.target.value)} /></label>
          <label>Largo en cm (opcional)<input type="number" min="0" step="any" value={largo} onChange={e => setLargo(e.target.value)} /></label>
          <label>Ancho en cm (opcional)<input type="number" min="0" step="any" value={ancho} onChange={e => setAncho(e.target.value)} /></label>
          <p>Para bandejas y tablas rectangulares usa largo y ancho. La capacidad corresponde a líquidos; puedes dejarla vacía.</p>
          {operacion.item && operacion.item.total_presentaciones > 0 && <p>El nuevo nombre aparecerá en todas las presentaciones asociadas.</p>}
        </> : <p>Confirma que deseas {operacion?.accion} <strong>{operacion?.item?.nombre}</strong>. {operacion?.accion === 'eliminar' && 'Se borrará el menaje del catálogo.'}</p>}
      </CatalogDialog>
    </section>
  )
}
