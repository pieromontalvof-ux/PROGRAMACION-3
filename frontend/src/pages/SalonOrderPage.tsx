import {SalonPinDialog,salonApi} from '../components/SalonPinDialog'
import './SalonPage.css'
import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import './SalonOrderPage.css'

interface Opcion {id:number;nombre:string}
interface Producto {id:number;nombre:string;precio:number;id_categoria:number;categoria:string;grupo:{maximo:number;repetir:boolean;opciones:Opcion[]}|null}
interface Linea {id_presentacion:number;nombre:string;precio:number;cantidad:number;comentario:string;opciones:Opcion[];enviada:boolean;ids_lineas?:number[]}
interface Pedido {puede_editar:boolean;mesa:string;version:number;id_borrador:number|null;lineas:Linea[];total:number}
const dinero=(valor:number) => new Intl.NumberFormat('es-PE',{style:'currency',currency:'PEN'}).format(valor)
const api=import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
const firma=(opciones:Opcion[]) => opciones.map(o => o.id).sort((a,b) => a-b).join(',')
async function consultar(ruta:string,datos?:unknown,signal?:AbortSignal,metodo='PUT') {
  const token=sessionStorage.getItem('salon_token')
  if(!token) throw new Error('Inicia sesión en Salón para continuar.')
  const r=await fetch(`${api}/salon/${ruta}`,{method:datos ? metodo:'GET',signal,
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:datos ? JSON.stringify(datos):undefined})
  const d=await r.json()
  if(!r.ok) throw new Error(d.mensaje ?? d.msg ?? 'No se pudo completar la operación')
  return d
}

export function SalonOrderPage() {
  const {mesa}=useParams()
  const navigate=useNavigate()
  const [sesion,setSesion]=useState<{local:string;usuario:string;perfil:number}|null>(null)
  const [eliminando,setEliminando]=useState(false)
  const [pedido,setPedido]=useState<Pedido|null>(null)
  const [productos,setProductos]=useState<Producto[]>([])
  const [lineas,setLineas]=useState<Linea[]>([])
  const [seleccion,setSeleccion]=useState<number|null>(null)
  const [categoria,setCategoria]=useState<number|null>(null)
  const [buscar,setBuscar]=useState('')
  const [error,setError]=useState('')
  const [mensaje,setMensaje]=useState('')
  const [ocupado,setOcupado]=useState(false)
  const [cambios,setCambios]=useState(false)
  const [configurando,setConfigurando]=useState<Producto|null>(null)
  const [opciones,setOpciones]=useState<Opcion[]>([])
  const [comentando,setComentando]=useState(false)
  const [comentario,setComentario]=useState('')
  const dialog=useRef<HTMLDialogElement>(null)
  const comentarioDialog=useRef<HTMLDialogElement>(null)
  const envioClave=useRef(crypto.randomUUID())
  const enProceso=useRef(false)
  const lineaSeleccionada=seleccion===null ? undefined:lineas[seleccion]
  const editable=Boolean(lineaSeleccionada && !lineaSeleccionada.enviada && !ocupado && pedido?.puede_editar)
  const pendientes=lineas.filter(l => !l.enviada)
  useEffect(() => {
    const controller=new AbortController()
    setPedido(null);setLineas([]);setError('');setCambios(false);setSeleccion(null)
    envioClave.current=crypto.randomUUID()
    Promise.all([consultar(`mesas/${mesa}/pedido`,undefined,controller.signal),consultar('carta',undefined,controller.signal),consultar('me',undefined,controller.signal)])
      .then(([p,c,s]) => {if(!controller.signal.aborted){setPedido(p);setLineas(p.lineas);setProductos(c.productos);setSesion(s)}})
      .catch(e => {if(!controller.signal.aborted)setError(e.message)})
    return () => controller.abort()
  },[mesa])
  useEffect(() => {if(configurando)dialog.current?.showModal()},[configurando])
  useEffect(() => {if(comentando)comentarioDialog.current?.showModal()},[comentando])
  useEffect(() => {
    if(!cambios)return
    const advertir=(e:BeforeUnloadEvent) => {e.preventDefault();e.returnValue=''}
    window.addEventListener('beforeunload',advertir)
    return () => window.removeEventListener('beforeunload',advertir)
  },[cambios])
  const categorias=Array.from(new Map(productos.map(p => [p.id_categoria,p.categoria])).entries())
  const filtrados=productos.filter(p => (categoria===null || p.id_categoria===categoria) && p.nombre.toLocaleLowerCase().includes(buscar.trim().toLocaleLowerCase()))
  const total=lineas.reduce((s,l) => s+l.precio*l.cantidad,0)
  function agregar(producto:Producto,elegidas:Opcion[]=[]) {
    if(ocupado || !pedido?.puede_editar)return
    const indice=lineas.findIndex(l => !l.enviada && l.id_presentacion===producto.id && firma(l.opciones)===firma(elegidas))
    if(indice>=0 && lineas[indice].cantidad>=99){setError('Máximo 99 unidades por línea.');return}
    if(indice<0 && pendientes.length>=100){setError('Máximo 100 líneas por envío.');return}
    setLineas(actual => {
      const i=actual.findIndex(l => !l.enviada && l.id_presentacion===producto.id && firma(l.opciones)===firma(elegidas))
      return i<0 ? [...actual,{id_presentacion:producto.id,nombre:producto.nombre,precio:producto.precio,cantidad:1,comentario:'',opciones:[...elegidas],enviada:false}]
        : actual.map((l,n) => n===i ? {...l,cantidad:Math.min(99,l.cantidad+1)}:l)
    })
    setSeleccion(indice<0 ? lineas.length:indice);setCambios(true);setMensaje('');setError('')
  }
  function tocar(producto:Producto) {
    if(ocupado || !pedido?.puede_editar)return
    const existente=lineas.find(l => !l.enviada && l.id_presentacion===producto.id)
    if(existente){agregar(producto,existente.opciones);return}
    if(producto.grupo?.opciones.length){setConfigurando(producto);setOpciones([])}
    else agregar(producto)
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
      if(pedido.puede_editar && pedido.id_borrador!==null)await consultar(`mesas/${mesa}/pedido`,{version:pedido.version},undefined,'DELETE')
      setCambios(false);navigate('/salon')
    } catch(e){setError(e instanceof Error ? e.message:'No se pudo cancelar')}
    finally {enProceso.current=false;setOcupado(false)}
  }
  async function enviar() {
    if(!pedido?.puede_editar || enProceso.current || !pendientes.length)return
    enProceso.current=true;setOcupado(true);setError('');setMensaje('')
    try {
      const p:Pedido=await consultar(`mesas/${mesa}/pedido`,{version:pedido.version,enviar:true,envio_clave:envioClave.current,
        lineas:pendientes.map(l => ({id_presentacion:l.id_presentacion,cantidad:l.cantidad,comentario:l.comentario,opciones:l.opciones.map(o => o.id)}))})
      setPedido(p);setLineas(p.lineas);setSeleccion(null);setCambios(false);envioClave.current=crypto.randomUUID()
      navigate('/salon')
    } catch(e){setError(e instanceof Error ? e.message:'No se pudo enviar')}
    finally {enProceso.current=false;setOcupado(false)}
  }
  return <main className="salon-order">
    <header><h1>Salón {sesion?.local} · {mesa}</h1><span>{sesion?.usuario}</span></header>
    {error && <div className="order-alert" role="alert"><p>{error}</p><button onClick={() => window.location.reload()}>Volver a cargar</button></div>}
    {mensaje && <p role="status" className="order-message">{mensaje}</p>}
    {!pedido ? !error && <p role="status">Cargando pedido…</p> : <div className="order-workspace">
      <section className="order-catalog"><h2>Carta</h2>
        <nav aria-label="Categorías de carta"><button aria-pressed={categoria===null} onClick={() => setCategoria(null)}>Todas</button>
          {categorias.map(([id,nombre]) => <button key={id} aria-pressed={categoria===id} onClick={() => setCategoria(id)}>{nombre}</button>)}</nav>
        <label className="order-search">Buscar producto<input type="search" placeholder="Escribe el nombre" value={buscar} onChange={e => setBuscar(e.target.value)} /></label>
        <div className="order-products">{filtrados.map(p => <button key={p.id} disabled={ocupado || !pedido.puede_editar} onClick={() => tocar(p)}><strong>{p.nombre}</strong><span>{dinero(p.precio)}</span></button>)}</div>
        {!filtrados.length && <p>No hay productos disponibles para esta búsqueda.</p>}
      </section>
      <aside className="order-cart"><h2>Pedido · {mesa}</h2><p>{pendientes.reduce((s,l) => s+l.cantidad,0)} unidades por enviar</p>
        <div className="order-lines" role="group" aria-label="Productos del pedido">
          {!lineas.length && <p>Toca un producto para agregar una unidad.</p>}
          {lineas.map((l,i) => <button type="button" className={`order-line-select ${l.enviada ? 'is-sent':''}`} key={i}
            disabled={ocupado} aria-pressed={seleccion===i} onClick={() => setSeleccion(i)}>
            <span className="order-line-heading"><strong>{l.cantidad} × {l.nombre}</strong><b>{dinero(l.cantidad*l.precio)}</b></span>
            <span className="order-line-status">{l.enviada ? 'Enviado':'Por enviar'}</span>
            {l.opciones.length>0 && <span>Opciones: {l.opciones.map(o => o.nombre).join(', ')}</span>}
            {l.comentario && <span className="order-comment"><strong>Comentario:</strong> {l.comentario}</span>}
          </button>)}
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
      salonApi(`mesas/${mesa}/eliminar`,{autorizacion,ids_lineas:lineaSeleccionada?.ids_lineas}).then(d=>{
        setPedido(d.pedido);setLineas(actual=>[...d.pedido.lineas.filter((l:Linea)=>l.enviada),...actual.filter(l=>!l.enviada)]);setSeleccion(null);setMensaje('Producto eliminado con autorización.')
      }).catch(e=>setError(e.message)).finally(()=>{setOcupado(false);enProceso.current=false})
    }}/>}
    {configurando && <dialog ref={dialog} className="order-editor" onCancel={() => setConfigurando(null)}>
      <form onSubmit={e => {e.preventDefault();agregar(configurando,opciones);setConfigurando(null)}}>
        <h2>{configurando.nombre}</h2><p>Escoge hasta {configurando.grupo!.maximo} opciones. {configurando.grupo!.repetir ? 'Puedes repetir.':'Sin repetir.'}</p>
        {configurando.grupo!.opciones.map(o => <div className="order-option" key={o.id}><span>{o.nombre}</span>
          <button type="button" aria-label={`Quitar ${o.nombre}`} disabled={!opciones.some(s => s.id===o.id)} onClick={() => {const copia=[...opciones];copia.splice(copia.findIndex(s => s.id===o.id),1);setOpciones(copia)}}>−</button>
          <span>{opciones.filter(s => s.id===o.id).length}</span>
          <button type="button" aria-label={`Agregar ${o.nombre}`} disabled={opciones.length>=configurando.grupo!.maximo || (!configurando.grupo!.repetir && opciones.some(s => s.id===o.id))} onClick={() => setOpciones([...opciones,o])}>+</button>
        </div>)}
        <footer><button type="button" onClick={() => setConfigurando(null)}>Cancelar</button><button className="primary">Agregar</button></footer>
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
