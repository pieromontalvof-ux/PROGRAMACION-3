import { scheduleEffect } from '../utils/scheduleEffect'
import { InvoiceFields } from '../components/recepciones/InvoiceFields'
import { Link } from 'react-router-dom'
import { ChevronDown, ChevronUp, LoaderCircle, PackageCheck } from 'lucide-react'
import { Fragment, useCallback, useEffect, useState } from 'react'

import { useAuth } from '../context/authState'
import {
  obtenerPendientesRecepcion,
  registrarRecepcion,
} from '../services/receptionService'
import type {
  PendienteRecepcion,
  FacturaProveedorEntrada,
  RespuestaPendientesRecepcion,
} from '../types/reception'
import './PendingReceiptsPage.css'

const hoy = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(new Date())

export function PendingReceiptsPage() {
  const { token } = useAuth()
  const [datos, setDatos] = useState<RespuestaPendientesRecepcion | null>(null)
  const [abierto, setAbierto] = useState<string | null>(null)
  const [factura, setFactura] = useState('')
  const [serie, setSerie] = useState('F001')
  const [financiera, setFinanciera] = useState<FacturaProveedorEntrada>({ fecha_emision: hoy(), moneda: 'PEN', lineas: [] })
  const [fecha, setFecha] = useState(hoy())
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const cargar = useCallback(async () => {
    if (!token) return
    try {
      setCargando(true)
      setError('')
      setDatos(await obtenerPendientesRecepcion(token))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar los pendientes.')
    } finally {
      setCargando(false)
    }
  }, [token])

  useEffect(() => scheduleEffect(() => { void cargar()
    }), [cargar])

  const seleccionar = (item: PendienteRecepcion) => {
    const clave = `${item.id_orden_compra}-${item.id_proveedor}`
    if (abierto === clave) {
      setAbierto(null)
      return
    }
    setAbierto(clave)
    setFactura('')
    setSerie('F001')
    setFinanciera({ fecha_emision: hoy(), moneda: 'PEN', lineas: item.productos.map(p => ({ id_producto: p.id_producto, cantidad_facturada: p.cantidad_pendiente, costo_total: 0, precio_unitario: 0, descuento: 0, afectacion_igv: 'GRAVADO', igv_porcentaje: 18 })) })
    setFecha(hoy())
    setError('')
    setMensaje('')
  }

  const guardar = async (item: PendienteRecepcion) => {
    if (!token || !factura.trim() || !serie.trim() || !fecha) {
      setError('Completa el número de factura y la fecha.')
      return
    }
    const lineas=financiera.lineas.filter(l=>l.cantidad_facturada>0)
    const detalles=lineas.map(l=>({id_producto:l.id_producto,cantidad_recibida:l.cantidad_facturada}))
    if(lineas.some(l=>!Number.isFinite(l.costo_total)||Number(l.costo_total)<=0)){
      setError('Ingresa el costo total de cada producto recibido.');return
    }
    if (!detalles.length) {
      setError('Registra al menos una cantidad recibida mayor que cero.')
      return
    }
    try {
      setGuardando(true)
      setError('')
      const respuesta = await registrarRecepcion(
        token,
        item.id_orden_compra,
        {
          id_proveedor: item.id_proveedor,
          numero_factura: `${serie.trim().toUpperCase()}-${factura.trim()}`,
          fecha_recepcion: fecha,
          detalles,
          factura: { ...financiera, lineas: financiera.lineas.filter(l => l.cantidad_facturada > 0) },
        },
      )
      setMensaje(respuesta.mensaje)
      setAbierto(null)
      await cargar()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo registrar la recepción.')
    } finally {
      setGuardando(false)
    }
  }

  if (cargando) return <div className="receipt-state"><LoaderCircle /> Cargando...</div>

  return (
    <section className="receipt-page">
      <header className="receipt-header">
        <span>RECEPCIÓN DE PRODUCTOS</span>
        <h1>Pendientes de recepción</h1>
        <p>Registra entregas completas o parciales por proveedor.</p>
      </header>

      {mensaje && <div className="receipt-message ok">{mensaje}</div>}
      {error && <div className="receipt-message error">{error}</div>}

      <div className="receipt-summary">
        <article><strong>{datos?.resumen.ordenes_pendientes ?? 0}</strong><span>Órdenes pendientes</span></article>
        <article><strong>{datos?.resumen.recepciones_pendientes ?? 0}</strong><span>Proveedores pendientes</span></article>
        <article><strong>{datos?.resumen.productos_pendientes ?? 0}</strong><span>Productos pendientes</span></article>
      </div>

      <div className="receipt-list">
        {(datos?.pendientes ?? []).map((item) => {
          const clave = `${item.id_orden_compra}-${item.id_proveedor}`
          return (
            <Fragment key={clave}>
              <button className="receipt-row" onClick={() => seleccionar(item)}>
                <PackageCheck />
                <b>{item.codigo_orden}</b>
                <span>{item.proveedor}</span>
                <span>{item.productos.length} productos</span>
                {abierto === clave ? <ChevronUp /> : <ChevronDown />}
              </button>
              {abierto === clave && (
                <div className="receipt-detail">
                  <div className="receipt-fields">
                    <label>Serie<input value={serie} maxLength={10} onChange={(e) => setSerie(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''))} placeholder="F001" /></label>
                    <label>Número<input value={factura} inputMode="numeric" maxLength={20} onChange={(e) => setFactura(e.target.value.replace(/\D/g, ''))} placeholder="258" /></label>
                    <label>Fecha de recepción<input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></label>
                  </div>
                  <div className="invoice-summary"><p><b>Proveedor:</b> {item.proveedor}<br/>RUC: {item.datos_comerciales?.ruc || 'No registrado'}<br/>{item.datos_comerciales?.direccion}</p><p><b>Orden de compra:</b> {item.codigo_orden}</p></div>
                  <InvoiceFields productos={item.productos} value={financiera} onChange={setFinanciera} />
                  <p>Si esta factura ya está registrada, completa su entrega desde el <Link to="/home/recepciones/historial">historial de recepciones</Link>.</p>
                  <button className="receipt-save" disabled={guardando} onClick={() => void guardar(item)}>
                    {guardando ? 'Guardando...' : 'Registrar recepción'}
                  </button>
                </div>
              )}
            </Fragment>
          )
        })}
        {!datos?.pendientes.length && (
          <div className="receipt-empty">No existen órdenes enviadas pendientes de recepción.</div>
        )}
      </div>
    </section>
  )
}
