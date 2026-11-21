import {useEffect,useRef,useState} from 'react'
import { salonApi } from '../services/salonService'
export function SalonPinDialog({accion,onCancel,onAuthorized}:{accion:'eliminar'|'mover'|'reasignar';onCancel:()=>void;onAuthorized:(token:string)=>void}){
 const dialog=useRef<HTMLDialogElement>(null),[pin,setPin]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false)
 useEffect(()=>{dialog.current?.showModal()},[])
 return <dialog ref={dialog} className="salon-action-dialog" onCancel={e=>{if(busy)e.preventDefault();else onCancel()}}><form onSubmit={async e=>{e.preventDefault();setBusy(true);setError('');try{const d=await salonApi('autorizar',{accion,pin});setPin('');onAuthorized(d.autorizacion)}catch(e){setError(e instanceof Error?e.message:'No se pudo autorizar');setPin('')}finally{setBusy(false)}}}>
 <h2>Autorizar {accion==='reasignar'?'cambio de miembro':accion}</h2><p>Ingresa nuevamente tu PIN de 4 dígitos.</p>
 <input aria-label="PIN de autorización" autoFocus type="password" inputMode="numeric" autoComplete="off" pattern="[0-9]{4}" maxLength={4} required value={pin} disabled={busy} onChange={e=>setPin(e.target.value.replace(/[^0-9]/g,''))}/>
 {error&&<p role="alert">{error}</p>}<footer><button type="button" disabled={busy} onClick={onCancel}>Cancelar</button><button disabled={busy}>{busy?'Validando...':'Autorizar'}</button></footer></form></dialog>
}
