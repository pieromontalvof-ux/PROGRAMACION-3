import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { InvoiceFields } from './InvoiceFields'

describe('Factura de proveedor', () => {
  it('muestra importe sobre lo facturado y permite cambiar precio y moneda', () => {
    const onChange = vi.fn()
    render(<InvoiceFields productos={[{ id_producto: 1, nombre: 'Sal', codigo: 'S1', unidad: 'KGM', categoria: 'Cocina', presentacion: 1, cantidad_pendiente: 20, cantidad_recibida: 0, cantidad_solicitada: 20 }]}
      value={{ fecha_emision: '2026-11-18', moneda: 'PEN', lineas: [{ id_producto: 1, cantidad_facturada: 20, precio_unitario: 10.125, descuento: 2.5, igv_porcentaje: 18 }] }} onChange={onChange} />)
    expect(screen.getByText('Total factura: PEN 236.00')).toBeTruthy()
    fireEvent.change(screen.getByLabelText('precio unitario Sal'), { target: { value: '11' } })
    expect(onChange.mock.calls[0][0].lineas[0].precio_unitario).toBe(11)
    fireEvent.change(screen.getByLabelText('Moneda'), { target: { value: 'USD' } })
    expect(onChange.mock.calls[1][0].moneda).toBe('USD')
    fireEvent.change(screen.getByLabelText('Afectación Sal'), { target: { value: 'EXONERADO' } })
    expect(onChange.mock.calls[2][0].lineas[0]).toMatchObject({ afectacion_igv: 'EXONERADO', igv_porcentaje: 0 })
  })
  it('calcula sin impuesto y bloquea la tasa para una línea exonerada', () => {
    render(<InvoiceFields productos={[{ id_producto: 1, nombre: 'Ejemplo', codigo: 'E1', unidad: 'KGM', categoria: 'Cocina', presentacion: 1, cantidad_pendiente: 20, cantidad_recibida: 0, cantidad_solicitada: 20 }]}
      value={{ fecha_emision: '2026-11-18', moneda: 'PEN', lineas: [{ id_producto: 1, cantidad_facturada: 20, precio_unitario: 10.125, descuento: 2.5, afectacion_igv: 'EXONERADO', igv_porcentaje: 0 }] }} onChange={vi.fn()} />)
    expect(screen.getByText('Total factura: PEN 200.00')).toBeTruthy()
    expect((screen.getByLabelText('igv porcentaje Ejemplo') as HTMLInputElement).disabled).toBe(true)
  })
  it('redondea los medios céntimos igual que el backend decimal', () => {
    render(<InvoiceFields productos={[{ id_producto: 1, nombre: 'Redondeo', codigo: 'R1', unidad: 'KGM', categoria: 'Cocina', presentacion: 1, cantidad_pendiente: 20, cantidad_recibida: 0, cantidad_solicitada: 20 }]}
      value={{ fecha_emision: '2026-11-18', moneda: 'PEN', lineas: [{ id_producto: 1, cantidad_facturada: 1, precio_unitario: 1.005, descuento: 0, afectacion_igv: 'GRAVADO', igv_porcentaje: 18 }] }} onChange={vi.fn()} />)
    expect(screen.getByText('Total factura: PEN 1.19')).toBeTruthy()
  })
})
