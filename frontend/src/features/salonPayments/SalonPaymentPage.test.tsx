import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest'
import {cleanup, fireEvent, render, screen, waitFor} from '@testing-library/react'
import {MemoryRouter, Route, Routes} from 'react-router-dom'
import {SalonPaymentPage} from './SalonPaymentPage'
import {salonApi} from '../../services/salonService'

vi.mock('../../services/salonService',()=>({salonApi:vi.fn()}))
vi.mock('../../context/authState',()=>({useAuth:()=>({logout:vi.fn()})}))
const api=vi.mocked(salonApi)
const uuid='f56f07c8-7348-4cc5-8a70-b58a8319967c'
const lineas=[{nombre:'Hamburguesa',cantidad:1,precio:25,enviada:true,comentario:'',opciones:[]}]
const account={local:'Miraflores',usuario:'Ana',mesa:'7',revision:'revision-7',total:25,id_borrador:null,lineas}
const receipt={id:81,numero:'000081',fecha:'2026-11-18T12:00:00Z',tipo:'FACTURA',metodo:'EFECTIVO',documento:'10123456789',cliente:'Ana Perez',local:'Miraflores',mesa:'7',usuario:'Ana',total:25,fiscal:false,lineas}
function open(path='/salon/mesa/7/pagar') {
  render(<MemoryRouter initialEntries={[path]}><Routes>
    <Route path="/salon/mesa/:mesa/pagar" element={<SalonPaymentPage/>}/>
    <Route path="/salon/comprobante/:id" element={<SalonPaymentPage/>}/>
  </Routes></MemoryRouter>)
}
beforeEach(()=>{api.mockReset()})
afterEach(cleanup)

describe('customer directory in salon payment',()=>{
  it('fills identity from the provider without saving the customer automatically',async()=>{
    api.mockImplementation(async(path)=>{
      if(path==='clientes/configuracion')return {configurado:true,directorio_disponible:true,consulta_identidad_externa:true}
      if(path==='mesas/7/cuenta')return account
      if(path==='clientes/consultar-documento')return {nombre:'Cliente de prueba',numero_documento:'00000000',tipo_documento:'DNI',fuente:'Factiliza'}
      throw new Error(`Unexpected request: ${path}`)
    })
    open()
    fireEvent.click(await screen.findByRole('button',{name:'Boleta electrónica'}))
    fireEvent.change(screen.getByLabelText('DNI'),{target:{value:'00000000'}})
    const search=await screen.findByRole('button',{name:'Consultar DNI/RUC'})
    await waitFor(()=>expect((search as HTMLButtonElement).disabled).toBe(false))
    fireEvent.click(search)
    await waitFor(()=>expect((screen.getByLabelText('Nombres y apellidos') as HTMLInputElement).value).toBe('Cliente de prueba'))
    expect(api.mock.calls.some(([path])=>path==='clientes')).toBe(false)
  })
  it('selects a stored customer by document and sends the internal UUID with the payment',async()=>{
    api.mockImplementation(async(path)=>{
      if(path==='clientes/configuracion')return {configurado:true,directorio_disponible:true}
      if(path==='mesas/7/cuenta')return account
      if(path==='clientes?q=10123456789&limit=10')return {clientes:[{id_cliente:uuid,nombre:'Ana Perez',numero_documento:'10123456789',tipo_documento:'RUC',tipo_persona:'NATURAL'}]}
      if(path==='mesas/7/emitir'||path==='comprobantes/81')return receipt
      throw new Error(`Unexpected request: ${path}`)
    })
    open()
    fireEvent.click(await screen.findByRole('button',{name:'Factura'}))
    fireEvent.change(screen.getByLabelText('RUC'),{target:{value:'10123456789'}})
    const search=screen.getByRole('button',{name:'Buscar cliente registrado'})
    await waitFor(()=>expect((search as HTMLButtonElement).disabled).toBe(false))
    fireEvent.click(search)
    fireEvent.click(await screen.findByRole('button',{name:/Ana Perez.*10123456789/}))
    fireEvent.click(screen.getByRole('button',{name:'Efectivo'}))
    fireEvent.click(screen.getByRole('button',{name:'Confirmar cobro'}))
    await waitFor(()=>expect(api.mock.calls.some(([path])=>path==='mesas/7/emitir')).toBe(true))
    expect(await screen.findByRole('dialog',{name:'Comprobante de la venta'})).toBeTruthy()
    expect(screen.getByRole('heading',{name:'Cobrar mesa 7'})).toBeTruthy()
    const body=api.mock.calls.find(([path])=>path==='mesas/7/emitir')?.[1] as Record<string,unknown>
    expect(body).toMatchObject({id_cliente:uuid,documento:'10123456789',cliente:'Ana Perez',tipo:'FACTURA',metodo:'EFECTIVO'})
    expect(body.id_cliente).not.toBe(body.documento)
    expect(Object.keys(body)).not.toContain('10123456789')
  })
  it('lets the cashier recover the two formats after a status request fails',async()=>{
    api.mockImplementation(async(path)=>{
      if(path==='clientes/configuracion')return {configurado:false,directorio_disponible:false}
      if(path==='comprobantes/81')return receipt
      throw new Error(`Unexpected request: ${path}`)
    })
    sessionStorage.setItem('salon_token','sesion-de-prueba')
    const fetchStatus = vi.spyOn(globalThis,'fetch').mockRejectedValueOnce(new Error('Sin conexión')).mockResolvedValue(Response.json({
      disponible:true,operaciones:[{id_operacion:'op-81',estado:'COMPLETADO',intentos:1,numero:'F001-81',
        archivos:[{id:'a4',formato:'A4'},{id:'ticket',formato:'80mm'}]}],
    }))
    try {
      open('/salon/comprobante/81')
      expect(await screen.findByText(/Cobro registrado/)).toBeTruthy()
      fireEvent.click(await screen.findByRole('button',{name:'Volver a consultar'}))
      expect(await screen.findByRole('button',{name:'Descargar PDF A4'})).toBeTruthy()
      expect(screen.getByRole('button',{name:'Descargar ticket de 80 mm'})).toBeTruthy()
      expect(screen.queryByRole('img',{name:/Comprobante interno/})).toBeNull()
    } finally {
      sessionStorage.removeItem('salon_token')
      fetchStatus.mockRestore()
    }
    expect(screen.queryByRole('button',{name:'Emitir comprobante fiscal'})).toBeNull()
    expect(api.mock.calls.some(([path])=>path.includes('/enviar'))).toBe(false)
  })
})
