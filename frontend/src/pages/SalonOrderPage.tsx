import { scheduleEffect } from '../utils/scheduleEffect'
import {SalonPinDialog} from '../components/SalonPinDialog'
import { cancelarPedido, eliminarLineasPedido, enviarPedido, obtenerCartaPedido, obtenerPedido, obtenerSesionPedido } from '../features/salonOrders/pedidoService'
import { ajustarSalsa, construirReposiciones, grupoCompleto, puedeAgregarSalsa, seleccionarProducto, seleccionesIniciales } from '../features/salonOrders/pedidoRules'
import type { GrupoPromocion, Linea, Opcion, Pedido, Producto, Promocion, SeleccionBorrador, SeleccionPromocion, Sesion } from '../features/salonOrders/pedidoTypes'
import './SalonPage.css'
import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import './SalonOrderPage.css'

const dinero=(valor:number) => new Intl.NumberFormat('es-PE',{style:'currency',currency:'PEN'}).format(valor)
const firma=(opciones:Opcion[]) => opciones.map(o => o.id).sort((a,b) => a-b).join(',')
const nombreSalsa=(nombre:string) => nombre.replace(/^Salsa\s+/i,'')
function resumenReposiciones(barra:Linea,lineas:Linea[]) {
  const identidad=barra.ids_lineas?.[0]
  if(!identidad)return ''
  const cantidades=new Map<string,number>()
  for(const linea of lineas.filter(l => l.id_barra_libre===identidad)) {
    const salsa=nombreSalsa(linea.opciones[0]?.nombre ?? 'Sin salsa')
    cantidades.set(salsa,(cantidades.get(salsa) ?? 0)+linea.cantidad)
  }
  const total=[...cantidades.values()].reduce((s,c) => s+c,0)
  return total ? `${total} reposiciones · ${[...cantidades].map(([salsa,cantidad]) => `${cantidad} ${salsa}`).join(' · ')}` : ''
}
export function SalonOrderPage() {
  const {mesa}=useParams()
  const navigate=useNavigate()
  const [sesion,setSesion]=useState<Sesion|null>(null)
  const [eliminando,setEliminando]=useState(false)
  const [pedido,setPedido]=useState<Pedido|null>(null)
  const [productos,setProductos]=useState<Producto[]>([])
  const [promociones,setPromociones]=useState<Promocion[]>([])
  const [lineas,setLineas]=useState<Linea[]>([])
  const [seleccion,setSeleccion]=useState<number|null>(null)
  const [categoria,setCategoria]=useState<number|null>(null)
  const [vista,setVista]=useState<'carta'|'promociones'>('carta')
  const [buscar,setBuscar]=useState('')
  const [error,setError]=useState('')
  const [mensaje,setMensaje]=useState('')
  const [ocupado,setOcupado]=useState(false)
  const [cambios,setCambios]=useState(false)
  const [configurando,setConfigurando]=useState<Producto|null>(null)
  const [configurandoPromo,setConfigurandoPromo]=useState<Promocion|null>(null)
  const [seleccionesPromo,setSeleccionesPromo]=useState<SeleccionBorrador[]>([])
  const [reposicionLinea,setReposicionLinea]=useState<Linea|null>(null)
  const [reposicionSeleccion,setReposicionSeleccion]=useState<SeleccionPromocion|null>(null)
  const [cantidadesReposicion,setCantidadesReposicion]=useState<Record<number,number>>({})
  const [opciones,setOpciones]=useState<Opcion[]>([])
  const [comentando,setComentando]=useState(false)
  const [comentario,setComentario]=useState('')
  const dialog=useRef<HTMLDialogElement>(null)
  const promoDialog=useRef<HTMLDialogElement>(null)
  const reposicionDialog=useRef<HTMLDialogElement>(null)
  const comentarioDialog=useRef<HTMLDialogElement>(null)
  const envioClave=useRef(crypto.randomUUID())
  const enProceso=useRef(false)
  const lineaSeleccionada=seleccion===null ? undefined:lineas[seleccion]
  const editable=Boolean(lineaSeleccionada && !lineaSeleccionada.enviada && !ocupado && pedido?.puede_editar)
  const pendientes=lineas.filter(l => !l.enviada)
  useEffect(() => scheduleEffect(() => {
    const controller=new AbortController()
    setPedido(null);setLineas([]);setError('');setCambios(false);setSeleccion(null)
    envioClave.current=crypto.randomUUID()
    Promise.all([
      obtenerPedido(mesa, controller.signal),
      obtenerCartaPedido(controller.signal),
      obtenerSesionPedido(controller.signal),
    ])
      .then(([p,c,s]) => {if(!controller.signal.aborted){setPedido(p);setLineas(p.lineas);setProductos(c.productos);setPromociones(c.promociones);setSesion(s)}})
      .catch(e => {if(!controller.signal.aborted)setError(e.message)})
    return () => controller.abort()

    }),[mesa])
  useEffect(() => {if(configurando)dialog.current?.showModal()},[configurando])
  useEffect(() => {if(configurandoPromo)promoDialog.current?.showModal()},[configurandoPromo])
  useEffect(() => {if(reposicionLinea && reposicionSeleccion)reposicionDialog.current?.showModal()},[reposicionLinea,reposicionSeleccion])
  useEffect(() => {if(comentando)comentarioDialog.current?.showModal()},[comentando])
  useEffect(() => {
    if(!cambios)return
    const advertir=(e:BeforeUnloadEvent) => {e.preventDefault();e.returnValue=''}
    window.addEventListener('beforeunload',advertir)
    return () => window.removeEventListener('beforeunload',advertir)
  },[cambios])
  const categorias=Array.from(new Map(productos.map(p => [p.id_categoria,p.categoria])).entries())
  const filtrados=productos.filter(p => (categoria===null || p.id_categoria===categoria) && p.nombre.toLocaleLowerCase().includes(buscar.trim().toLocaleLowerCase()))
  const promocionesFiltradas=promociones.filter(p => p.nombre.toLocaleLowerCase().includes(buscar.trim().toLocaleLowerCase()))
  const total=lineas.reduce((s,l) => s+l.precio*l.cantidad,0)

  function agregar(producto:Producto,elegidas:Opcion[]=[],barra?:Linea) {
    if(ocupado || !pedido?.puede_editar)return
    if(barra) {
      if((barra.ids_lineas?.length ?? 0)!==1 || pendientes.length>=100){setError('No se pudo identificar la barra libre o se alcanzó el límite de líneas.');return}
      setLineas(actual => [...actual,{id_presentacion:producto.id,nombre:producto.nombre,precio:0,cantidad:1,
        comentario:'Reposición',opciones:[...elegidas],enviada:false,id_barra_libre:barra.ids_lineas![0],barra_nombre:barra.nombre}])
      setSeleccion(lineas.length);setCambios(true);setMensaje('');setError('');setReposicionLinea(null);setConfigurando(null);return
    }
    const indice=lineas.findIndex(l => !l.enviada && l.id_presentacion===producto.id && !l.id_barra_libre && firma(l.opciones)===firma(elegidas))
    if(indice>=0 && lineas[indice].cantidad>=99){setError('Máximo 99 unidades por línea.');return}
    if(indice<0 && pendientes.length>=100){setError('Máximo 100 líneas por envío.');return}
    setLineas(actual => {
      const i=actual.findIndex(l => !l.enviada && l.id_presentacion===producto.id && !l.id_barra_libre && firma(l.opciones)===firma(elegidas))
      return i<0 ? [...actual,{id_presentacion:producto.id,nombre:producto.nombre,precio:producto.precio,cantidad:1,comentario:'',opciones:[...elegidas],enviada:false}]
        : actual.map((l,n) => n===i ? {...l,cantidad:Math.min(99,l.cantidad+1)}:l)
    })
    setSeleccion(indice<0 ? lineas.length:indice);setCambios(true);setMensaje('');setError('')
  }
  function tocar(producto:Producto) {
    if(ocupado || !pedido?.puede_editar)return
    const existente=lineas.find(l => !l.enviada && l.id_presentacion===producto.id && !l.id_barra_libre)
    if(existente){agregar(producto,existente.opciones);return}
    if(producto.grupo?.opciones.length){setReposicionLinea(null);setConfigurando(producto);setOpciones([])}
    else agregar(producto)
  }
  function agregarPromo(promo:Promocion) {
    if(ocupado || !pedido?.puede_editar || pendientes.length>=100)return
    setConfigurandoPromo(promo)
    setSeleccionesPromo(seleccionesIniciales(promo, () => crypto.randomUUID()))
  }
  function seleccionarOpcionPromo(grupo:GrupoPromocion,producto:Producto) {
    const clave = crypto.randomUUID()
    setSeleccionesPromo(items => seleccionarProducto(items, grupo, producto, clave))
  }
  function quitarOpcionPromo(clave:string) {setSeleccionesPromo(items => items.filter(s => s.clave!==clave))}
  function cambiarSalsaPromo(clave:string,opcion:Opcion,delta:number) {
    setSeleccionesPromo(items => items.map(s => s.clave === clave ? ajustarSalsa(s, opcion, delta) : s))
  }
  function confirmarPromo() {
    if(!configurandoPromo || !pedido?.puede_editar)return
    const completa=configurandoPromo.grupos.every(g => grupoCompleto(g, seleccionesPromo))
    if(!completa){setError('Completa las opciones incluidas en la promoción.');return}
    setLineas(actual => [...actual,{id_presentacion:null,id_promocion:configurandoPromo.id,
      selecciones_promocion:seleccionesPromo.map(({clave:_clave,...s}) => s),nombre:configurandoPromo.nombre,
      precio:configurandoPromo.precio,cantidad:1,comentario:'',opciones:[],enviada:false}])
    setSeleccion(lineas.length);setCambios(true);setMensaje('');setError('');setConfigurandoPromo(null)
  }
  function iniciarReposicion(linea:Linea,seleccionPromo:SeleccionPromocion) {
    if(!pedido?.puede_editar || !linea.enviada || !seleccionPromo.reponible)return
    if(!seleccionPromo.grupo?.opciones.length)return
    setReposicionLinea(linea);setReposicionSeleccion(seleccionPromo);setCantidadesReposicion({})
  }
  function ajustarCantidadReposicion(opcion:Opcion,delta:number) {
    setCantidadesReposicion(actual => ({...actual,[opcion.id]:Math.max(0,Math.min(99,(actual[opcion.id] ?? 0)+delta))}))
  }
  function confirmarReposiciones() {
    if(!reposicionLinea || !reposicionSeleccion || !pedido?.puede_editar)return
    const resultado = construirReposiciones(reposicionLinea, reposicionSeleccion, cantidadesReposicion, pendientes.length)
    if ('error' in resultado) {setError(resultado.error);return}
    setLineas(actual => [...actual,...resultado.lineas]);setCambios(true);setMensaje('');setError('')
    setReposicionLinea(null);setReposicionSeleccion(null);setCantidadesReposicion({})
  }
  function borrar() {
    if(!editable)return
    setLineas(actual => actual.filter((_,i) => i!==seleccion));setSeleccion(null);setCambios(true);setMensaje('')
  }
  async function cancelar() {
    if(enProceso.current)return
    if(!pedido){navigate('/salon');return}
    enProceso.current=true;setOcupado(true);setError('')
    try {
      if(pedido.puede_editar && pedido.id_borrador!==null)await cancelarPedido(mesa, pedido.version)
      setCambios(false);navigate('/salon')
    } catch(e){setError(e instanceof Error ? e.message:'No se pudo cancelar')}
    finally {enProceso.current=false;setOcupado(false)}
  }
  async function enviar() {
    if(!pedido?.puede_editar || enProceso.current || !pendientes.length)return
    enProceso.current=true;setOcupado(true);setError('');setMensaje('')
    try {
      const p=await enviarPedido(mesa, pedido.version, envioClave.current, pendientes)
      setPedido(p);setLineas(p.lineas);setSeleccion(null);setCambios(false);envioClave.current=crypto.randomUUID()
      navigate('/salon')
    } catch(e){setError(e instanceof Error ? e.message:'No se pudo enviar')}
    finally {enProceso.current=false;setOcupado(false)}
  }
  const grupoSalsaCompleto=(seleccionPromo:SeleccionBorrador) => !seleccionPromo.grupo || seleccionPromo.opciones.length<=seleccionPromo.grupo.maximo

  return <main className="salon-order">
    <header><h1>Salón {sesion?.local} · {mesa}</h1><span>{sesion?.usuario}</span></header>
    {error && <div className="order-alert" role="alert"><p>{error}</p><button onClick={() => window.location.reload()}>Volver a cargar</button></div>}
    {mensaje && <p role="status" className="order-message">{mensaje}</p>}
    {!pedido ? !error && <p role="status">Cargando pedido…</p> : <div className="order-workspace">
      <section className="order-catalog"><h2>Carta</h2>
        <nav aria-label="Sección del catálogo">
          <button aria-pressed={vista==='carta'} onClick={() => {setVista('carta');setBuscar('')}}>Carta</button>
          <button aria-pressed={vista==='promociones'} onClick={() => {setVista('promociones');setCategoria(null);setBuscar('')}}>Promociones</button>
        </nav>
        {vista==='carta' && <nav aria-label="Categorías de carta"><button aria-pressed={categoria===null} onClick={() => setCategoria(null)}>Todas</button>
          {categorias.map(([id,nombre]) => <button key={id} aria-pressed={categoria===id} onClick={() => setCategoria(id)}>{nombre}</button>)}</nav>}
        <label className="order-search">Buscar {vista==='promociones' ? 'promoción':'producto'}<input type="search" placeholder="Escribe el nombre" value={buscar} onChange={e => setBuscar(e.target.value)} /></label>
        {vista==='carta' ? <div className="order-products">{filtrados.map(p => <button key={p.id} disabled={ocupado || !pedido.puede_editar} onClick={() => tocar(p)}><strong>{p.nombre}</strong><span>{dinero(p.precio)}</span></button>)}</div> :
          <div className="order-products">{promocionesFiltradas.map(p => <button key={p.id} disabled={ocupado || !pedido.puede_editar} onClick={() => agregarPromo(p)}>
            <strong>{p.nombre}</strong><span>{dinero(p.precio)} · por persona</span></button>)}</div>}
        {vista==='carta' && !filtrados.length && <p>No se encontraron artículos disponibles.</p>}
        {vista==='promociones' && !promocionesFiltradas.length && <p>No hay promociones activas disponibles.</p>}
      </section>
      <aside className="order-cart"><h2>Pedido · {mesa}</h2><p>{pendientes.reduce((total,l) => total+(l.id_promocion ? 1:l.cantidad),0)} unidades por enviar</p>
        <div className="order-lines" role="group" aria-label="Productos del pedido">
          {!lineas.length && <p>Toca un artículo o una promoción para agregarlo.</p>}
          {lineas.map((l,i) => {
            if(l.id_barra_libre)return null
            const resumen=resumenReposiciones(l,lineas)
            return <article className="order-line-card" key={l.ids_lineas?.[0] ?? `pending-${i}`}>
            <button type="button" className={`order-line-select ${l.enviada ? 'is-sent':''}`} disabled={ocupado}
              aria-pressed={seleccion===i} onClick={() => setSeleccion(i)}>
              <span className="order-line-heading"><strong>{l.id_promocion ? '1 × ' : `${l.cantidad} × `}{l.nombre}</strong><b>{dinero(l.cantidad*l.precio)}</b></span>
              <span className="order-line-status">{l.enviada ? 'Enviado':'Por enviar'}</span>
              {l.id_barra_libre && <span>Reposición para: {l.barra_nombre}</span>}
              {l.id_promocion && resumen && <span>{resumen}</span>}
              {l.opciones.length>0 && <span>Salsa: {l.opciones.map(o => o.nombre).join(', ')}</span>}
              {l.selecciones_promocion?.map((s,j) => <span key={`${s.id_grupo}-${j}`}>{s.nombre}{s.opciones.length ? ` · ${s.opciones.map(o => nombreSalsa(o.nombre)).join(', ')}`:''}</span>)}
              {l.comentario && <span className="order-comment"><strong>Comentario:</strong> {l.comentario}</span>}
            </button>
            {l.enviada && l.id_promocion && pedido.puede_editar && <div className="order-refills">
              {l.selecciones_promocion?.filter(s => s.reponible).map((s,j) => <button key={`${s.id_presentacion}-${j}`} disabled={ocupado}
                onClick={() => iniciarReposicion(l,s)}>+ Reponer {s.nombre}</button>)}
            </div>}
          </article>
          })}
        </div>
        {lineaSeleccionada?.enviada && <small>Producto enviado. Solo gerente o supervisor puede eliminarlo con su PIN.</small>}
        <div className="order-total"><strong>Total mesa</strong><strong>{dinero(total)}</strong></div>
      </aside>
    </div>}
    <footer className="salon-actionbar">
      <button disabled={ocupado} onClick={()=>void cancelar()}>Cancelar</button>
      {[2,3].includes(sesion?.perfil??0)&&<button className="salon-delete" disabled={ocupado||!lineaSeleccionada?.enviada} onClick={()=>setEliminando(true)}>Eliminar</button>}
      <button disabled={!editable} onClick={borrar}>Borrar</button>
      <button disabled={!editable} onClick={()=>{setComentario(lineaSeleccionada!.comentario);setComentando(true)}}>Añadir comentario</button>
      <button className="salon-exit" disabled={ocupado} onClick={()=>{setCambios(false);sessionStorage.removeItem('salon_token');navigate('/login',{replace:true})}}>Salir</button>
      <button className="salon-send" disabled={ocupado||!pendientes.length||!pedido?.puede_editar} onClick={()=>void enviar()}>{ocupado?'Procesando...':'Enviar'}</button>
      <button className="salon-pay" disabled={ocupado||!lineas.some(l=>l.enviada)||pendientes.length>0||pedido?.id_borrador!=null}
        title={pendientes.length ? 'Envía o borra los productos pendientes antes de pagar' : 'Pagar la cuenta'}
        onClick={()=>navigate(`/salon/mesa/${mesa}/pagar`)}>Pagar</button>
    </footer>
    {eliminando&&<SalonPinDialog accion="eliminar" onCancel={()=>setEliminando(false)} onAuthorized={autorizacion=>{
      setEliminando(false);setOcupado(true);enProceso.current=true;setError('')
      eliminarLineasPedido(mesa, autorizacion, lineaSeleccionada?.ids_lineas).then(d=>{
        setPedido(d.pedido);setLineas(actual=>[...d.pedido.lineas.filter((l:Linea)=>l.enviada),...actual.filter((l:Linea)=>!l.enviada)]);setSeleccion(null);setMensaje('Producto eliminado con autorización.')
      }).catch(e=>setError(e.message)).finally(()=>{setOcupado(false);enProceso.current=false})
    }}/>}
    {configurando && <dialog ref={dialog} className="order-editor" onCancel={() => {setConfigurando(null);setReposicionLinea(null)}}>
      <form onSubmit={e => {e.preventDefault();agregar(configurando,opciones,reposicionLinea ?? undefined)}}>
        <h2>{reposicionLinea ? 'Reposición de barra libre':'Opciones del producto'}</h2><p>{configurando.nombre}</p>
        <p>Escoge hasta {configurando.grupo!.maximo} opciones. {configurando.grupo!.repetir ? 'Puedes repetir.':'Sin repetir.'}</p>
        {configurando.grupo!.opciones.map(o => <div className="order-option" key={o.id}><span>{o.nombre}</span>
          <button type="button" aria-label={`Quitar ${o.nombre}`} disabled={!opciones.some(s => s.id===o.id)} onClick={() => {const copia=[...opciones];copia.splice(copia.findIndex(s => s.id===o.id),1);setOpciones(copia)}}>−</button>
          <span>{opciones.filter(s => s.id===o.id).length}</span>
          <button type="button" aria-label={`Agregar ${o.nombre}`} disabled={opciones.length>=configurando.grupo!.maximo || (!configurando.grupo!.repetir && opciones.some(s => s.id===o.id))} onClick={() => setOpciones([...opciones,o])}>+</button>
        </div>)}
        <footer><button type="button" onClick={() => {setConfigurando(null);setReposicionLinea(null)}}>Cancelar</button><button className="primary">{reposicionLinea ? 'Agregar reposición':'Agregar'}</button></footer>
      </form>
    </dialog>}
    {reposicionLinea && reposicionSeleccion && <dialog ref={reposicionDialog} className="order-editor order-refill-editor"
      onCancel={() => {setReposicionLinea(null);setReposicionSeleccion(null);setCantidadesReposicion({})}}>
      <form onSubmit={e => {e.preventDefault();confirmarReposiciones()}}>
        <h2>Reponer Alitas</h2><p>{reposicionLinea.nombre}</p>
        <p>Elige cuántas porciones agregar de cada salsa.</p>
        {reposicionSeleccion.grupo?.opciones.map(opcion => <div className="order-option" key={opcion.id}>
          <span>{nombreSalsa(opcion.nombre)}</span>
          <button type="button" aria-label={`Quitar una porción ${nombreSalsa(opcion.nombre)}`}
            disabled={!cantidadesReposicion[opcion.id]} onClick={() => ajustarCantidadReposicion(opcion,-1)}>−</button>
          <span>{cantidadesReposicion[opcion.id] ?? 0}</span>
          <button type="button" aria-label={`Agregar una porción ${nombreSalsa(opcion.nombre)}`}
            disabled={(cantidadesReposicion[opcion.id] ?? 0)>=99} onClick={() => ajustarCantidadReposicion(opcion,1)}>+</button>
        </div>)}
        <footer><button type="button" onClick={() => {setReposicionLinea(null);setReposicionSeleccion(null);setCantidadesReposicion({})}}>Cancelar</button>
          <button className="primary" disabled={!Object.values(cantidadesReposicion).some(cantidad => cantidad>0)}>Agregar reposiciones</button></footer>
      </form>
    </dialog>}
    {configurandoPromo && <dialog ref={promoDialog} className="order-editor order-promotion-editor" onCancel={() => setConfigurandoPromo(null)}>
      <form onSubmit={e => {e.preventDefault();confirmarPromo()}}>
        <h2>{configurandoPromo.nombre}</h2><p>{dinero(configurandoPromo.precio)} · se cobra una vez por persona</p>
        {configurandoPromo.grupos.map(grupo => <section className="order-promo-group" key={grupo.id}>
          <h3>Elige {grupo.cantidad} opción{grupo.cantidad===1?'':'es'}{grupo.repetir?' · se permite repetir':''}</h3>
          {!(grupo.cantidad===1 && grupo.opciones.length===1) && grupo.opciones.map(producto => {
            const tomadas=seleccionesPromo.filter(s => s.id_grupo===grupo.id && s.id_presentacion===producto.id).length
            const totalGrupo=seleccionesPromo.filter(s => s.id_grupo===grupo.id).length
            return <div className="order-option" key={producto.id}><span>{producto.nombre}</span><span>{tomadas}</span>
              <button type="button" aria-label={`Agregar ${producto.nombre}`} disabled={totalGrupo>=grupo.cantidad || (!grupo.repetir && tomadas>0)}
                onClick={() => seleccionarOpcionPromo(grupo,producto)}>+</button>
            </div>
          })}
          {grupo.cantidad===1 && grupo.opciones.length===1 && <p className="order-promo-included">Incluye {grupo.opciones[0].nombre}</p>}
          {seleccionesPromo.filter(s => s.id_grupo===grupo.id).map((s,index) => <article className="order-promo-selection" key={s.clave}>
            <header><strong>{index+1}. {s.nombre}</strong><button type="button" aria-label={`Quitar ${s.nombre}`} onClick={() => quitarOpcionPromo(s.clave)}>Quitar</button></header>
            {s.grupo?.opciones.map(o => <div className="order-option" key={o.id}><span>Salsa: {o.nombre}</span>
              <button type="button" aria-label={`Quitar salsa ${o.nombre}`} disabled={!s.opciones.some(x => x.id===o.id)} onClick={() => cambiarSalsaPromo(s.clave,o,-1)}>−</button>
              <span>{s.opciones.filter(x => x.id===o.id).length}</span>
              <button type="button" aria-label={`Agregar salsa ${o.nombre}`} disabled={!puedeAgregarSalsa(s, o)}
                onClick={() => cambiarSalsaPromo(s.clave,o,1)}>+</button>
            </div>)}
          </article>)}
          <small>{seleccionesPromo.filter(s => s.id_grupo===grupo.id).length} de {grupo.cantidad} seleccionadas</small>
        </section>)}
        <footer><button type="button" onClick={() => setConfigurandoPromo(null)}>Cancelar</button>
          <button className="primary" disabled={!configurandoPromo.grupos.every(grupo => grupoCompleto(grupo, seleccionesPromo)) || !seleccionesPromo.every(grupoSalsaCompleto)}>Agregar a la cuenta</button></footer>
      </form>
    </dialog>}
    {comentando && <dialog ref={comentarioDialog} className="order-editor" onCancel={() => setComentando(false)}>
      <form onSubmit={e => {e.preventDefault();if(editable){setLineas(a => a.map((l,i) => i===seleccion ? {...l,comentario:comentario.trim()}:l));setCambios(true)}setComentando(false)}}>
        <h2>Comentario</h2><p>{lineaSeleccionada?.nombre}</p>
        <textarea aria-label="Comentario del producto" autoFocus maxLength={500} value={comentario} onChange={e => setComentario(e.target.value)} placeholder="Ej. sin cebolla" />
        <footer><button type="button" onClick={() => setComentando(false)}>Cancelar</button><button className="primary" disabled={!editable}>Aplicar</button></footer>
      </form>
    </dialog>}
  </main>
}
