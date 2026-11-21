import {render,screen,fireEvent,waitFor,cleanup,within} from '@testing-library/react'
import {afterEach,expect,it,vi} from 'vitest'
import {useState} from 'react'
import {FactApiPanel} from './FactApiPanel'
import {FactApiPreviewPane} from './FactApiPdfPreview'

afterEach(()=>{cleanup();vi.unstubAllGlobals()})
it('shows demo document status and queues using the source identity',async()=>{
  const fetchMock=vi.fn().mockResolvedValue({ok:true,json:async()=>({disponible:true,operaciones:[]})})
  vi.stubGlobal('fetch',fetchMock)
  render(<FactApiPanel origin="COMPRA" source={9} token="test"/>)
  fireEvent.click(await screen.findByRole('button',{name:'Generar PDF de prueba'}))
  await waitFor(()=>expect(fetchMock.mock.calls.some(([url,options])=>String(url).endsWith('/COMPRA/9')&&options?.method==='POST')).toBe(true))
  expect(screen.getByText('Sin validez tributaria')).toBeTruthy()
})

it('switches preview formats without starting a download',async()=>{
  const createObjectURL=vi.fn().mockReturnValueOnce('blob:a4').mockReturnValueOnce('blob:ticket')
  const revokeObjectURL=vi.fn()
  const OriginalURL=URL
  vi.stubGlobal('URL',Object.assign(class extends OriginalURL {},{createObjectURL,revokeObjectURL}))
  const fetchMock=vi.fn((path:string)=>Promise.resolve(path.includes('/archivos/')
    ? new Response('%PDF-demo',{headers:{'Content-Type':'application/pdf'}})
    : Response.json({disponible:true,operaciones:[{estado:'COMPLETADO',numero:'B003-2',
      archivos:[{id:'a4',formato:'A4'},{id:'ticket',formato:'80mm'}]}]})))
  vi.stubGlobal('fetch',fetchMock)
  function SplitPanel(){
    const [target,setTarget]=useState<HTMLDivElement|null>(null)
    return <><FactApiPanel origin="VENTA" source={746} token="test" salon previewTarget={target}/>
      <FactApiPreviewPane onTarget={setTarget}/></>
  }
  render(<SplitPanel/>)
  const visor=screen.getByRole('complementary',{name:'Visor del comprobante'})
  fireEvent.click(await screen.findByRole('button',{name:'Ver PDF A4'}))
  expect((await within(visor).findByTitle('Vista previa PDF A4')).getAttribute('src')).toBe('blob:a4')
  const ticket=screen.getByRole('button',{name:'Ver ticket de 80 mm'})
  fireEvent.click(ticket)
  expect((await within(visor).findByTitle('Vista previa ticket de 80 mm')).getAttribute('src')).toBe('blob:ticket')
  expect(revokeObjectURL).toHaveBeenCalledWith('blob:a4')
  expect(screen.getByRole('button',{name:'Descargar PDF A4'})).toBeTruthy()
  expect(screen.getByRole('button',{name:'Descargar ticket de 80 mm'})).toBeTruthy()
  fireEvent.click(within(visor).getByRole('button',{name:'Cerrar vista previa'}))
  expect(screen.queryByTitle('Vista previa ticket de 80 mm')).toBeNull()
  expect(document.activeElement).toBe(ticket)
  expect(revokeObjectURL).toHaveBeenCalledWith('blob:ticket')
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

it('offers four format actions and exit in the journal preview dialog',async()=>{
  const OriginalURL=URL
  vi.stubGlobal('URL',Object.assign(class extends OriginalURL {},{
    createObjectURL:vi.fn().mockReturnValue('blob:preview'),revokeObjectURL:vi.fn(),
  }))
  vi.stubGlobal('fetch',vi.fn((path:string)=>Promise.resolve(path.includes('/archivos/')
    ? new Response('%PDF-demo',{headers:{'Content-Type':'application/pdf'}})
    : Response.json({disponible:true,operaciones:[{estado:'COMPLETADO',numero:'B003-2',
      archivos:[{id:'a4',formato:'A4'},{id:'ticket',formato:'80mm'}]}]}))))
  render(<FactApiPanel origin="VENTA" source={746} token="test" salon previewModal/>)
  const abrir=await screen.findByRole('button',{name:'Ver PDF A4'})
  fireEvent.click(abrir)
  const ventana=within(screen.getByRole('dialog',{name:'Vista previa del comprobante'}))
  expect(ventana.getAllByRole('button')).toHaveLength(5)
  await ventana.findByTitle('Vista previa PDF A4')
  fireEvent.click(ventana.getByRole('button',{name:'Ver ticket de 80 mm'}))
  await ventana.findByTitle('Vista previa ticket de 80 mm')
  fireEvent.click(ventana.getByRole('button',{name:'Salir'}))
  expect(screen.queryByRole('dialog')).toBeNull()
  expect(document.activeElement).toBe(abrir)
})
