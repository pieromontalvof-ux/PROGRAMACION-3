import {useEffect, useRef, useState} from 'react'
import {useNavigate, useParams} from 'react-router-dom'
import {CreditCard, Banknote, ReceiptText, CheckCircle2} from 'lucide-react'
import {salonApi} from '../../components/SalonPinDialog'
import {useAuth} from '../../context/AuthContext'
import {documentNames, money, receiptImage, resumenReposiciones, type Receipt, type ReceiptLine} from './receipt'
import './SalonPaymentPage.css'

interface Customer {id_cliente:string; nombre:string; numero_documento:string; tipo_documento:string; tipo_persona:string}

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
  const [type,setType]=useState('BOLETA')
  const [method,setMethod]=useState('')
  const [document,setDocument]=useState('')
  const [customer,setCustomer]=useState('')
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
    const controller=new AbortController()
    salonApi(id ? `comprobantes/${id}` : `mesas/${mesa}/cuenta`,undefined,'GET',controller.signal)
      .then(data=>{if(!controller.signal.aborted){if(id)setReceipt(data);else setAccount(data)}})
      .catch(e=>{if(!controller.signal.aborted)setError(e.message)})
    return ()=>controller.abort()
  },[mesa,id])
  useEffect(()=>{const controller=new AbortController()
    salonApi('clientes/configuracion',undefined,'GET',controller.signal).then(data=>{if(!controller.signal.aborted){setDirectoryReady(data.directorio_disponible);setIdentityReady(!!data.consulta_identidad_externa)}})
      .catch(()=>{})
    return ()=>controller.abort()
  },[])
  async function searchCustomers(){
    setCustomerBusy(true);setCustomerNotice('')
    try{const data=await salonApi(`clientes?q=${encodeURIComponent(document)}&limit=10`)
      setCustomers(data.clientes);if(!data.clientes.length)setCustomerNotice('No hay clientes registrados con ese documento. Puedes ingresar sus datos y guardarlos.')
    }catch(e){setCustomerNotice(e instanceof Error?e.message:'No se pudo buscar el cliente')}
    finally{setCustomerBusy(false)}
  }
  async function saveCustomer(){
    setCustomerBusy(true);setCustomerNotice('')
    try{const data=await salonApi('clientes',{nombre:customer,tipo_persona:personType,tipo_documento:type==='FACTURA'?'RUC':'DNI',numero_documento:document})
      setSelectedCustomer(data.id_cliente);setCustomers([]);setCustomerNotice('Cliente registrado en este local.')
    }catch(e){setCustomerNotice(e instanceof Error?e.message:'No se pudo guardar el cliente')}
    finally{setCustomerBusy(false)}
  }
  async function lookupIdentity(){
    const requestId=++identityRequest.current
    setCustomerBusy(true);setCustomerNotice('')
    try{
      const data=await salonApi('clientes/consultar-documento',{tipo_documento:type==='FACTURA'?'RUC':'DNI',numero_documento:document})
      if(requestId!==identityRequest.current)return
      setCustomer(data.nombre);setSelectedCustomer(null);setCustomers([])
      setCustomerNotice('Datos obtenidos de Factiliza. Revísalos antes de guardar el cliente.')
    }catch(e){if(requestId===identityRequest.current)setCustomerNotice(e instanceof Error?e.message:'No se pudo consultar el documento')}
    finally{setCustomerBusy(false)}
  }
  const ready=account && account.lineas.length>0 && account.id_borrador===null && account.lineas.every(l=>l.enviada)
  async function emit() {
    if(!ready || !method || submitting.current)return
    submitting.current=true;setBusy(true);setError('')
    try {
      const saved:Receipt=await salonApi(`mesas/${mesa}/emitir`,{clave:key.current,revision:account.revision,
        tipo:type,metodo:method,documento:document,cliente:customer,...(selectedCustomer?{id_cliente:selectedCustomer}:{})})
      setReceipt(saved)
      navigate(`/salon/comprobante/${saved.id}`,{replace:true})
    }catch(e){setError(e instanceof Error ? e.message : 'No se pudo registrar el cobro')}
    finally{submitting.current=false;setBusy(false)}
  }
  function exit() {
    sessionStorage.removeItem('salon_token');logout();navigate('/login',{replace:true})
  }
  return <main className="salon-payment">
    <header><div><span>SALÓN · {receipt?.local ?? account?.local ?? ''}</span><h1>{id ? 'Comprobante' : `Pagar mesa ${mesa}`}</h1></div>
      <ReceiptText size={30}/></header>
    {error && <p className="payment-error" role="alert">{error}</p>}
    {!account && !receipt && !error && <p role="status">Cargando…</p>}
    {receipt ? <section className="payment-receipt">
      <p className="payment-success"><CheckCircle2 size={20}/>Cobro registrado · La mesa quedó libre</p>
      <img src={receiptImage(receipt)} alt={`Comprobante interno ${receipt.numero}, mesa ${receipt.mesa}, total pagado ${money(receipt.total)} por ${receipt.metodo.toLowerCase()}`} />
    </section> : account && <div className="payment-workspace">
      <form id="payment-form" onSubmit={e=>{e.preventDefault();void emit()}}>
        <fieldset disabled={busy}><legend>Tipo de comprobante</legend>
          <div className="payment-choices">{Object.entries(documentNames).map(([value,label])=><button key={value} type="button" aria-pressed={type===value}
            onClick={()=>{identityRequest.current++;setType(value);setDocument('');setCustomer('');setSelectedCustomer(null);setCustomers([]);setCustomerNotice('')}}>{label}</button>)}</div>
          <p className="payment-note">Registro interno de cobro. La emisión electrónica a SUNAT aún no está conectada.</p>
          {type!=='BOLETA' && <div className="payment-customer">
            <label>{type==='FACTURA' ? 'RUC' : 'DNI'}<input autoComplete="off" inputMode="numeric" required pattern={type==='FACTURA' ? '[0-9]{11}' : '[0-9]{8}'}
              maxLength={type==='FACTURA' ? 11 : 8} value={document} onChange={e=>{identityRequest.current++;setDocument(e.target.value.replace(/\D/g,''));setSelectedCustomer(null);setCustomers([])}}/></label>
            <label>{type==='FACTURA' ? 'Razón social' : 'Nombres y apellidos'}<input required maxLength={200} value={customer} onChange={e=>{setCustomer(e.target.value);setSelectedCustomer(null)}}/></label>
            <div>
              <button type="button" disabled={!directoryReady||customerBusy||!document} onClick={()=>void searchCustomers()}>Buscar cliente registrado</button>
              <button type="button" disabled={!identityReady||customerBusy||document.length!==(type==='FACTURA'?11:8)} onClick={()=>void lookupIdentity()}>Consultar DNI/RUC</button>
              {!identityReady&&<p className="payment-note">Consulta externa pendiente de configurar el token de Factiliza. Puedes registrar al cliente manualmente.</p>}
              {type==='FACTURA'&&<label>Tipo de persona<select value={personType} onChange={e=>setPersonType(e.target.value)}><option value="NATURAL">Persona natural con RUC</option><option value="JURIDICA">Persona jur?dica</option></select></label>}
              <button type="button" disabled={!directoryReady||customerBusy||!customer||!document||!!selectedCustomer} onClick={()=>void saveCustomer()}>Guardar cliente</button>
              {!!customers.length&&<ul>{customers.filter(c=>c.tipo_documento===(type==='FACTURA'?'RUC':'DNI')).map(c=><li key={c.id_cliente}><button type="button" onClick={()=>{setSelectedCustomer(c.id_cliente);setCustomer(c.nombre);setDocument(c.numero_documento);setPersonType(c.tipo_persona);setCustomers([])}}>{c.nombre} ? {c.numero_documento}</button></li>)}</ul>}
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
    <footer>{id ? <><button className="payment-exit" onClick={exit}>Salir</button><button className="payment-primary" onClick={()=>navigate('/salon',{replace:true})}>Regresar al salón</button></>
      : <><button disabled={busy} onClick={()=>navigate(`/salon/mesa/${mesa}`,{replace:true})}>Cancelar</button>
        <button className="payment-primary" type="submit" form="payment-form" disabled={busy||!ready||!method}>{busy ? 'Registrando…' : 'Emitir'}</button></>}</footer>
  </main>
}
