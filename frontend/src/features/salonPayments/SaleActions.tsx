import {useState} from 'react'
import {salonApi} from '../../services/salonService'
import {documentosCliente, type TipoDocumentoCliente} from './documentosCliente'
import {type Receipt} from './receipt'
export function SaleActions({receipt,onSaved}:{receipt:Receipt;onSaved:()=>void}){
 const [action,setAction]=useState(''),[motivo,setMotivo]=useState(''),[referencia,setReferencia]=useState('')
 const [tipo,setTipo]=useState('BOLETA_ELECTRONICA'),[documento,setDocumento]=useState(''),[cliente,setCliente]=useState('')
 const [tipoDocumento,setTipoDocumento]=useState<TipoDocumentoCliente>('DNI')
 const formato=documentosCliente[tipoDocumento]
 const [busy,setBusy]=useState(false),[error,setError]=useState('')
 const submit=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);setError('');try{
  await salonApi(`comprobantes/${receipt.id}/${action}`,{motivo,referencia,tipo,tipo_documento:tipoDocumento,documento,cliente,version:receipt.historial?.length??0})
  setAction('');onSaved()
 }catch(e){setError(e instanceof Error?e.message:'No se pudo modificar la venta.')}finally{setBusy(false)}}
 return <section className="sale-actions">
 {receipt.anulacion&&<p role="status"><strong>Venta anulada.</strong> {receipt.anulacion.motivo}{receipt.anulacion.referencia&&` · Reemplazo: ${receipt.anulacion.referencia}`}</p>}
 {!!receipt.historial?.length&&<details><summary>Historial de cambios</summary>{receipt.historial.map((h,i)=><p key={i}>{h.accion==='anular'?'Anulación':'Cambio de comprobante'} · {h.fecha} · {h.motivo}</p>)}</details>}
 {receipt.editable?<><div className="sale-action-buttons"><button type="button" onClick={()=>{setAction('anular');setError('')}}>Anular venta</button><button type="button" onClick={()=>{setAction('cambiar-tipo');setError('')}}>Cambiar comprobante</button></div>
 {action&&<form onSubmit={submit}><h3>{action==='anular'?'Anular esta venta':'Cambiar tipo de comprobante'}</h3>
 {action==='anular'?<label>Comprobante de reemplazo (opcional)<input maxLength={40} value={referencia} onChange={e=>setReferencia(e.target.value)}/></label>:<><label>Nuevo comprobante<select value={tipo} onChange={e=>{setTipo(e.target.value);setTipoDocumento(e.target.value==='FACTURA'?'RUC':'DNI');setDocumento('')}}><option value="BOLETA_ELECTRONICA">Boleta electrónica</option><option value="FACTURA">Factura</option></select></label>{tipo==='BOLETA_ELECTRONICA'&&<label>Tipo de documento<select value={tipoDocumento} onChange={e=>{
  setTipoDocumento(e.target.value as TipoDocumentoCliente);setDocumento('')
 }}>{Object.entries(documentosCliente).map(([codigo,datos])=><option value={codigo} key={codigo}>{datos.etiqueta}</option>)}</select></label>}<label>{formato.etiqueta}<input required inputMode={formato.numerico?'numeric':'text'} pattern={formato.patron}
 maxLength={formato.maximo} value={documento} onChange={e=>setDocumento(e.target.value)}/></label><label>Nombre o razón social<input required maxLength={200} value={cliente} onChange={e=>setCliente(e.target.value)}/></label></>}
 <label>Motivo<textarea required minLength={5} maxLength={1000} value={motivo} onChange={e=>setMotivo(e.target.value)}/></label>
 <p>{action==='anular'?'El cobro quedará anulado. Los insumos consumidos no se reintegran automáticamente.':'Se conserva el número, importe y pago; no se realiza otro cobro.'}</p>
 <button disabled={busy} type="submit">{busy?'Guardando…':action==='anular'?'Confirmar anulación':'Guardar cambio'}</button><button type="button" disabled={busy} onClick={()=>setAction('')}>Cancelar</button>
 </form>}</>:!receipt.anulacion&&<p>Los cambios solo están disponibles para ventas de hoy con la jornada abierta.</p>}
 {error&&<p role="alert">{error}</p>}</section>
}
