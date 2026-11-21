import { scheduleEffect } from '../../utils/scheduleEffect'
import {SaleActions} from './SaleActions'
import {useEffect,useRef,useState} from 'react'
import {Link} from 'react-router-dom'
import {ArrowLeft,ReceiptText,Search} from 'lucide-react'
import {salonApi} from '../../services/salonService'
import {documentNames,money,type Receipt} from './receipt'
import { DailySalesClosures, type DailySalesClosure } from './DailySalesClosures'
import './SalesJournalPage.css'
import {FactApiPanel} from '../../components/FactApiPanel'

type Sale={id_cobro:number;numero:string;creado_en:string;mesa:string;tipo:string;metodo:string;total:number;usuario:string;anulacion?:unknown;simulacion?:boolean}
type Journal={local:string;ventas:Sale[];cantidad:number;total:number;efectivo:number;tarjeta:number;cierres_diarios?:DailySalesClosure[]}
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())
const dateTime=(value:string)=>new Date(value).toLocaleString('es-PE',{timeZone:'America/Lima',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'})
export function SalesJournalPage(){
 const [session,setSession]=useState<{perfil:number;local:string}|null>(null)
 const [filters,setFilters]=useState({desde:today(),hasta:today(),tipo:'',metodo:'',codigo:''})
 const [query,setQuery]=useState({...filters,pagina:1})
 const [journal,setJournal]=useState<Journal|null>(null),[selected,setSelected]=useState<number|null>(null)
 const [detail,setDetail]=useState<Receipt|null>(null),[error,setError]=useState(''),[detailError,setDetailError]=useState(''),[loading,setLoading]=useState(true)
 const selection = useRef<number|null>(null)
 useEffect(()=>{selection.current=selected},[selected])
 useEffect(()=>{const c=new AbortController();salonApi('me',undefined,'GET',c.signal).then(s=>{if(!c.signal.aborted){if(![2,3].includes(s.perfil)){setError('Solo gerentes y supervisores pueden consultar el diario de ventas.');setLoading(false)}else setSession(s)}}).catch(e=>{if(!c.signal.aborted){setError(e.message);setLoading(false)}});return()=>c.abort()},[])
 useEffect(()=>scheduleEffect(() => {if(!session)return;const c=new AbortController();const previous=selection.current;setLoading(true);setError('');setJournal(null);setSelected(null);setDetail(null)
 const params=new URLSearchParams({...query,pagina:String(query.pagina)})
 salonApi(`ventas?${params}`,undefined,'GET',c.signal).then(data=>{if(!c.signal.aborted){setJournal(data);setSelected(data.ventas.some((s:Sale)=>s.id_cobro===previous)?previous:data.ventas[0]?.id_cobro??null)}}).catch(e=>{if(!c.signal.aborted)setError(e.message)}).finally(()=>{if(!c.signal.aborted)setLoading(false)})
 return()=>c.abort()
    }),[session,query])
 useEffect(()=>scheduleEffect(() => {setDetail(null);setDetailError('');if(selected===null)return;const c=new AbortController()
 salonApi(`comprobantes/${selected}`,undefined,'GET',c.signal).then(data=>{if(!c.signal.aborted)setDetail(data)}).catch(e=>{if(!c.signal.aborted)setDetailError(e.message)})
 return()=>c.abort()
    }),[selected])
 return <main className="sales-journal"><header><div><span>SALÓN · {session?.local??''}</span><h1><ReceiptText aria-hidden="true"/> Diario de ventas</h1></div><Link to="/salon"><ArrowLeft size={18}/> Regresar al salón</Link></header>
 {session&&<><form className="journal-filters" onSubmit={e=>{e.preventDefault();setQuery({...filters,pagina:1})}}>
 <label>Desde<input type="date" required value={filters.desde} onChange={e=>setFilters({...filters,desde:e.target.value})}/></label>
 <label>Hasta<input type="date" required min={filters.desde} value={filters.hasta} onChange={e=>setFilters({...filters,hasta:e.target.value})}/></label>
 <label>Comprobante<select value={filters.tipo} onChange={e=>setFilters({...filters,tipo:e.target.value})}><option value="">Todos</option>{Object.entries(documentNames).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label>
 <label>Método de pago<select value={filters.metodo} onChange={e=>setFilters({...filters,metodo:e.target.value})}><option value="">Todos</option><option value="EFECTIVO">Efectivo</option><option value="TARJETA">Tarjeta</option></select></label>
 <label>Código<input placeholder="INT-00000498" maxLength={30} value={filters.codigo} onChange={e=>setFilters({...filters,codigo:e.target.value})}/></label>
 <button type="submit" disabled={loading}><Search size={18}/> Buscar</button></form>
 {journal&&<div className="journal-totals"><div><span>Ventas</span><strong>{journal.cantidad}</strong></div><div><span>Total cobrado</span><strong>{money(journal.total)}</strong></div><div><span>Efectivo</span><strong>{money(journal.efectivo)}</strong></div><div><span>Tarjeta</span><strong>{money(journal.tarjeta)}</strong></div></div>}</>}
 {error&&<p className="journal-error" role="alert">{error}</p>}{loading&&<p role="status">Cargando ventas...</p>}
 {journal && <DailySalesClosures cierres={journal.cierres_diarios ?? []} />}
 {journal&&<div className="journal-panels"><section className="journal-list" aria-label="Ventas registradas"><h2>Ventas registradas</h2><p className="journal-muted">{query.desde} al {query.hasta} · Hora de Lima</p>
 <div className="journal-sales-scroll"><table className="journal-sales-table"><caption className="journal-sr-only">Ventas registradas del local</caption><thead><tr><th scope="col">Código</th><th scope="col">Mesa</th><th scope="col">Hora</th><th scope="col">Total</th></tr></thead><tbody>{journal.ventas.map(s=><tr key={s.id_cobro} className={selected===s.id_cobro?'is-selected':''}><td><button type="button" aria-pressed={selected===s.id_cobro} onClick={()=>setSelected(s.id_cobro)}>{s.numero}{s.simulacion?' · SIMULACIÓN':''}{s.anulacion?' · ANULADA':''}</button></td><td>{s.mesa}</td><td>{new Date(s.creado_en).toLocaleTimeString('es-PE',{timeZone:'America/Lima',hour:'2-digit',minute:'2-digit',hour12:false})}</td><td>{money(s.total)}</td></tr>)}</tbody></table>{journal.ventas.length===0&&<p>No hay ventas con estos filtros.</p>}</div>
 <nav className="journal-pagination" aria-label="Páginas de ventas"><button disabled={query.pagina===1||loading} onClick={()=>setQuery({...query,pagina:query.pagina-1})}>Anterior</button><span>{query.pagina} / {Math.max(1,Math.ceil(journal.cantidad/20))}</span><button disabled={query.pagina*20>=journal.cantidad||loading} onClick={()=>setQuery({...query,pagina:query.pagina+1})}>Siguiente</button></nav></section>
 <section className="journal-detail" aria-label="Detalle de la venta">{detailError?<p role="alert">{detailError}</p>:detail?<><div className="journal-detail-heading"><div><span className="journal-muted">Detalle de venta</span><h2>{detail.numero}</h2>{detail.prueba && <p>Venta simulada</p>}</div><strong>{money(detail.total)}</strong></div><dl><div><dt>Fecha y hora</dt><dd>{dateTime(detail.fecha)}</dd></div><div><dt>Mesa</dt><dd>{detail.mesa}</dd></div><div><dt>Comprobante</dt><dd>{documentNames[detail.tipo]}</dd></div><div><dt>Pago</dt><dd>{detail.metodo==='EFECTIVO'?'Efectivo':'Tarjeta'}</dd></div><div><dt>Cobrado por</dt><dd>{detail.usuario}</dd></div>{detail.cliente&&<div><dt>Cliente</dt><dd>{detail.cliente} · {detail.documento}</dd></div>}</dl>
 <div className="journal-table-wrap"><table><caption className="journal-sr-only">Productos de la venta {detail.numero}</caption><thead><tr><th scope="col">Cant.</th><th scope="col">Producto</th><th scope="col">Precio</th><th scope="col">Total</th></tr></thead><tbody>{detail.lineas.filter(l=>!l.id_barra_libre).map((l,i)=><tr key={i}><td>{l.cantidad}</td><td>{l.nombre}{l.opciones?.length>0&&<small>{l.opciones.map(o=>o.nombre).join(', ')}</small>}{l.selecciones_promocion?.map((s,j)=><small key={j}>{s.nombre}{s.opciones.length>0?': '+s.opciones.map(o=>o.nombre).join(', '):''}</small>)}{l.comentario&&<small>{l.comentario}</small>}</td><td>{money(l.precio)}</td><td>{money(l.precio*l.cantidad)}</td></tr>)}</tbody><tfoot><tr><th colSpan={3} scope="row">Total pagado</th><td>{money(detail.total)}</td></tr></tfoot></table></div>
 <FactApiPanel key={detail.id} origin="VENTA" source={detail.id} salon/><SaleActions key={detail.id} receipt={detail} onSaved={()=>setQuery({...query})}/><p className="journal-muted">Registro interno de cobro · Sin validez tributaria</p><Link className="journal-receipt-link" to={`/salon/comprobante/${detail.id}`}>Ver comprobante</Link></>:<p>{selected===null?'Selecciona una venta para ver su detalle.':'Cargando detalle...'}</p>}</section></div>}
 </main>
}
