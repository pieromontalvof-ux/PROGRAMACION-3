import { API_BASE_URL } from '../config'
import {useCallback,useEffect,useRef,useState} from 'react'
import {createPortal} from 'react-dom'
import {FactApiPdfPreview} from './FactApiPdfPreview'
import './FactApiPanel.css'

type Operation={id_operacion:string;version:number;estado:string;intentos:number;obsoleto?:boolean;ultimo_error?:string;numero?:string;archivos:{id:string;formato:string}[]}
type Status={disponible:boolean;modo?:string;operaciones:Operation[];originales?:{id_adjunto:string;formato:string}[]}
const names:Record<string,string>={PENDIENTE:'En cola',PROCESANDO:'Generando documento',REINTENTO:'Esperando reintento',COMPLETADO:'PDF disponible',RECHAZADO:'Datos rechazados',BLOQUEADO:'Requiere configuración',REVISION:'Requiere revisión'}

export function FactApiPanel({origin,source,token,salon=false,showAvailability=false,previewTarget,previewModal=false,autoPreviewFormat}:{
  origin:'VENTA'|'COMPRA';source:number;token?:string;salon?:boolean;showAvailability?:boolean
  previewTarget?: HTMLDivElement | null
  previewModal?: boolean
  autoPreviewFormat?: 'A4' | '80mm'
}) {
  const [status,setStatus]=useState<Status|null>(null)
  const [loadedScope,setLoadedScope]=useState('')
  const [failedScope,setFailedScope]=useState('')
  const [error,setError]=useState('')
  const [busy,setBusy]=useState(false)
  const [revision,setRevision]=useState(0)
  const [preview,setPreview]=useState<{scope:string;id:string}|null>(null)
  const [originalPreview,setOriginalPreview]=useState<{scope:string;id:string}|null>(null)
  const previewButton=useRef<HTMLButtonElement|null>(null)
  const dialogRef=useRef<HTMLDialogElement|null>(null)
  const mountDialog=useCallback((dialog:HTMLDialogElement|null)=>{
    dialogRef.current=dialog
    if(!dialog||dialog.open)return
    if(typeof dialog.showModal==='function')dialog.showModal()
    else dialog.setAttribute('open','')
  },[])
  const auth=token??sessionStorage.getItem('salon_token')??''
  const base=(API_BASE_URL)+(salon?'/salon/fact-api':'/v1/fact-api')
  const scope=`${auth}:${base}:${origin}:${source}`
  useEffect(()=>{
    if(!auth)return
    const controller=new AbortController()
    let timer:ReturnType<typeof setTimeout>
    async function load(){
      try{
        const response=await fetch(`${base}/${origin}/${source}`,{headers:{Authorization:`Bearer ${auth}`},signal:controller.signal})
        if(!response.ok)throw new Error('No se pudo consultar el comprobante')
        const data=await response.json() as Status
        if(controller.signal.aborted)return
        setStatus(data)
        setLoadedScope(`${auth}:${base}:${origin}:${source}`)
        setFailedScope('')
        if(data.operaciones?.some(o=>['PENDIENTE','PROCESANDO','REINTENTO'].includes(o.estado)))timer=setTimeout(()=>void load(),4000)
      }catch{
        if(!controller.signal.aborted)setFailedScope(`${auth}:${base}:${origin}:${source}`)
      }
    }
    void load()
    return ()=>{controller.abort();clearTimeout(timer)}
  },[base,origin,source,auth,revision])
  async function generate(){
    setBusy(true);setError('')
    try{
      const response=await fetch(`${base}/${origin}/${source}`,{method:'POST',headers:{Authorization:`Bearer ${auth}`}})
      if(!response.ok){const data=await response.json();throw new Error(data.mensaje??'No se pudo encolar el documento.')}
      setRevision(v=>v+1)
    }catch(e){setError(e instanceof Error?e.message:'No se pudo generar.')}
    finally{setBusy(false)}
  }
  async function download(file:{id:string;formato:string},original=false){
    setBusy(true);setError('')
    try{
      const response=await fetch(`${base}/${original?'originales':'archivos'}/${file.id}`,{headers:{Authorization:`Bearer ${auth}`}})
      if(!response.ok)throw new Error('No se pudo descargar el archivo autorizado.')
      const url=URL.createObjectURL(await response.blob())
      const link=document.createElement('a');link.href=url;link.download=`${original?'original':'documento'}_${source}_${file.formato}.${file.formato==='XML'?'xml':'pdf'}`;link.click()
      setTimeout(()=>URL.revokeObjectURL(url),1000)
    }catch(e){setError(e instanceof Error?e.message:'No se pudo descargar.')}
    finally{setBusy(false)}
  }
  async function retry(identity:string){
    setBusy(true);setError('')
    try{
      const response=await fetch(`${base}/operaciones/${identity}/reintentar`,{method:'POST',headers:{Authorization:`Bearer ${auth}`}})
      if(!response.ok)throw new Error('No se pudo reintentar esta operación.')
      setRevision(v=>v+1)
    }catch(e){setError(e instanceof Error?e.message:'Error de reintento.')}
    finally{setBusy(false)}
  }
  async function upload(file:File){
    setBusy(true);setError('')
    try{
      if(file.size>5*1024*1024)throw new Error('El original debe tener como máximo 5 MB.')
      const data=new FormData();data.append('archivo',file);data.append('formato',file.name.toLowerCase().endsWith('.xml')?'XML':'PDF')
      const response=await fetch(`${base}/COMPRA/${source}/originales`,{method:'POST',headers:{Authorization:`Bearer ${auth}`},body:data})
      if(!response.ok){const result=await response.json();throw new Error(result.mensaje??'No se pudo adjuntar el original.')}
      setRevision(v=>v+1)
    }catch(e){setError(e instanceof Error?e.message:'Error al adjuntar.')}
    finally{setBusy(false)}
  }
  if(loadedScope!==scope||!status?.disponible||(showAvailability&&failedScope===scope)){
    if(!showAvailability||!auth)return null
    return <section className="fact-api-panel" aria-label="Comprobante de prueba">
      <strong>Comprobante de prueba</strong>
      {failedScope===scope?<><p role="status">El cobro está registrado. No se pudo consultar el comprobante.</p>
        <button type="button" onClick={()=>setRevision(v=>v+1)}>Volver a consultar</button></>
      :loadedScope===scope?<p role="status">La generación de comprobantes de prueba no está disponible en este local.</p>
      :<p role="status">Consultando el comprobante…</p>}
    </section>
  }
  const operation=status.operaciones[0]
  const archivos=operation?.archivos ?? []
  const visto=preview?.scope===scope ? archivos.find(file=>file.id===preview.id)
    : autoPreviewFormat&&!operation?.obsoleto&&operation?.estado==='COMPLETADO'
      ? archivos.find(file=>file.formato===autoPreviewFormat) : undefined
  const formato=(value:string)=>value==='80mm'?'ticket de 80 mm':'PDF '+value
  function cerrarVista(){
    dialogRef.current?.close?.()
    setPreview({scope,id:''})
    previewButton.current?.focus({preventScroll:true})
  }
  const acciones=(enModal=false)=><div className="fact-api-actions">
    <div role="group" aria-label="Vista previa">{archivos.map(file=><button type="button" key={file.id}
      aria-pressed={visto?.id===file.id} onClick={event=>{
        if(!enModal)previewButton.current=event.currentTarget
        setPreview({scope,id:file.id})
      }}>Ver {formato(file.formato)}</button>)}</div>
    <div role="group" aria-label="Descargas">{archivos.map(file=><button type="button" disabled={busy}
      key={file.id} onClick={()=>void download(file)}>Descargar {formato(file.formato)}</button>)}</div>
  </div>
  const archivo=visto&&<FactApiPdfPreview key={visto.id} url={`${base}/archivos/${visto.id}`} token={auth} format={formato(visto.formato)}/>
  const visor=visto && <div className="fact-api-preview-section">
    <div className="fact-api-preview-toolbar">
      <strong>{formato(visto.formato)}</strong>
      <button type="button" onClick={cerrarVista}>Cerrar vista previa</button>
    </div>
    {archivo}
  </div>
  return <section className="fact-api-panel" aria-label="Documento fact_api">
    <div className="fact-api-heading"><strong>{origin==='VENTA'?'Comprobante':'Factura recibida'}</strong>
      <span>{origin==='VENTA'?'Sin validez tributaria':'Original del proveedor y representación interna'}</span></div>
    {operation?<><p role="status">{operation.obsoleto?'Documento histórico de una fuente modificada o anulada':names[operation.estado]??operation.estado}{operation.numero?` · ${operation.numero}`:''}</p>
      {operation.ultimo_error&&<p>{operation.ultimo_error}</p>}
      {!!archivos.length&&<>
        {acciones()}
        {previewModal ? visto && <dialog className="fact-api-preview-dialog" ref={mountDialog}
          aria-label="Vista previa del comprobante" onCancel={event=>{event.preventDefault();cerrarVista()}}>
          <div className="fact-api-preview-dialog-layout">
            <div className="fact-api-preview-dialog-header"><strong>Comprobante {operation.numero}</strong>
              <button className="fact-api-preview-exit" type="button" onClick={cerrarVista}>Salir</button></div>
            {acciones(true)}
            {error&&<p role="alert">{error}</p>}
            {archivo}
          </div>
        </dialog> : visor && (previewTarget ? createPortal(visor,previewTarget) : previewTarget===undefined ? visor : null)}
      </>}
      {!operation.obsoleto&&['REVISION','REINTENTO','BLOQUEADO','RECHAZADO'].includes(operation.estado)&&<button type="button" disabled={busy} onClick={()=>void retry(operation.id_operacion)}>Reintentar con la misma referencia</button>}
    </>:<button type="button" disabled={busy} onClick={()=>void generate()}>{busy?'Encolando…':origin==='VENTA'?'Generar comprobante de prueba':'Generar PDF de prueba'}</button>}
    {origin==='COMPRA'&&<p>El PDF generado resume la recepción. El comprobante emitido por el proveedor es el archivo original adjunto.</p>}
    {origin==='COMPRA'&&!salon&&<div><label>Adjuntar original del proveedor (PDF o XML, máximo 5 MB)<input type="file" accept=".pdf,.xml" disabled={busy} onChange={e=>{const file=e.target.files?.[0];if(file)void upload(file);e.target.value=''}}/></label>
      {status.originales?.map(file=><span key={file.id_adjunto}>
        {file.formato==='PDF'&&<button type="button" onClick={()=>setOriginalPreview({scope,id:file.id_adjunto})}>Ver original PDF</button>}
        <button type="button" disabled={busy} onClick={()=>void download({id:file.id_adjunto,formato:file.formato},true)}>Descargar original {file.formato}</button></span>)}</div>}
    {originalPreview?.scope===scope&&status.originales?.some(file=>file.id_adjunto===originalPreview.id&&file.formato==='PDF')&&<div>
      <button type="button" onClick={()=>setOriginalPreview(null)}>Cerrar original</button>
      <FactApiPdfPreview key={originalPreview.id} url={`${base}/originales/${originalPreview.id}`} token={auth} format="original del proveedor"/>
    </div>}
    {error&&!(previewModal&&visto)&&<p role="alert">{error}</p>}
  </section>
}
