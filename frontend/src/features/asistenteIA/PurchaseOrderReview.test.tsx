import {render,screen,fireEvent,cleanup} from '@testing-library/react'
import {afterEach,describe,it,expect} from 'vitest'
import {ReviewDetails} from './ReviewDetails'

afterEach(cleanup)
describe('compact purchase review',()=>{
  const product={producto:'Gin',unidad:'LTR',unidad_medida:{simbolo:'L',factor_a_base:'1'},unidad_fraccion:{simbolo:'mL',factor_a_base:'0.001'},cantidad_final:1.8,presentacion_compra:0.6,
    porcentaje_general:10,porcentaje_adicional:0,base_sugerida:1.8,antes_de_redondear:1.8}
  it('shows product first, percentage and purchase presentations without technical fields',()=>{
    render(<ReviewDetails resource="ordenes_compra" value={{advertencia:'Texto técnico extenso',eventos_cercanos:null,productos:[product]}} />)
    expect(screen.getAllByRole('columnheader').map(h=>h.textContent)).toEqual(['Producto','Incremento','Presentación','Cantidad de presentaciones','Total a pedir'])
    expect(screen.getByText('Gin')).toBeTruthy()
    expect(screen.getByText('10%')).toBeTruthy()
    expect(screen.getByText('600 mL')).toBeTruthy()
    expect(screen.getByText('3')).toBeTruthy()
    expect(screen.queryByText('Antes de redondear')).toBeNull()
    expect(screen.queryByText('Texto técnico extenso')).toBeNull()
    expect(screen.queryByText('Sin asignar')).toBeNull()
  })
  it('keeps extra separate, handles units and lets the user show remaining products',()=>{
    const rows=Array.from({length:8},(_,i)=>({...product,producto:`Insumo ${i}`,unidad:'C62',unidad_medida:{simbolo:'unidad',simbolo_plural:'unidades',factor_a_base:'1'},unidad_fraccion:undefined,presentacion_compra:12,cantidad_final:36,porcentaje_adicional:20}))
    render(<ReviewDetails resource="ordenes_compra" value={{productos:rows}} />)
    expect(screen.getAllByText('10% + 20% extra')).toHaveLength(5)
    expect(screen.getAllByText('12 unidades')).toHaveLength(5)
    expect(screen.queryByText('Insumo 7')).toBeNull()
    fireEvent.change(screen.getByRole('combobox',{name:'Mostrar productos'}),{target:{value:'all'}})
    expect(screen.getByText('Insumo 7')).toBeTruthy()
  })
  it('preserves other review types',()=>{
    render(<ReviewDetails resource="menajes" value={{nombre:'Vaso'}} />)
    expect(screen.getByText('Nombre')).toBeTruthy()
    expect(screen.getByText('Vaso')).toBeTruthy()
    expect(screen.queryByRole('table')).toBeNull()
  })
  it('keeps purchase footers free of redundant notices',()=>{
    render(<ReviewDetails resource="ordenes_compra" value={{productos:[product],resumen_compra:'Solo se compra el faltante. El adicional aumentó Gin.'}} />)
    expect(screen.queryByText('Solo se compra el faltante. El adicional aumentó Gin.')).toBeNull()
    expect(screen.queryByText('Se guardará como borrador al confirmar.')).toBeNull()
  })
  it('edits package totals across pagination and submits product identities for server validation',async()=>{
    const {vi}=await import('vitest')
    const apply=vi.fn().mockResolvedValue(undefined),dirty=vi.fn()
    render(<ReviewDetails resource="ordenes_compra" value={{productos:[product]}}
      purchase={{details:[{id_producto:7}],onApply:apply,onDirtyChange:dirty}} />)
    const input=screen.getByRole('spinbutton',{name:'Cantidad de presentaciones de Gin'})
    expect((input as HTMLInputElement).value).toBe('3')
    fireEvent.change(input,{target:{value:'4'}})
    expect(dirty).toHaveBeenLastCalledWith(true)
    expect(screen.getByRole('cell',{name:'2.4 L'})).toBeTruthy()
    fireEvent.click(screen.getByRole('button',{name:'Actualizar propuesta'}))
    expect(apply).toHaveBeenCalledWith([{id_producto:7,presentaciones:4}])
    fireEvent.change(input,{target:{value:'2.5'}})
    expect(screen.getByRole('button',{name:'Actualizar propuesta'}).hasAttribute('disabled')).toBe(true)
    fireEvent.click(screen.getByRole('button',{name:'Descartar cambios'}))
    expect(dirty).toHaveBeenLastCalledWith(false)
    expect((input as HTMLInputElement).value).toBe('3')
  })
})
