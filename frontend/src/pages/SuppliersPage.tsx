import { useScopedCatalog } from '../hooks/useScopedCatalog'
import { StatusFilters } from '../components/catalogs/StatusFilters'
import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  ChevronDown,
  Layers3,
  RefreshCw,
  Search,
  Truck,
} from 'lucide-react'

import {
  Fragment,
  useMemo,
  useState,
} from 'react'

import { CatalogDialog } from '../components/catalogs/CatalogDialog'
import { useAuth } from '../context/authState'
import {
  cambiarEstadoProveedor,
  consultarDependenciasProveedor,
  crearProveedor,
  consultarRucProveedor,
  editarProveedor,
  obtenerProveedores,
  reasignarProveedor,
} from '../services/catalogService'
import type {
  ProveedorDetalle,
  DatosComercialesProveedor,
  RespuestaProveedores,
} from '../types/catalog'
import { permisosDe } from '../utils/permissionHelpers'

import './SuppliersPage.css'

type FiltroEstado = 'todos' | 'activos' | 'inactivos'

export function SuppliersPage() {
  const { token, menu, perfilActivo } = useAuth()
  const permisos = permisosDe(menu, 6)
  const administrador = perfilActivo?.id_perfil === 1
  const mostrarAcciones = administrador || (
    permisos.editar || permisos.configurar || permisos.desactivar || permisos.reactivar || permisos.eliminar
  )

  const [modal, setModal] = useState(false)
  const [proveedorEditado, setProveedorEditado] =
    useState<ProveedorDetalle | null>(null)
  const [nombre, setNombre] = useState('')
  const [comercial, setComercial] = useState<DatosComercialesProveedor>({})
  const [consultandoRuc, setConsultandoRuc] = useState(false)
  const [idsCategorias, setIdsCategorias] = useState<number[]>([])
  const [procesando, setProcesando] = useState(false)


  const [busqueda, setBusqueda] = useState('')
  const [estado, setEstado] =
    useState<FiltroEstado>('todos')


  const [proveedorAbierto, setProveedorAbierto] =
  useState<number | null>(null)

  const {datos, cargando, actualizando, setActualizando, error, setError, cargar: cargarProveedores} = useScopedCatalog<RespuestaProveedores>(token, obtenerProveedores, 'No se pudieron cargar los proveedores.')

  const proveedoresFiltrados = useMemo(() => {
    if (!datos) {
      return []
    }

    const texto = busqueda
      .trim()
      .toLocaleLowerCase('es')

    return datos.proveedores.filter((proveedor) => {
      const coincideBusqueda =
        texto === '' ||
        proveedor.nombre
          .toLocaleLowerCase('es')
          .includes(texto)

      const coincideEstado =
        estado === 'todos' ||
        (estado === 'activos' && proveedor.activo) ||
        (estado === 'inactivos' && !proveedor.activo)

      return coincideBusqueda && coincideEstado
    })
  }, [busqueda, datos, estado])

  function limpiarFiltros() {
    setBusqueda('')
    setEstado('todos')
  }

  function abrirProveedor(proveedor?: ProveedorDetalle) {
    setError('')
    setProveedorEditado(proveedor ?? null)
    setNombre(proveedor?.nombre ?? '')
    setComercial(proveedor?.datos_comerciales ?? {})
    setIdsCategorias(proveedor?.ids_categorias ?? [])
    setModal(true)
  }

  async function guardarProveedor() {
    if (!datos?.categorias_proveedor_configurables) {
      setError('Falta completar la actualización de proveedores en PostgreSQL para guardar sus categorías.')
      return
    }
    if (!token) {
      setError('No existe una sesión válida.')
      return
    }

    const nombreLimpio = nombre.trim()
    if (!idsCategorias.length) {
      setError('Selecciona una o varias categorías.')
      return
    }
    if (!nombreLimpio) {
      setError('Ingresa el nombre del proveedor.')
      return
    }

    try {
      setError('')
      setProcesando(true)

      if (proveedorEditado) {
        await editarProveedor(
          token,
          proveedorEditado.id_proveedor,
          { nombre: nombreLimpio, ids_categorias: idsCategorias, datos_comerciales: comercial },
        )
      } else {
        await crearProveedor(token, { nombre: nombreLimpio, ids_categorias: idsCategorias, datos_comerciales: comercial })
      }

      setModal(false)
      await cargarProveedores(true)
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo guardar el proveedor.',
      )
    } finally {
      setProcesando(false)
    }
  }

  async function reasignarProductos(
    proveedor: ProveedorDetalle,
  ) {
    if (!token) return

    try {
      setError('')
      const dependencia =
        await consultarDependenciasProveedor(
          token,
          proveedor.id_proveedor,
        )

      const productosActivos = dependencia.productos.filter(
        (producto) => producto.activo,
      )

      if (productosActivos.length === 0) {
        window.alert(
          'Este proveedor no tiene productos activos para reasignar.',
        )
        return
      }

      const destinos = datos?.proveedores.filter(
        (item) =>
          item.activo &&
          item.id_proveedor !== proveedor.id_proveedor,
      ) ?? []

      if (destinos.length === 0) {
        setError(
          'No existe otro proveedor activo para realizar la reasignación.',
        )
        return
      }

      const opciones = destinos
        .map((item) => `${item.id_proveedor}: ${item.nombre}`)
        .join('\n')

      const idDestino = window.prompt(
        `Escribe el ID del proveedor destino:\n\n${opciones}`,
      )

      if (idDestino === null) return

      const destino = destinos.find(
        (item) => item.id_proveedor === Number(idDestino),
      )

      if (!destino) {
        setError('Selecciona un ID de proveedor destino válido.')
        return
      }

      const motivo = window.prompt(
        `Motivo para reasignar los productos a ${destino.nombre}:`,
      )

      if (!motivo || motivo.trim().length < 10) {
        setError('El motivo debe tener al menos 10 caracteres.')
        return
      }

      if (!window.confirm(
        `¿Reasignar ${productosActivos.length} producto(s) a ${destino.nombre}?`,
      )) return

      setActualizando(true)
      await reasignarProveedor(token, proveedor.id_proveedor, {
        id_proveedor_nuevo: destino.id_proveedor,
        ids_productos: productosActivos.map(
          (producto) => producto.id_producto,
        ),
        motivo: motivo.trim(),
      })

      await cargarProveedores(true)
      window.alert(
        'Los productos fueron reasignados. Ya puedes desactivar el proveedor.',
      )
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudieron reasignar los productos.',
      )
    } finally {
      setActualizando(false)
    }
  }

  async function cambiarEstado(
    proveedor: ProveedorDetalle,
  ) {
    if (!token) return

    try {
      setError('')

      if (proveedor.activo) {
        const dependencia =
          await consultarDependenciasProveedor(
            token,
            proveedor.id_proveedor,
          )

        if (dependencia.productos_activos > 0) {
          setError(
            'El proveedor tiene productos activos. Debes reasignarlos o desactivarlos primero.',
          )
          return
        }
      }

      const accion = proveedor.activo
        ? 'desactivar'
        : 'reactivar'
      const motivo = window.prompt(
        `Motivo para ${accion} ${proveedor.nombre}:`,
      )

      if (!motivo || motivo.trim().length < 10) {
        setError('El motivo debe tener al menos 10 caracteres.')
        return
      }

      if (!window.confirm('¿Confirmas esta operación?')) return

      setActualizando(true)
      await cambiarEstadoProveedor(
        token,
        proveedor.id_proveedor,
        !proveedor.activo,
        motivo.trim(),
      )
      await cargarProveedores(true)
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo cambiar el estado del proveedor.',
      )
    } finally {
      setActualizando(false)
    }
  }

  if (cargando) {
    return (
      <section className="suppliers-state">
        <RefreshCw
          className="suppliers-spinner"
          aria-hidden="true"
        />

        <div>
          <h1>Cargando proveedores</h1>
          <p>Consultando la información registrada.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="suppliers-state suppliers-state--error">
        <AlertTriangle aria-hidden="true" />

        <div>
          <h1>No se pudieron cargar los proveedores</h1>
          <p>{error}</p>

          <button
            type="button"
            onClick={() => void cargarProveedores()}
          >
            Intentar nuevamente
          </button>
        </div>
      </section>
    )
  }

  if (!datos) {
    return null
  }

  const hayFiltros =
    busqueda.trim() !== '' || estado !== 'todos'

  return (
    <section className="suppliers-page">
      <header className="suppliers-header">
        <div className="suppliers-header__content">
          <span className="suppliers-header__eyebrow">
            CATÁLOGO DE INVENTARIO
          </span>

          <h1>Proveedores <span className="catalog-title-count">{datos.resumen.total_proveedores} proveedores</span></h1>

          <p>
            Consulta los proveedores vinculados a los
            productos utilizados por el establecimiento.
          </p>
        </div>

      </header>

      <div className="catalog-overview-tools">
        <StatusFilters value={estado} onChange={setEstado} options={[
          { value: 'todos', label: 'Todos', count: datos.resumen.total_proveedores },
          { value: 'activos', label: 'Activos', count: datos.resumen.proveedores_activos },
          { value: 'inactivos', label: 'Inactivos', count: datos.resumen.proveedores_inactivos },
        ]} />
        <div className="catalog-admin-actions">
          {(administrador || permisos.crear) && (
            <button
              className="catalog-admin-new"
              type="button"
              onClick={() => abrirProveedor()}
            >
              Nuevo proveedor
            </button>
          )}

          <button
            className="suppliers-refresh"
            type="button"
            disabled={actualizando}
            onClick={() => void cargarProveedores(true)}
          >
          <RefreshCw
            className={
              actualizando ? 'suppliers-spinner' : ''
            }
            aria-hidden="true"
          />

          {actualizando
            ? 'Actualizando...'
            : 'Actualizar proveedores'}
          </button>
        </div>
      </div>

      {!datos.categorias_proveedor_configurables && (
        <div className="suppliers-warning" role="status">
          Los proveedores están disponibles para consulta. Para asignar sus categorías,
          falta completar la actualización de la base de datos.
        </div>
      )}

      {error && (
        <div className="suppliers-warning" role="alert">
          <AlertTriangle aria-hidden="true" />
          {error}
        </div>
      )}

      <section className="suppliers-content">

        <div className="suppliers-filters">
          <label className="suppliers-search">
            <Search aria-hidden="true" />

            <input
              type="search"
              value={busqueda}
              onChange={(evento) =>
                setBusqueda(evento.target.value)
              }
              placeholder="Buscar proveedor"
              aria-label="Buscar proveedores"
            />
          </label>

<button
            className="suppliers-clear"
            type="button"
            disabled={!hayFiltros}
            onClick={limpiarFiltros}
          >
            Limpiar
          </button>
        </div>

        <div className="suppliers-table-container">
          <table className="suppliers-table">
            <thead>
              <tr>
                <th>Proveedor</th>
                <th>Categorías atendidas</th>
                <th>Total de productos</th>
                <th>Productos activos</th>
                <th>Productos inactivos</th>
                <th>Estado</th>
                {mostrarAcciones && <th>Acciones</th>}
              </tr>
            </thead>

            <tbody>
                {proveedoresFiltrados.map((proveedor) => {
                    const estaAbierto =
                    proveedorAbierto === proveedor.id_proveedor

                    return (
                    <Fragment key={proveedor.id_proveedor}>
                        <tr>
                        <td>
                            <div className="suppliers-name">
                            <span>
                                <Truck aria-hidden="true" />
                            </span>

                            <strong>{proveedor.nombre}</strong>
                            <small>{proveedor.datos_comerciales?.ruc}</small>
                            </div>
                        </td>

                        <td>
                            <button
                            className="suppliers-categories-button"
                            type="button"
                            aria-expanded={estaAbierto}
                            onClick={() =>
                                setProveedorAbierto(
                                estaAbierto
                                    ? null
                                    : proveedor.id_proveedor,
                                )
                            }
                            >
                            <Layers3 aria-hidden="true" />

                            <span>
                                {proveedor.total_categorias}
                                {' '}
                                {proveedor.total_categorias === 1
                                ? 'categoría'
                                : 'categorías'}
                            </span>

                            <ChevronDown
                                className={
                                estaAbierto
                                    ? 'suppliers-chevron suppliers-chevron--open'
                                    : 'suppliers-chevron'
                                }
                                aria-hidden="true"
                            />
                            </button>
                        </td>

                        <td>
                            <strong>
                            {proveedor.total_productos}
                            </strong>
                        </td>

                        <td>
                            <span className="suppliers-count suppliers-count--active">
                            {proveedor.productos_activos}
                            </span>
                        </td>

                        <td>
                            <span className="suppliers-count suppliers-count--inactive">
                            {proveedor.productos_inactivos}
                            </span>
                        </td>

                        <td>
                            <span
                            className={
                                proveedor.activo
                                ? 'suppliers-status suppliers-status--active'
                                : 'suppliers-status suppliers-status--inactive'
                            }
                            >
                            {proveedor.activo
                                ? 'Activo'
                                : 'Inactivo'}
                            </span>
                        </td>

                        {mostrarAcciones && <td>
                          <div className="catalog-admin-actions">
                            {(administrador || permisos.editar) && <button
                              type="button"
                              onClick={() => abrirProveedor(proveedor)}
                            >Editar</button>}
                            {(administrador || permisos.eliminar) && <DeleteRecordButton token={token} entidad="proveedores" id={proveedor.id_proveedor} nombre={proveedor.nombre} eliminado={() => void cargarProveedores(true)} />}
                            {proveedor.activo && (administrador || permisos.configurar) && <button
                              type="button"
                              onClick={() => void reasignarProductos(proveedor)}
                            >Reasignar</button>}
                            {(proveedor.activo ? (administrador || permisos.desactivar) : (administrador || permisos.reactivar)) && <button
                              className={proveedor.activo ? 'danger' : ''}
                              type="button"
                              onClick={() => void cambiarEstado(proveedor)}
                            >{proveedor.activo ? 'Desactivar' : 'Reactivar'}</button>}
                          </div>
                        </td>}
                        </tr>

                        {estaAbierto && (
                        <tr className="suppliers-detail-row">
                            <td colSpan={mostrarAcciones ? 7 : 6}>
                            <dl className="supplier-commercial-summary">{Object.entries(proveedor.datos_comerciales ?? {}).filter(([,v]) => v).map(([k,v]) => <div key={k}><dt>{k.replaceAll('_',' ')}</dt><dd>{v}</dd></div>)}</dl>
                            <div className="suppliers-detail">
                                <div className="suppliers-detail__title">
                                <Layers3 aria-hidden="true" />

                                <div>
                                    <strong>
                                    Categorías atendidas
                                    </strong>

                                    <span>
                                    Categorías asignadas al proveedor.
                                    </span>
                                </div>
                                </div>

                                <div className="suppliers-category-list">
                                {proveedor.categorias.length > 0 ? (
                                    proveedor.categorias.map(
                                    (nombreCategoria) => (
                                        <span key={nombreCategoria}>
                                        {nombreCategoria}
                                        </span>
                                    ),
                                    )
                                ) : (
                                    <p>
                                    Este proveedor todavía no tiene
                                    categorías asociadas.
                                    </p>
                                )}
                                </div>
                            </div>
                            </td>
                        </tr>
                        )}
                    </Fragment>
                    )
                })}

                {proveedoresFiltrados.length === 0 && (
                    <tr>
                    <td colSpan={mostrarAcciones ? 7 : 6}>
                        <div className="suppliers-empty">
                        <Truck aria-hidden="true" />

                        <strong>
                            No se encontraron proveedores
                        </strong>

                        <span>
                            Modifica o limpia los filtros.
                        </span>
                        </div>
                    </td>
                    </tr>
                )}
                </tbody>
          </table>
        </div>
      </section>

      <CatalogDialog
        error={error}
        titulo={
          proveedorEditado
            ? 'Editar proveedor'
            : 'Nuevo proveedor'
        }
        abierto={modal}
        procesando={procesando}
        guardar={guardarProveedor}
        cerrar={() => setModal(false)}
      >
        <label>
          Nombre del proveedor
          <input
            value={nombre}
            onChange={(evento) => setNombre(evento.target.value)}
          />
        </label>

        <div className="supplier-commercial-fields">
          <label>RUC<input inputMode="numeric" maxLength={11} value={comercial.ruc ?? ''} onChange={e => setComercial(a => ({ ...a, ruc: e.target.value.replace(/\D/g, '') }))} /></label>
          <button type="button" disabled={consultandoRuc || procesando || comercial.ruc?.length !== 11} onClick={async () => {
            if (!token || !comercial.ruc) return
            const rucConsultado = comercial.ruc
            try {
              setConsultandoRuc(true); setError('')
              const respuesta = await consultarRucProveedor(token, rucConsultado)
              setComercial(a => a.ruc === rucConsultado ? { ...a, razon_social: respuesta.nombre } : a)
            } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo consultar el RUC.') }
            finally { setConsultandoRuc(false) }
          }}>{consultandoRuc ? 'Consultando...' : 'Consultar RUC'}</button>
          {([
            ['razon_social', 'Razón social', 200], ['nombre_comercial', 'Nombre comercial', 200],
            ['direccion', 'Dirección', 250], ['contacto', 'Persona de contacto', 200],
          ] as const).map(([campo, titulo, limite]) => <label key={campo}>{titulo}<input
            maxLength={limite} value={comercial[campo] ?? ''}
            onChange={e => setComercial(a => ({ ...a, [campo]: e.target.value }))} /></label>)}
        </div>

        <div className="supplier-commercial-fields">
          <label>Correo (opcional)<input type="email" maxLength={200} value={comercial.email ?? ''}
            onChange={e => setComercial(actual => ({ ...actual, email: e.target.value }))} /></label>
          <label>Celular o teléfono (opcional)<input type="tel" maxLength={40} value={comercial.telefono ?? ''}
            onChange={e => setComercial(actual => ({ ...actual, telefono: e.target.value }))} /></label>
        </div>

        <fieldset className="suppliers-category-picker">
          <legend>Categorías que atiende</legend>
          <p>Selecciona una o varias categorías para este proveedor.</p>
          {datos.categorias.filter((item) => item.activo || idsCategorias.includes(item.id_categoria)).map((item) => (
            <label key={item.id_categoria}>
              <input
                type="checkbox"
                checked={idsCategorias.includes(item.id_categoria)}
                onChange={(evento) => setIdsCategorias((actuales) =>
                  evento.target.checked
                    ? [...actuales, item.id_categoria]
                    : actuales.filter((id) => id !== item.id_categoria),
                )}
              />
              {item.nombre}{!item.activo && ' (inactiva)'}
            </label>
          ))}
          {!datos.categorias.some((item) => item.activo) && (
            <p>Crea o activa una categoría antes de registrar un proveedor.</p>
          )}
        </fieldset>
      </CatalogDialog>
    </section>
  )
}
