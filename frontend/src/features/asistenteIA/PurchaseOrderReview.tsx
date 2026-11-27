import {useId,useState} from 'react'
import {numeric,number,quantity,packageCount,percentage} from './purchaseSummary'

export type PurchaseAdjustment={id_producto:number;presentaciones:number}
export interface PurchaseEditHandlers {
  details:unknown
  disabled?:boolean
  onDirtyChange:(dirty:boolean)=>void
  onApply:(changes:PurchaseAdjustment[])=>Promise<void>
}

export function PurchaseOrderReview({rows,purchase}:{rows:Record<string,unknown>[];purchase?:PurchaseEditHandlers}) {
  const [limit,setLimit]=useState('5')
  const [edits,setEdits]=useState<Record<number,string>>({})
  const id=useId()
  const visible=limit==='all'?rows:rows.slice(0,Number(limit))
  const details=Array.isArray(purchase?.details)?purchase.details:[]
  const changes=Object.entries(edits).filter(([index,value])=>value!==String(packageCount(rows[Number(index)])))
  const dirty=changes.length>0
  const valid=changes.every(([index,value])=>/^\d+$/.test(value) && Number(value)>=1 && Number(value)<=1000000 &&
    numeric(details[Number(index)]?.id_producto))
  function change(index:number,value:string) {
    const next={...edits,[index]:value}
    setEdits(next)
    purchase?.onDirtyChange(Object.entries(next).some(([key,v])=>v!==String(packageCount(rows[Number(key)]))))
  }
  return <section>
    <div className="assistant-table-wrap" tabIndex={0} role="region" aria-label="Productos del pedido">
      <table className="assistant-data-table" id={id}>
        <thead><tr><th scope="col">Producto</th><th scope="col">Incremento</th><th scope="col">Presentación</th><th scope="col">Cantidad de presentaciones</th><th scope="col">Total a pedir</th></tr></thead>
        <tbody>{visible.map((row,index)=>{
          const count=packageCount(row),value=edits[index]??String(count??'')
          const editable=Boolean(purchase && count!==null && numeric(details[index]?.id_producto))
          const invalid=!/^\d+$/.test(value) || Number(value)<1 || Number(value)>1000000
          return <tr key={index}>
            <th scope="row">{String(row.producto??'—')}</th><td>{percentage(row)}</td>
            <td>{numeric(row.presentacion_compra)?quantity(row.presentacion_compra,row):'—'}</td>
            <td>{editable?<input type="number" min="1" max="1000000" step="1" className="assistant-purchase-total"
              aria-label={`Cantidad de presentaciones de ${String(row.producto??'producto')}`} aria-invalid={invalid}
              disabled={purchase?.disabled} value={value} onChange={event=>change(index,event.target.value)} />:
              <span>{count===null?'—':number(count)}</span>}</td>
            <td aria-live="polite">{!invalid && numeric(row.presentacion_compra)
              ?quantity(Number(value)*row.presentacion_compra,row):'—'}</td>
          </tr>
        })}</tbody>
      </table>
    </div>
    {rows.length>5 && <div className="assistant-table-controls">
      <label htmlFor={`${id}-limit`}>Mostrar productos</label>
      <select id={`${id}-limit`} aria-controls={id} value={limit} onChange={event=>setLimit(event.target.value)}>
        <option value="5">5</option><option value="10">10</option><option value="20">20</option><option value="all">Todos</option>
      </select>
      <span role="status">Mostrando {visible.length} de {rows.length}</span>
    </div>}
    {dirty && <div className="assistant-purchase-adjustment">
      <p>{valid?'Actualiza la propuesta para conservar estos cambios.':'Introduce cantidades enteras de presentaciones, desde 1.'}</p>
      <button type="button" disabled={!valid || purchase?.disabled} onClick={()=>{
        if (!purchase || !valid) return
        void purchase.onApply(changes.map(([index,value])=>({id_producto:details[Number(index)].id_producto,presentaciones:Number(value)})))
      }}>Actualizar propuesta</button>
      <button type="button" className="assistant-secondary" disabled={purchase?.disabled}
        onClick={()=>{setEdits({});purchase?.onDirtyChange(false)}}>Descartar cambios</button>
    </div>}
  </section>
}
