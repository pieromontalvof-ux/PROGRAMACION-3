import {render,screen,fireEvent,waitFor,cleanup} from '@testing-library/react'
import {afterEach,expect,it,vi} from 'vitest'
import {FactApiPanel} from './FactApiPanel'

afterEach(()=>{cleanup();vi.unstubAllGlobals()})
it('shows demo document status and queues using the source identity',async()=>{
  const fetchMock=vi.fn().mockResolvedValue({ok:true,json:async()=>({disponible:true,operaciones:[]})})
  vi.stubGlobal('fetch',fetchMock)
  render(<FactApiPanel origin="COMPRA" source={9} token="test"/>)
  fireEvent.click(await screen.findByRole('button',{name:'Generar PDF de prueba'}))
  await waitFor(()=>expect(fetchMock.mock.calls.some(([url,options])=>String(url).endsWith('/COMPRA/9')&&options?.method==='POST')).toBe(true))
  expect(screen.getByText(/Sin envío a SUNAT/)).toBeTruthy()
})

it('hides previous store results as soon as the session changes',async()=>{
  vi.stubGlobal('fetch',vi.fn().mockResolvedValueOnce({ok:true,json:async()=>({disponible:true,operaciones:[
    {id_operacion:'old',version:1,estado:'COMPLETADO',intentos:1,numero:'OLD-1',archivos:[]}]})})
    .mockImplementation(()=>new Promise(()=>{})))
  const view=render(<FactApiPanel origin="COMPRA" source={1} token="store-a"/>)
  await screen.findByText(/OLD-1/)
  view.rerender(<FactApiPanel origin="COMPRA" source={1} token="store-b"/>)
  expect(screen.queryByText(/OLD-1/)).toBeNull()
})
