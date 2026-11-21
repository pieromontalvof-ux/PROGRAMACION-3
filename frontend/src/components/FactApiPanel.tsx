import {useEffect,useState} from 'react'
import './FactApiPanel.css'

type Operation={id_operacion:string;version:number;estado:string;intentos:number;obsoleto?:boolean;ultimo_error?:string;numero?:string;archivos:{id:string;formato:string}[]}
type Status={disponible:boolean;modo?:string;operaciones:Operation[];originales?:{id_adjunto:string;formato:string}[]}
const names:Record<string,string>={PENDIENTE:'En cola',PROCESANDO:'Generando documento',REINTENTO:'Esperando reintento',COMPLETADO:'PDF disponible',RECHAZADO:'Datos rechazados',BLOQUEADO:'Requiere configuración',REVISION:'Requiere revisión'}

export function FactApiPanel({origin,source,token,salon=false}:{origin:'VENTA'|'COMPRA';source:number;token?:string;salon?:boolean}) {
  const [status,setStatus]=useState<Status|null>(null)
  const [loadedScope,setLoadedScope]=useState('')
  const [error,setError]=useState('')
  const [busy,setBusy]=useState(false)
  const [revision,setRevision]=useState(0)
  const auth=token??sessionStorage.getItem('salon_token')??''
  const base=(import.meta.env.VITE_API_URL??'http://127.0.0.1:5000/api')+(salon?'/salon/fact-api':'/v1/fact-api')
  const scope=`${auth}:${base}:${origin}:${source}`
  useEffect(()=>{
    if(!auth)return
    const controller=new AbortController()
    let timer:ReturnType<typeof setTimeout>
    async function load(){
      try{
        const response=await fetch(`${base}/${origin}/${source}`,{headers:{Authorization:`Bearer ${auth}`},signal:controller.signal})
        if(!response.ok)return
        const data=await response.json() as Status
        if(controller.signal.aborted)return
        setStatus(data)
        setLoadedScope(`${auth}:${base}:${origin}:${source}`)
        if(data.operaciones?.some(o=>['PENDIENTE','PROCESANDO','REINTENTO'].includes(o.estado)))timer=setTimeout(()=>void load(),4000)
      }catch{/* Existing pages remain usable when the optional integration is unavailable. */}
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
  if(loadedScope!==scope||!status?.disponible)return null
  const operation=status.operaciones[0]
  return <section className="fact-api-panel" aria-label="Documento fact_api">
    <strong>Documento de prueba · fact_api</strong><p>Sin validez tributaria. Sin envío a SUNAT.{origin==='COMPRA'?' Vista interna; no sustituye el original del proveedor.':''}</p>
    {operation?<><p role="status">{operation.obsoleto?'Documento histórico de una fuente modificada o anulada':names[operation.estado]??operation.estado}{operation.numero?` · ${operation.numero}`:''}</p><small>Seguimiento: {operation.id_operacion} · Intentos: {operation.intentos}</small>
      {operation.ultimo_error&&<p>{operation.ultimo_error}</p>}
      <div>{operation.archivos.map(file=><button type="button" disabled={busy} key={file.id} onClick={()=>void download(file)}>Descargar PDF {file.formato}</button>)}</div>
      {!operation.obsoleto&&['REVISION','REINTENTO','BLOQUEADO','RECHAZADO'].includes(operation.estado)&&<button type="button" disabled={busy} onClick={()=>void retry(operation.id_operacion)}>Reintentar con la misma referencia</button>}
    </>:<button type="button" disabled={busy} onClick={()=>void generate()}>{busy?'Encolando…':'Generar PDF de prueba'}</button>}
    {origin==='COMPRA'&&!salon&&<div><label>Adjuntar original del proveedor (PDF o XML, máximo 5 MB)<input type="file" accept=".pdf,.xml" disabled={busy} onChange={e=>{const file=e.target.files?.[0];if(file)void upload(file);e.target.value=''}}/></label>
      {status.originales?.map(file=><button type="button" key={file.id_adjunto} disabled={busy} onClick={()=>void download({id:file.id_adjunto,formato:file.formato},true)}>Descargar original {file.formato}</button>)}</div>}
    {error&&<p role="alert">{error}</p>}
  </section>
}
