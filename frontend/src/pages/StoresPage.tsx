import { API_BASE_URL } from '../config'
﻿import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Plus, Search, Store, MapPin, Pencil, Trash2, X, Download, Info } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/authState'
import './UsersPage.css'
import './StoresPage.css'

type Tienda = { id_local: number; codigo: string; nombre: string; direccion: string | null; estado_registro: number }
const api = API_BASE_URL
const vacio = { nombre: '', direccion: '' }

const ordenar = (a: Tienda, b: Tienda) => a.codigo.localeCompare(b.codigo, undefined, { numeric: true })

export function StoresPage() {
  const { token, perfilActivo, menu, actualizarSesion } = useAuth()
  const permiso = menu.find(m => m.id_opcion_menu === 2)?.permisos
  const permitido = perfilActivo?.id_perfil === 1 && permiso?.consultar
  const [tiendas, setTiendas] = useState<Tienda[]>([])
  const [form, setForm] = useState(vacio)
  const [edicion, setEdicion] = useState<Tienda | null>(null)
  const [modal, setModal] = useState(false)
  const [confirmacion, setConfirmacion] = useState<{ tienda: Tienda; accion: 'estado' | 'eliminar' } | null>(null)
  const [busqueda, setBusqueda] = useState('')
  const [filtro, setFiltro] = useState('todas')
  const [error, setError] = useState('')
  const [errorModal, setErrorModal] = useState('')
  const [mensaje, setMensaje] = useState('')
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const dialog = useRef<HTMLDialogElement>(null)
  const confirmDialog = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    if (!permitido) return
    const control = new AbortController()
    fetch(`${api}/locales`, { headers: { Authorization: `Bearer ${token}` }, signal: control.signal })
      .then(async r => { const d = await r.json(); if (!r.ok) throw Error(d.mensaje ?? 'No se pudieron cargar las tiendas.'); return d })
      .then(d => { if (!control.signal.aborted) setTiendas(d.locales) })
      .catch(e => { if (!control.signal.aborted) setError(e.message) })
      .finally(() => { if (!control.signal.aborted) setCargando(false) })
    return () => control.abort()
  }, [token, permitido])
  useEffect(() => { if (modal) dialog.current?.showModal(); else dialog.current?.close() }, [modal])
  useEffect(() => { if (confirmacion) confirmDialog.current?.showModal(); else confirmDialog.current?.close() }, [confirmacion])

  async function solicitar(ruta: string, method: string, datos?: unknown) {
    const r = await fetch(`${api}/locales${ruta}`, { method, headers: {
      Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
    }, body: datos === undefined ? undefined : JSON.stringify(datos) })
    const d = await r.json()
    if (!r.ok) throw Error(d.mensaje ?? 'No se pudo guardar el cambio.')
    return d as { mensaje: string; local: Tienda | null }
  }
  async function refrescarSesion() {
    try { await actualizarSesion() } catch { setError('El cambio se guardó. Recarga para actualizar el selector de locales.') }
  }
  function abrir(tienda: Tienda | null = null) {
    setEdicion(tienda); setForm(tienda ? { nombre: tienda.nombre, direccion: tienda.direccion ?? '' } : vacio)
    setErrorModal(''); setModal(true)
  }
  async function guardar(event: FormEvent) {
    event.preventDefault()
    if (guardando) return
    setGuardando(true); setErrorModal(''); setError(''); setMensaje('')
    try {
      const d = await solicitar(edicion ? `/${edicion.id_local}` : '', edicion ? 'PUT' : 'POST', form)
      if (d.local) {
        const local = d.local
        setTiendas(actual => [...actual.filter(t => t.id_local !== local.id_local), local].sort(ordenar))
      }
      setModal(false); setMensaje(d.mensaje); await refrescarSesion()
    } catch (e) { setErrorModal(e instanceof Error ? e.message : 'No se pudo guardar la tienda.') }
    finally { setGuardando(false) }
  }
  async function confirmar() {
    if (!confirmacion || guardando) return
    setGuardando(true); setErrorModal(''); setError(''); setMensaje('')
    const { tienda, accion } = confirmacion
    try {
      const d = await solicitar(`/${tienda.id_local}${accion === 'estado' ? '/estado' : ''}`,
        accion === 'estado' ? 'PATCH' : 'DELETE', accion === 'estado' ? { estado_registro: tienda.estado_registro === 1 ? 0 : 1 } : undefined)
      setTiendas(actual => accion === 'eliminar' ? actual.filter(t => t.id_local !== tienda.id_local) : actual.map(t => t.id_local === tienda.id_local && d.local ? d.local : t))
      setConfirmacion(null); setMensaje(d.mensaje); await refrescarSesion()
    } catch (e) { setErrorModal(e instanceof Error ? e.message : 'No se pudo completar la acción.') }
    finally { setGuardando(false) }
  }
  const visibles = tiendas.filter(t => `${t.nombre} ${t.codigo} ${t.direccion ?? ''}`.toLocaleLowerCase().includes(busqueda.toLocaleLowerCase()) &&
    (filtro === 'todas' || t.estado_registro === (filtro === 'activas' ? 1 : 0)))
  const activas = tiendas.filter(t => t.estado_registro === 1).length
  function exportar() {
    const cell = (value: string) => '"' + value.replace(/^[\s=+@-]/, "'$&").replaceAll('"', '""') + '"'
    const rows = [['Código', 'Tienda', 'Dirección', 'Estado'], ...visibles.map(t =>
      [t.codigo, t.nombre, t.direccion ?? '', t.estado_registro === 1 ? 'Activa' : 'Inactiva'])]
    const url = URL.createObjectURL(new Blob(['\ufeff' + rows.map(row => row.map(cell).join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8' }))
    const link = document.createElement('a'); link.href = url; link.download = 'tiendas.csv'; link.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  const accionTexto = confirmacion?.accion === 'eliminar' ? 'Eliminar' : confirmacion?.tienda.estado_registro === 1 ? 'Desactivar' : 'Reactivar'
  if (!permitido) return <p>La gestión de tiendas corresponde al Administrador.</p>
  return <main className="users-page stores-page">
    <section className="stores-overview" aria-label="Resumen de tiendas">
    <header className="users-header stores-header"><span className="stores-hero-icon"><Store size={32} aria-hidden="true" /></span><div><div className="stores-title-line"><h1>Tiendas</h1><span className="stores-count">{cargando ? '…' : tiendas.length} sedes</span></div><p>Administra tus locales y su disponibilidad.</p></div></header>
    {error && <div role="alert" className="users-alert error">{error}</div>}
    {mensaje && <div role="status" className="users-alert ok">{mensaje}</div>}
    <div className="stores-overview-tools"><nav className="stores-status-tabs" aria-label="Estado de las tiendas">
      {([['todas', 'Todas', tiendas.length], ['activas', 'Activas', activas], ['inactivas', 'Inactivas', tiendas.length - activas]] as const).map(([value, label, count]) =>
        <button key={value} type="button" aria-pressed={filtro === value} onClick={() => setFiltro(value)}>{label}<span>{cargando ? '—' : count}</span></button>)}
    </nav>
      {permiso?.crear && <button className="stores-create" onClick={() => abrir()}><Plus size={20} aria-hidden="true" />Nueva tienda</button>}
    </div>
    </section>
    <section className="users-card">
      <div className="users-tools stores-toolbar"><label><Search size={18} aria-hidden="true" /><input aria-label="Buscar tiendas" placeholder="Buscar por nombre, código o dirección…" value={busqueda} onChange={e => setBusqueda(e.target.value)} /></label>
        <button className="stores-export" disabled={cargando || !visibles.length} onClick={exportar}><Download size={18} aria-hidden="true" />Exportar CSV</button></div>
      <div className="users-table"><table><thead><tr><th>Tienda</th><th>Dirección</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>
        {visibles.map(t => <tr key={t.id_local}><td><div className="stores-name"><span className="stores-avatar"><Store size={21} /></span><div><strong>{t.nombre}</strong><small>{t.codigo}</small></div></div></td>
          <td><span className="stores-address"><MapPin size={16} aria-hidden="true" />{t.direccion || 'Sin dirección registrada'}</span></td>
          <td><div className="stores-state"><button type="button" className="stores-switch" role="switch" aria-checked={t.estado_registro === 1} disabled={!permiso?.editar}
            aria-label={`${t.estado_registro === 1 ? 'Desactivar' : 'Reactivar'} ${t.nombre}`} onClick={() => { setErrorModal(''); setConfirmacion({ tienda: t, accion: 'estado' }) }}><span /></button><span>{t.estado_registro === 1 ? 'Activa' : 'Inactiva'}</span></div></td>
          <td><div className="users-actions">{permiso?.editar && <button className="stores-edit" title={`Editar ${t.nombre}`} aria-label={`Editar ${t.nombre}`} onClick={() => abrir(t)}><Pencil aria-hidden="true" /><span>Editar</span></button>}
            {permiso?.eliminar && <button className="stores-danger" title={`Eliminar ${t.nombre}`} aria-label={`Eliminar ${t.nombre}`} onClick={() => { setErrorModal(''); setConfirmacion({ tienda: t, accion: 'eliminar' }) }}><Trash2 /></button>}</div></td></tr>)}
        {(cargando || !visibles.length) && <tr><td colSpan={4} className="empty">{cargando ? 'Cargando tiendas…' : 'No hay tiendas para estos filtros.'}</td></tr>}
      </tbody></table></div><footer className="stores-footer">{visibles.length} de {tiendas.length} tiendas <Link to="/home/usuarios">Asignar gerente y equipo en Usuarios →</Link></footer>
    </section>
    <aside className="stores-help"><Info size={20} aria-hidden="true" /><span>Revisa la dirección y disponibilidad de cada sede. Los cambios de estado requieren tu confirmación.</span></aside>
    <dialog ref={dialog} className="stores-dialog" aria-labelledby="stores-form-title" onCancel={e => { if (guardando) e.preventDefault(); else setModal(false) }}>
      <form onSubmit={e => void guardar(e)}><header className="users-modal-title"><div><h2 id="stores-form-title">{edicion ? 'Editar tienda' : 'Nueva tienda'}</h2><p>Datos de la sede y ubicación para eventos cercanos.</p></div><button type="button" aria-label="Cerrar" disabled={guardando} onClick={() => setModal(false)}><X /></button></header>
        {errorModal && <div role="alert" className="users-alert error">{errorModal}</div>}
        <fieldset disabled={guardando} className="stores-form"><label>Nombre de la tienda<input autoFocus required maxLength={100} value={form.nombre} placeholder="Ej. BarBarian San Isidro" onChange={e => setForm({ ...form, nombre: e.target.value })} /></label>
          <label>Código de la sede<input readOnly value={edicion?.codigo ?? 'Se asignará al crear la tienda'} /><small>{edicion ? 'El código se conserva al editar.' : 'Formato TDA-001. Se asigna el primer número disponible; las tiendas inactivas conservan su número.'}</small></label>
          <label>Dirección completa<textarea required maxLength={250} rows={3} value={form.direccion} placeholder="Calle, número, distrito y ciudad" onChange={e => setForm({ ...form, direccion: e.target.value })} /><small>El asistente usa esta dirección para consultar eventos cercanos.</small></label>
        </fieldset><footer className="users-modal-buttons"><button type="button" disabled={guardando} onClick={() => setModal(false)}>Cancelar</button><button className="save" disabled={guardando}>{guardando ? 'Guardando…' : edicion ? 'Guardar cambios' : 'Crear tienda'}</button></footer>
      </form>
    </dialog>
    <dialog ref={confirmDialog} className="stores-dialog" aria-labelledby="stores-confirm-title" onCancel={e => { if (guardando) e.preventDefault(); else setConfirmacion(null) }}>
      <h2 id="stores-confirm-title">{accionTexto} tienda</h2><p>¿Quieres {accionTexto.toLowerCase()} <strong>{confirmacion?.tienda.nombre}</strong>?</p>
      <p className="stores-detail">{confirmacion?.accion === 'eliminar' ? 'Esta acción es permanente. Solo se pueden eliminar tiendas sin usuarios, configuraciones ni historial asociado.' : confirmacion?.tienda.estado_registro === 1 ? 'La tienda dejará de estar disponible para nuevas sesiones. Su historial se conservará.' : 'La tienda volverá a estar disponible para los usuarios asignados.'}</p>
      {errorModal && <div role="alert" className="users-alert error">{errorModal}</div>}
      <footer className="users-modal-buttons"><button autoFocus disabled={guardando} onClick={() => setConfirmacion(null)}>Cancelar</button><button className={confirmacion?.accion === 'eliminar' ? 'stores-delete-button' : 'save'} disabled={guardando} onClick={() => void confirmar()}>{guardando ? 'Procesando…' : accionTexto}</button></footer>
    </dialog>
  </main>
}
