import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import { InvoiceDetail } from './InvoiceDetail'
import { registrarEntrega } from '../../services/receptionService'

vi.mock('../../services/receptionService', () => ({ registrarEntrega: vi.fn() }))
const recepcion = {
  id_factura_recepcion: 3, id_orden_compra: 1, codigo_orden: 'OC-001', estado_orden_compra: 'RECEPCION_PARCIAL',
  id_proveedor: 2, proveedor: 'Empresa', numero_factura: 'F001-258', fecha_recepcion: '2026-11-18', recibido_por: 'Ana',
  detalles: [{ id_factura_recepcion_detalle: 9, id_producto: 1, codigo:'S1', nombre:'Sal', unidad:'KGM', cantidad_recibida:15, cantidad_solicitada:20, recibido_otras_facturas:0, maximo_permitido:20 }],
  factura: { fecha_emision:'2026-11-18', moneda:'PEN' as const, proveedor:{nombre:'Empresa',ruc:'20123456789'}, subtotal:200, igv:36, total:236,
    lineas:[{ id_producto:1, nombre:'Sal', codigo:'S1', unidad:'KGM', unidad_medida:{codigo:'KGM', valor:'KGM', simbolo:'kg', nombre:'Kilogramo', dimension:'MASA' as const, codigo_unece:'KGM', codigo_base:'KGM', factor_a_base:'1', estandar:'UNECE Rec. 20' as const}, cantidad_facturada:20, precio_unitario:10.125, descuento:2.5, igv_porcentaje:18, subtotal:200,igv:36,total:236 }] }, entregas: [],
}
describe('Detalle de factura recibida', () => {
  it('separa facturado de recibido y permite completar sin emitir otra factura', async () => {
    vi.mocked(registrarEntrega).mockResolvedValue({ mensaje:'Registrado' })
    const onSaved=vi.fn().mockResolvedValue(undefined)
    render(<InvoiceDetail recepcion={recepcion} token="token" puedeRecibir onSaved={onSaved} />)
    expect(screen.getByText('Factura F001-258 · Entrega parcial')).toBeTruthy()
    fireEvent.change(screen.getByLabelText('Sal (kg)'), { target:{value:'5'} })
    fireEvent.click(screen.getByRole('button', { name:'Registrar entrega' }))
    await waitFor(() => expect(onSaved).toHaveBeenCalledOnce())
    expect(registrarEntrega).toHaveBeenCalledWith('token',3,expect.objectContaining({ detalles:[{id_producto:1,cantidad_recibida:5}], clave:expect.any(String) }))
  })
  it('habilita la cantidad y datos en el mismo detalle al corregir', () => {
    const cambiar=vi.fn()
    const props={recepcion,token:'token',puedeRecibir:false,onSaved:async()=>{}}
    const {rerender}=render(<InvoiceDetail {...props} />)
    expect(screen.queryByLabelText('Recibido Sal')).toBeNull()
    rerender(<InvoiceDetail {...props} edicion={{activa:true,numero:'F001-258',fecha:'2026-11-18',cantidades:{9:'15'},numeroCambio:vi.fn(),fechaCambio:vi.fn(),cantidadCambio:cambiar}} />)
    expect(screen.getAllByLabelText('Recibido Sal')).toHaveLength(1)
    expect((screen.getByLabelText('Número de factura') as HTMLInputElement).value).toBe('F001-258')
    fireEvent.change(screen.getByLabelText('Recibido Sal'),{target:{value:'12'}})
    expect(cambiar).toHaveBeenCalledWith(9,'12')
  })
  it('conserva las recepciones anteriores sin inventar importes', () => {
    render(<InvoiceDetail recepcion={{...recepcion, factura:null}} token="token" puedeRecibir={false} onSaved={async()=>{}} />)
    expect(screen.getByText(/no se registraron precios/)).toBeTruthy()
  })
})
