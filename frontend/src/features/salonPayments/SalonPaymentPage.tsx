import {useEffect, useRef, useState} from 'react'
import {useNavigate, useParams} from 'react-router-dom'
import {CreditCard, Banknote, ReceiptText, CheckCircle2} from 'lucide-react'
import {salonApi} from '../../services/salonService'
import { useAuth } from '../../context/authState'
import {documentNames, money, resumenReposiciones, type Receipt, type ReceiptLine} from './receipt'
import './SalonPaymentPage.css'
import {FactApiPanel} from '../../components/FactApiPanel'
import {FactApiPreviewPane} from '../../components/FactApiPdfPreview'

interface Customer {id_cliente:string; nombre:string; numero_documento:string; tipo_documento:string; tipo_persona:string; email?:string|null; telefono?:string|null; direccion?:string|null}

interface Account {
  local:string; usuario:string; mesa:string; revision:string; total:number
  id_borrador:number|null; lineas:ReceiptLine[]
}

export function SalonPaymentPage() {
  const {mesa, id}=useParams()
  return <PaymentWorkspace key={`${mesa ?? ''}:${id ?? ''}`} mesa={mesa} id={id}/>
}

function PaymentWorkspace({mesa,id}:{mesa?:string;id?:string}) {
  const navigate=useNavigate()
  const {logout}=useAuth()
  const [account,setAccount]=useState<Account|null>(null)
  const [receipt,setReceipt]=useState<Receipt|null>(null)
  const receiptDialog=useRef<HTMLDialogElement>(null)
  const [previewTarget,setPreviewTarget]=useState<HTMLDivElement|null>(null)
  const [type,setType]=useState('BOLETA')
  const [method,setMethod]=useState('')
  const [document,setDocument]=useState('')
  const [customer,setCustomer]=useState('')
  const [email,setEmail]=useState('')
  const [telefono,setTelefono]=useState('')
  const [direccion,setDireccion]=useState('')
  const [selectedCustomer,setSelectedCustomer]=useState<string|null>(null)
  const [customers,setCustomers]=useState<Customer[]>([])
  const [personType,setPersonType]=useState('NATURAL')
  const [customerBusy,setCustomerBusy]=useState(false)
  const [customerNotice,setCustomerNotice]=useState('')
  const [directoryReady,setDirectoryReady]=useState(false)
  const [identityReady,setIdentityReady]=useState(false)
  const identityRequest=useRef(0)
  const [error,setError]=useState('')
  const [busy,setBusy]=useState(false)
  const submitting=useRef(false)
  const key=useRef(crypto.randomUUID())
  useEffect(()=>{
    const dialog=receiptDialog.current
    if(receipt&&!id&&dialog&&!dialog.open){
      if(typeof dialog.showModal==='function')dialog.showModal()
      else dialog.setAttribute('open','')
    }
  },[receipt,id])
  useEffect(()=>{
    const controller=new AbortController()
    salonApi(id ? `comprobantes/${id}` : `mesas/${mesa}/cuenta`,undefined,'GET',controller.signal)
      .then(data=>{if(!controller.signal.aborted){if(id)setReceipt(data);else setAccount(data)}})
      .catch(e=>{if(!controller.signal.aborted)setError(e.message)})
    return ()=>controller.abort()
  },[mesa,id])
  useEffect(()=>{if(id)return
    const controller=new AbortController()
    salonApi('clientes/configuracion',undefined,'GET',controller.signal).then(data=>{if(!controller.signal.aborted){setDirectoryReady(data.directorio_disponible);setIdentityReady(!!data.consulta_identidad_externa)}})
      .catch(()=>{})
    return ()=>controller.abort()
  },[id])
  async function searchCustomers(){
    setCustomerBusy(true);setCustomerNotice('')
    try{const data=await salonApi(`clientes?q=${encodeURIComponent(document)}&limit=10`)
      setCustomers(data.clientes);if(!data.clientes.length)setCustomerNotice('No hay clientes registrados con ese documento. Puedes ingresar sus datos y guardarlos.')
    }catch(e){setCustomerNotice(e instanceof Error?e.message:'No se pudo buscar el cliente')}
    finally{setCustomerBusy(false)}
  }
  const contacto={email:email.trim() || null,telefono:telefono.trim() || null,direccion:direccion.trim() || null}
  async function saveCustomer(){
    setCustomerBusy(true);setCustomerNotice('')
    const requestId=++identityRequest.current
    try{
      if(selectedCustomer){
        await salonApi(`clientes/${selectedCustomer}/contacto`,contacto,'PATCH')
      }else{
        const data=await salonApi('clientes',{nombre:customer,tipo_persona:personType,
          tipo_documento:type==='FACTURA'?'RUC':'DNI',numero_documento:document,...contacto})
        if(requestId===identityRequest.current)setSelectedCustomer(data.id_cliente)
      }
      if(requestId===identityRequest.current){
        setCustomers([])
        setCustomerNotice(selectedCustomer?'Contacto actualizado.':'Cliente guardado en el directorio compartido.')
      }
    }catch(e){
      if(requestId===identityRequest.current)setCustomerNotice(e instanceof Error?e.message:'No se pudo guardar el cliente')
    }finally{setCustomerBusy(false)}
  }
  async function lookupIdentity(){
    const requestId=++identityRequest.current
    setCustomerBusy(true);setCustomerNotice('')
    try{
      const data=await salonApi('clientes/consultar-documento',{tipo_documento:type==='FACTURA'?'RUC':'DNI',numero_documento:document})
      if(requestId!==identityRequest.current)return
      setCustomer(data.nombre);setSelectedCustomer(null);setCustomers([])
      if(data.direccion)setDireccion(actual=>actual || data.direccion)
      setCustomerNotice('Datos obtenidos de Factiliza. Revísalos antes de guardar el cliente.')
    }catch(e){if(requestId===identityRequest.current)setCustomerNotice(e instanceof Error?e.message:'No se pudo consultar el documento')}
    finally{setCustomerBusy(false)}
  }
  const ready=account && account.lineas.length>0 && account.id_borrador===null && account.lineas.every(l=>l.enviada)
  async function emit() {
    if(receipt || !ready || !method || submitting.current)return
    submitting.current=true;setBusy(true);setError('')
    try {
      const saved:Receipt=await salonApi(`mesas/${mesa}/emitir`,{clave:key.current,revision:account.revision,
        tipo:type,metodo:method,documento:document,cliente:customer,
        ...(type!=='BOLETA'?{contacto}:{}),...(selectedCustomer?{id_cliente:selectedCustomer}:{})})
      setReceipt(saved)
    }catch(e){setError(e instanceof Error ? e.message : 'No se pudo registrar el cobro')}
    finally{submitting.current=false;setBusy(false)}
  }
  function exit() {
    sessionStorage.removeItem('salon_token');logout();navigate('/login',{replace:true})
  }
  const regresarAlSalon=()=>navigate('/salon',{replace:true})
  const comprobante=receipt ? <>
    <p className="payment-success"><CheckCircle2 size={20}/>Cobro registrado</p>
    <p className="payment-note">Mesa {receipt.mesa} · {money(receipt.total)} · {receipt.metodo === 'EFECTIVO' ? 'Efectivo' : 'Tarjeta'}{receipt.prueba && ' · Venta simulada'}</p>
    <FactApiPanel key={receipt.id} origin="VENTA" source={receipt.id} salon showAvailability previewTarget={previewTarget} autoPreviewFormat="A4"/>
  </> : null
  return <main className="salon-payment">
    <header><div><span>SALÓN · {receipt?.local ?? account?.local ?? ''}</span><h1>{id ? 'Cobro y comprobante' : `Cobrar mesa ${mesa}`}</h1></div>
      <ReceiptText size={30}/></header>
    {error && <p className="payment-error" role="alert">{error}</p>}
    {!account && !receipt && !error && <p role="status">Cargando…</p>}
    {id ? receipt && <section className="payment-receipt payment-receipt-columns">
      <div className="payment-receipt-info">{comprobante}</div>
      <FactApiPreviewPane onTarget={setPreviewTarget}/>
    </section> : account && <div className="payment-workspace">
      <form id="payment-form" onSubmit={e=>{e.preventDefault();void emit()}}>
        <fieldset disabled={busy}><legend>Tipo de comprobante</legend>
          <div className="payment-choices">{Object.entries(documentNames).map(([value,label])=><button key={value} type="button" aria-pressed={type===value}
            onClick={()=>{identityRequest.current++;setType(value);setDocument('');setCustomer('');setEmail('');setTelefono('');setDireccion('');setSelectedCustomer(null);setCustomers([]);setCustomerNotice('')}}>{label}</button>)}</div>
          <p className="payment-note">Después de confirmar el cobro podrás descargar el comprobante de prueba en PDF A4 o ticket de 80 mm.</p>
          {type!=='BOLETA' && <div className="payment-customer">
            <label>{type==='FACTURA' ? 'RUC' : 'DNI'}<input autoComplete="off" inputMode="numeric" required pattern={type==='FACTURA' ? '[0-9]{11}' : '[0-9]{8}'}
              maxLength={type==='FACTURA' ? 11 : 8} value={document} onChange={e=>{identityRequest.current++;setDocument(e.target.value.replace(/\D/g,''));setEmail('');setTelefono('');setDireccion('');setSelectedCustomer(null);setCustomers([])}}/></label>
            <label>{type==='FACTURA' ? 'Razón social' : 'Nombres y apellidos'}<input required maxLength={200} value={customer} onChange={e=>{identityRequest.current++;setCustomer(e.target.value);setSelectedCustomer(null)}}/></label>
            <div className="payment-contact">
              <label>Correo (opcional)<input inputMode="email" autoComplete="off" maxLength={200} value={email}
                onChange={e=>setEmail(e.target.value)} /></label>
              <label>Celular o teléfono (opcional)<input type="tel" autoComplete="off" maxLength={40} value={telefono}
                onChange={e=>setTelefono(e.target.value)} /></label>
              <label className="payment-address">Dirección (opcional)<input autoComplete="off" maxLength={300} value={direccion}
                onChange={e=>setDireccion(e.target.value)} /></label>
              <p className="payment-note">Estos datos se usan en el comprobante. Pulsa Guardar cliente o Guardar contacto para conservarlos en el directorio.</p>
            </div>
            <div>
              <button type="button" disabled={!directoryReady||customerBusy||!document} onClick={()=>void searchCustomers()}>Buscar cliente registrado</button>
              <button type="button" disabled={!identityReady||customerBusy||document.length!==(type==='FACTURA'?11:8)} onClick={()=>void lookupIdentity()}>Consultar DNI/RUC</button>
              {!identityReady&&<p className="payment-note">Consulta externa pendiente de configurar el token de Factiliza. Puedes registrar al cliente manualmente.</p>}
              {type==='FACTURA'&&<label>Tipo de persona<select value={personType} onChange={e=>setPersonType(e.target.value)}><option value="NATURAL">Persona natural con RUC</option><option value="JURIDICA">Persona jur?dica</option></select></label>}
              <button type="button" disabled={!directoryReady||customerBusy||!customer||!document} onClick={()=>void saveCustomer()}>{selectedCustomer?'Guardar contacto':'Guardar cliente'}</button>
              {!!customers.length&&<ul>{customers.filter(c=>c.tipo_documento===(type==='FACTURA'?'RUC':'DNI')).map(c=><li key={c.id_cliente}><button type="button" onClick={()=>{setSelectedCustomer(c.id_cliente);setCustomer(c.nombre);setDocument(c.numero_documento);setPersonType(c.tipo_persona);setEmail(c.email ?? '');setTelefono(c.telefono ?? '');setDireccion(c.direccion ?? '');setCustomers([])}}>{c.nombre} ? {c.numero_documento}</button></li>)}</ul>}
              {customerNotice&&<p role="status">{customerNotice}</p>}
            </div>
          </div>}
        </fieldset>
        <fieldset disabled={busy}><legend>Método de pago</legend><div className="payment-choices">
          <button type="button" aria-pressed={method==='TARJETA'} onClick={()=>setMethod('TARJETA')}><CreditCard size={23}/>Tarjeta</button>
          <button type="button" aria-pressed={method==='EFECTIVO'} onClick={()=>setMethod('EFECTIVO')}><Banknote size={23}/>Efectivo</button>
        </div><p className="payment-note">Selecciona el medio con el que recibiste el pago{method==='TARJETA' ? ' en el POS' : ''}.</p></fieldset>
        {!ready && <p role="alert" className="payment-error">La cuenta debe tener productos enviados y ningún borrador pendiente. Regresa a la mesa para revisarla.</p>}
      </form>
      <aside className="payment-account"><span className="payment-eyebrow">RESUMEN DE LA CUENTA</span><h2>Mesa {account.mesa}</h2>
        <div className="payment-items">{account.lineas.filter(line => !line.id_barra_libre).map((line,i)=><article key={line.ids_lineas?.[0] ?? i}><div><strong>{line.cantidad} × {line.nombre}</strong><span>{money(line.cantidad*line.precio)}</span></div>
          {!!line.opciones.length && <small>{line.opciones.map(o=>o.nombre).join(', ')}</small>}
          {line.selecciones_promocion?.map((selection,index)=><small key={index}>Incluye {selection.nombre}{selection.opciones.length ? ` · Salsa: ${selection.opciones.map(o=>o.nombre).join(', ')}`:''}</small>)}
          {resumenReposiciones(line,account.lineas) && <small>Reposiciones: {resumenReposiciones(line,account.lineas)}</small>}
          {line.comentario && <small>{line.comentario}</small>}</article>)}</div>
        <div className="payment-total"><span>Total a pagar</span><strong>{money(account.total)}</strong></div>
      </aside>
    </div>}
    {receipt&&!id&&<dialog ref={receiptDialog} className="payment-receipt-dialog" aria-labelledby="payment-receipt-title"
      onCancel={event=>{event.preventDefault();regresarAlSalon()}}>
      <div className="payment-receipt-columns">
        <div className="payment-receipt-info">
          <h2 id="payment-receipt-title">Comprobante de la venta</h2>
          {comprobante}
          <div className="payment-dialog-actions"><button className="payment-exit" onClick={exit}>Salir</button>
            <button className="payment-primary" onClick={regresarAlSalon}>Regresar al salón</button></div>
        </div>
        <FactApiPreviewPane onTarget={setPreviewTarget}/>
      </div>
    </dialog>}
    <footer>{id ? <><button className="payment-exit" onClick={exit}>Salir</button><button className="payment-primary" onClick={regresarAlSalon}>Regresar al salón</button></>
      : <><button disabled={busy} onClick={()=>navigate(`/salon/mesa/${mesa}`,{replace:true})}>Cancelar</button>
        <button className="payment-primary" type="submit" form="payment-form" disabled={busy||!!receipt||!ready||!method}>{busy ? 'Registrando…' : 'Confirmar cobro'}</button></>}</footer>
  </main>
}
