import {afterEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,within} from '@testing-library/react'
import {MemoryRouter} from 'react-router-dom'
import {SalesJournalPage} from './SalesJournalPage'
import {salonApi} from '../../services/salonService'
vi.mock('../../services/salonService',()=>({salonApi:vi.fn()}))
const api=vi.mocked(salonApi)
afterEach(()=>{cleanup();api.mockReset()})
it('shows daily closures and labels demonstration sales',async()=>{
 api.mockImplementation(async path => {
  if(path==='me')return {perfil:2,local:'Sheraton'}
  if(path.startsWith('ventas?'))return {
   ventas:[{id_cobro:81,numero:'INT-00000081',creado_en:'2026-11-18T16:00:00Z',mesa:'M01',total:25,simulacion:true}],
   cantidad:1,total:25,efectivo:25,tarjeta:0,
   cierres_diarios:[{fecha:'2026-11-18',simulacion:true,cantidad:5,efectivo:75,tarjeta:25,total:100}],
  }
  return {id:81,numero:'INT-00000081',fecha:'2026-11-18T16:00:00Z',lineas:[],total:25,prueba:'DEMO'}
 })
 render(<MemoryRouter><SalesJournalPage/></MemoryRouter>)
 expect(await screen.findByText('Cierres diarios de ventas (1)')).toBeTruthy()
 expect(screen.getByText('2026-11-18')).toBeTruthy()
 expect(screen.getByRole('button',{name:'INT-00000081 · SIMULACIÓN'})).toBeTruthy()
 expect(await screen.findByText('Venta simulada')).toBeTruthy()
})
it('lists sales, opens persisted detail, and filters by payment method',async()=>{
 api.mockImplementation(async(path)=>{
  if(path==='me')return {perfil:2,local:'Barranco'}
  if(path.startsWith('ventas?'))return {local:'Barranco',ventas:[{id_cobro:81,numero:'INT-00000081',creado_en:'2026-11-18T16:00:00Z',mesa:'M01',tipo:'BOLETA',metodo:'EFECTIVO',total:25,usuario:'Ana'}],cantidad:1,total:25,efectivo:25,tarjeta:0}
  if(path==='comprobantes/81')return {id:81,numero:'INT-00000081',fecha:'2026-11-18T16:00:00Z',mesa:'M01',tipo:'BOLETA',metodo:'EFECTIVO',total:25,usuario:'Ana',lineas:[{nombre:'Mojito',cantidad:1,precio:25,opciones:[]}]}
  throw Error(path)
 })
 render(<MemoryRouter><SalesJournalPage/></MemoryRouter>)
 expect(await screen.findByText('Mojito')).toBeTruthy()
 const lista=screen.getByRole('region',{name:'Ventas registradas'})
 const detalle=screen.getByRole('region',{name:'Detalle de la venta'})
 expect(lista.nextElementSibling).toBe(detalle)
 expect(within(detalle).queryByRole('complementary',{name:'Visor del comprobante'})).toBeNull()
 fireEvent.change(screen.getByLabelText('Método de pago'),{target:{value:'TARJETA'}})
 fireEvent.click(screen.getByRole('button',{name:'Buscar'}))
 await screen.findByText('Mojito')
 expect(api.mock.calls.some(([p])=>p.includes('metodo=TARJETA'))).toBe(true)
})
it('denies team access without requesting sales',async()=>{
 api.mockResolvedValue({perfil:4,local:'Barranco'})
 render(<MemoryRouter><SalesJournalPage/></MemoryRouter>)
 expect(await screen.findByRole('alert')).toBeTruthy()
 expect(api.mock.calls.some(([p])=>p.startsWith('ventas'))).toBe(false)
})
