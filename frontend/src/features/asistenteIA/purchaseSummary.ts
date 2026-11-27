import {formatearUnidad} from '../../utils/unitHelpers'

export const numeric=(value:unknown):value is number=>typeof value==='number' && Number.isFinite(value)
export const number=(value:number)=>value.toLocaleString('es-PE',{maximumFractionDigits:3})

export function quantity(value: number, row: Record<string, unknown>) {
  const unidad = row.unidad_medida as { simbolo_plural?: string; factor_a_base?: string } | undefined
  const fraccion = row.unidad_fraccion as { simbolo: string; factor_a_base: string } | undefined
  const convertido = value * Number(unidad?.factor_a_base) / Number(fraccion?.factor_a_base)
  if (fraccion && value > 0 && value < 1 && Number.isFinite(convertido) && convertido >= 1) {
    return `${number(convertido)} ${fraccion.simbolo}`
  }
  const etiqueta = (value !== 1 && unidad?.simbolo_plural) || formatearUnidad(row)
  return `${number(value)} ${etiqueta}`.trim()
}

export function packageCount(row:Record<string,unknown>) {
  const total=row.cantidad_final,pack=row.presentacion_compra
  if(!numeric(total)||!numeric(pack)||pack<=0)return null
  const count=total/pack,rounded=Math.round(count)
  return count>0 && Math.abs(count-rounded)<=0.000001?rounded:null
}

export function percentage(row:Record<string,unknown>) {
  const general=row.porcentaje_general,extra=row.porcentaje_adicional
  if(!numeric(general))return '—'
  return `${number(general)}%${numeric(extra)&&extra!==0?` + ${number(extra)}% extra`:''}${row.ajuste_manual?' · manual':''}`
}

const cell=(value:unknown)=>String(value??'—').replace(/[\r\n|]/g,' ')
export function purchaseSummary(rows:Record<string,unknown>[]) {
  return ['### Pedido de insumos','',
    '| Producto | Incremento | Presentación | Cantidad de presentaciones | Total a pedir |',
    '| --- | --- | --- | --- | --- |',
    ...rows.map(row=>{
      const count=packageCount(row)
      return '| '+[row.producto,percentage(row),numeric(row.presentacion_compra)?quantity(row.presentacion_compra,row):'—',
        count===null?'—':number(count),numeric(row.cantidad_final)?quantity(row.cantidad_final,row):'—'].map(cell).join(' | ')+' |'
    })].join('\n')
}

export function legacyPurchaseSummary(text:string):string|null {
  if(!/^(?:Crear|Editar)\s+[ÓO]rdenes compra\b/i.test(text))return null
  const chunks=text.split(/^\s*\d+\.\s+/m).slice(1)
  if(!chunks.length)return null
  const rows:Record<string,unknown>[]=[]
  for(const chunk of chunks){
    const fields:Record<string,string>={}
    for(const line of chunk.split('\n')){
      const match=line.trim().match(/^([^:]+):\s*(.*)$/)
      if(match)fields[match[1].normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase()]=match[2]
    }
    const total=Number(fields['cantidad final']),pack=Number(fields['presentacion compra'])
    if(!fields.producto||!fields['unidad de medida']||!Number.isFinite(total)||!Number.isFinite(pack)||pack<=0)return null
    rows.push({producto:fields.producto,unidad:fields['unidad de medida'],cantidad_final:total,presentacion_compra:pack,
      porcentaje_general:Number(fields['porcentaje general']),porcentaje_adicional:Number(fields['porcentaje adicional']??0),
      ajuste_manual:fields['ajuste manual']==='Sí'})
  }
  return purchaseSummary(rows)
}
