import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import { AnswerContent } from './AnswerContent'

afterEach(cleanup)
it('keeps the four column event table first and candidate review collapsed', () => {
  render(<AnswerContent text={'| Día | Evento publicado | Tipo | Lugar |\n| --- | --- | --- | --- |\n| Jue. 12 | Congreso | Congreso | Hotel |'}
    queries={[{recurso:'eventos_cercanos',registros:[{detalle:'Candidato lejano: fuera del radio.'}],total:1,desde:0,hay_mas:false}]} />)
  expect(screen.getAllByRole('columnheader').map(h=>h.textContent)).toEqual(['Día','Evento publicado','Tipo','Lugar'])
  const toggle=screen.getByText('Ver revisión de eventos')
  expect(toggle.closest('details')?.open).toBe(false)
  fireEvent.click(toggle)
  expect(toggle.closest('details')?.open).toBe(true)
})

it('preserves the event table and review when the final query is stock', () => {
  render(<AnswerContent text={'| Día | Evento publicado | Tipo | Lugar |\n| --- | --- | --- | --- |\n| Jue. 12 | Congreso | Congreso | Hotel |\n\nStock revisado: Limón 1 kg.'}
    queries={[{recurso:'eventos_cercanos',registros:[{detalle:'Motivos de descarte.'}],total:1,desde:0,hay_mas:false},
      {recurso:'stock',registros:[{id_producto:1,nombre:'Limón',stock_actual:1,stock_minimo:2,unidad:'KGM'}],total:1,desde:0,hay_mas:false}]} />)
  expect(screen.getAllByRole('columnheader').map(h=>h.textContent)).toEqual(['Día','Evento publicado','Tipo','Lugar'])
  expect(screen.getByText('Ver revisión de eventos')).toBeTruthy()
})

it('keeps clean sales and coverage tables when stock is last without events', () => {
  render(<AnswerContent text={'| Producto | Cantidad vendida | Promedio por día |\n| --- | --- | --- |\n| Mojito | 92 | 3.07 |\n\n| Insumo | Stock | Consumo diario | Cobertura estimada (días) |\n| --- | --- | --- | --- |\n| Limón | 1 kg | 0.61 kg | 2.86 |'}
    queries={[{recurso:'demanda_rotacion',registros:[],total:1,desde:0,hay_mas:false},
      {recurso:'stock',registros:[{id_producto:1,nombre:'Limón',stock_actual:1,stock_minimo:2,unidad:'KGM'}],total:1,desde:0,hay_mas:false}]} />)
  expect(screen.getAllByRole('table')).toHaveLength(2)
  expect(screen.getByRole('columnheader',{name:'Cantidad vendida'})).toBeTruthy()
  expect(screen.getByRole('columnheader',{name:'Cobertura estimada (días)'})).toBeTruthy()
})
