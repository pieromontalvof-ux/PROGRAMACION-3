import { fireEvent, render, screen } from '@testing-library/react'
import { describe,expect,it,vi } from 'vitest'
import { InvoiceFields } from './InvoiceFields'
import { importesLinea } from './invoiceAmounts'
const productos=[{id_producto:1,nombre:'Sal',codigo:'S1',unidad:'KGM',categoria:'Cocina',presentacion:1,cantidad_pendiente:20,cantidad_recibida:0,cantidad_solicitada:20}]
const value={fecha_emision:'2026-11-19',moneda:'PEN' as const,lineas:[{id_producto:1,cantidad_facturada:20,costo_total:118,precio_unitario:0,descuento:0,afectacion_igv:'GRAVADO' as const,igv_porcentaje:18}]}
describe('Recepción simplificada',()=>{
 it('deriva la base, IGV y unitario del costo total',()=>{
  expect(importesLinea(value.lineas[0])).toEqual({total:118,base:100,igv:18,unitario:5})
  expect(importesLinea({...value.lineas[0],afectacion_igv:'EXONERADO',igv_porcentaje:0})).toEqual({total:118,base:118,igv:0,unitario:5.9})
 })
 it('permite recibir menos, quitar un producto y marcar exoneración',()=>{
  const onChange=vi.fn();render(<InvoiceFields productos={productos} value={value} onChange={onChange}/> )
  expect(screen.getByText('Total factura: PEN 118.00')).toBeTruthy()
  expect(screen.queryByLabelText('precio unitario Sal')).toBeNull()
  fireEvent.change(screen.getByLabelText('Recibido Sal'),{target:{value:'10'}})
  expect(onChange.mock.calls[0][0].lineas[0].cantidad_facturada).toBe(10)
  fireEvent.click(screen.getByLabelText('Exonerado IGV Sal'))
  expect(onChange.mock.calls[1][0].lineas[0]).toMatchObject({afectacion_igv:'EXONERADO',igv_porcentaje:0,costo_total:118})
  fireEvent.click(screen.getByRole('button',{name:'Quitar Sal'}))
  expect(onChange.mock.calls[2][0].lineas).toEqual([])
 })
})
