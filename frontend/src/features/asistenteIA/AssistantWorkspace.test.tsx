import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { AssistantWorkspace } from './AssistantWorkspace'
import type { RespuestaAsistente } from './service'
import { blankWorkspace } from './workspaceState'

const mocks = vi.hoisted(() => ({ request: vi.fn(), status: vi.fn(), scope: {perfil:1, local:1, changing:false} }))
vi.mock('../../context/authState', () => ({
  useAuth: () => ({ token: 'test-session', perfilActivo: { id_perfil: mocks.scope.perfil, nombre: 'Administrador' }, localActivo: {id_local:mocks.scope.local}, cambiandoLocal:mocks.scope.changing }),
}))

it('preserves a clean promotion table after saving and in the following conversation turn',async()=>{
  const vista={nombre:'Inicio para 2',precio:39.9,activo:true,hora_inicio:null,hora_fin:null,
    grupos:[{cantidad_elegir:2,permite_repetir:true,opciones:['174 IPA · 0.2 LTR (#118)']},
      {cantidad_elegir:1,permite_repetir:false,opciones:['Nachos · 1.0 PORCION (#68)','Papas · 1.0 PORCION (#61)']}]}
  mocks.request.mockImplementation(async(_token,route)=>{
    if(route==='realizar')return {mensaje:'Promoción guardada correctamente'}
    if(mocks.request.mock.calls.filter(call=>call[1]==='preparar').length>1)return {respuesta:'Seguimos con tu consulta.',consultas:[],borrador:null}
    return {respuesta:'Revisa la propuesta',consultas:[],borrador:{id_borrador:'promotion',recurso:'promociones',accion:'crear',id:null,anterior:null,datos:vista,vista}}
  })
  render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  const input=await screen.findByRole('textbox',{name:'Consulta o corrección'})
  await waitFor(()=>expect(input.hasAttribute('disabled')).toBe(false))
  fireEvent.change(input,{target:{value:'Prepara Inicio para 2'}})
  fireEvent.click(screen.getByRole('button',{name:'Enviar'}))
  fireEvent.click(await screen.findByRole('checkbox'))
  fireEvent.click(screen.getByRole('button',{name:'Realizar'}))
  await screen.findByRole('heading',{name:'Cambio realizado'})
  expect(screen.getByRole('table')).toBeTruthy()
  expect(screen.getByRole('heading',{name:'Inicio para 2'})).toBeTruthy()
  expect(screen.queryByText(/Permite repetir/)).toBeNull()
  await waitFor(()=>expect(input.hasAttribute('disabled')).toBe(false))
  fireEvent.change(input,{target:{value:'Gracias, otra consulta'}})
  fireEvent.click(screen.getByRole('button',{name:'Enviar'}))
  await screen.findByText('Seguimos con tu consulta.')
  expect(screen.getByRole('heading',{name:'Inicio para 2'})).toBeTruthy()
  expect(screen.getByRole('table')).toBeTruthy()
})
vi.mock('./service', async importOriginal => ({
  ...await importOriginal<typeof import('./service')>(),
  solicitar: mocks.request,
  obtenerEstadoAsistente: mocks.status,
}))

function proposal(nested: boolean): RespuestaAsistente {
  return {
    respuesta: 'Revisa la propuesta.', agente: nested ? 'presentaciones' : 'recetas', consultas: [],
    continuacion: nested ? 'child-step' : 'root-step',
    ...(nested ? { tarea_pendiente: 'Crear receta de hamburguesa' } : {}),
    borrador: { id_borrador: 'confirmed-draft', recurso: nested ? 'presentaciones' : 'recetas',
      accion: 'crear', id: null, datos: {}, vista: { nombre: 'Hamburguesa' }, anterior: null },
  }
}

async function prepare() {
  render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  await waitFor(() => expect(mocks.status).toHaveBeenCalled())
  fireEvent.change(screen.getByRole('textbox', { name: 'Consulta o corrección' }), { target: { value: 'Crear receta' } })
  await waitFor(() => expect(screen.getByRole('button', { name: 'Enviar' }).hasAttribute('disabled')).toBe(false))
  fireEvent.click(screen.getByRole('button', { name: 'Enviar' }))
  await screen.findByRole('checkbox')
  fireEvent.click(screen.getByRole('checkbox'))
  fireEvent.click(screen.getByRole('button', { name: 'Realizar' }))
}

beforeEach(() => {
  mocks.request.mockReset()
  mocks.status.mockReset().mockResolvedValue({ estado: 'disponible', ia_disponible: true,
    dictado_disponible: false, ejecucion_disponible: true, capacidades: {}, modulos_consultables: [] })
  Element.prototype.scrollIntoView = vi.fn()
  let revision = 0
  vi.stubGlobal('fetch', vi.fn(async (_url, options) => new Response(JSON.stringify({
    workspace: null, revision: options?.method === 'PUT' ? ++revision : revision,
  }))))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('assistant confirmed workflow continuation', () => {
  it('starts a clean conversation without previous drafts, context or flow tokens', async () => {
    mocks.request.mockImplementation(async (_token, route) => {
      if (route === 'cancelar') return { mensaje: 'Cancelado' }
      return { ...proposal(false), flujo_compra: 'old-purchase-flow' }
    })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const input = await screen.findByRole('textbox', { name: 'Consulta o corrección' })
    await waitFor(() => expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.change(input, { target: { value: 'Crear receta anterior' } })
    fireEvent.click(screen.getByRole('button', { name: 'Enviar' }))
    await screen.findByRole('checkbox')
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar conversación' }))
    await waitFor(() => expect(screen.queryByRole('checkbox')).toBeNull())
    await waitFor(() => expect(input.hasAttribute('disabled')).toBe(false))
    expect(mocks.request.mock.calls.some(call => call[1] === 'cancelar')).toBe(true)
    expect(vi.mocked(fetch).mock.calls.some(call => call[1]?.method === 'PUT' && JSON.parse(String(call[1].body)).workspace === null)).toBe(true)
    fireEvent.change(input, { target: { value: 'Quiero comparar promociones' } })
    fireEvent.click(screen.getByRole('button', { name: 'Enviar' }))
    await waitFor(() => expect(mocks.request.mock.calls.filter(call => call[1] === 'preparar')).toHaveLength(2))
    const body = mocks.request.mock.calls.filter(call => call[1] === 'preparar')[1][2]
    expect(body.contexto_previo).toBe('')
    expect(body.borrador_previo).toBe('')
    expect(body.continuacion).toBeUndefined()
    expect(body.flujo_compra).toBeUndefined()
    expect(body.reemplaza).toBeUndefined()
  })
  it('validates manual purchase totals before allowing confirmation of the replacement draft',async()=>{
    function purchase(id:string,total:number):RespuestaAsistente {
      return {respuesta:'Revisa el pedido',consultas:[],flujo_compra:'signed-flow',borrador:{
        id_borrador:id,recurso:'ordenes_compra',accion:'crear',id:null,anterior:null,
        datos:{accion:'ENVIAR',detalles:[{id_producto:7,cantidad_solicitada:total}]},
        vista:{productos:[{producto:'Gin',unidad:'LTR',unidad_medida:{simbolo:'L',factor_a_base:'1'},unidad_fraccion:{simbolo:'mL',factor_a_base:'0.001'},presentacion_compra:0.6,cantidad_final:total,
          porcentaje_general:10,porcentaje_adicional:0}]},
      }}
    }
    mocks.request.mockImplementation(async(_token,route)=>{
      if(route==='preparar')return purchase('purchase-old',1.8)
      if(route==='compras/ajustar')return purchase('purchase-new',2.4)
      return {mensaje:'Borrador guardado'}
    })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const chat=await screen.findByRole('textbox',{name:'Consulta o corrección'})
    await waitFor(()=>expect(chat.hasAttribute('disabled')).toBe(false))
    fireEvent.change(chat,{target:{value:'Prepara mi pedido'}})
    fireEvent.click(screen.getByRole('button',{name:'Enviar'}))
    const quantity=await screen.findByRole('spinbutton',{name:'Cantidad de presentaciones de Gin'})
    fireEvent.click(screen.getByRole('checkbox'))
    fireEvent.change(quantity,{target:{value:'4'}})
    expect(screen.getByRole('button',{name:'Enviar pedido'}).hasAttribute('disabled')).toBe(true)
    expect((screen.getByRole('checkbox') as HTMLInputElement).checked).toBe(false)
    fireEvent.click(screen.getByRole('button',{name:'Actualizar propuesta'}))
    await waitFor(()=>expect(mocks.request.mock.calls.some(call=>call[1]==='compras/ajustar')).toBe(true))
    expect(mocks.request.mock.calls.find(call=>call[1]==='compras/ajustar')?.[2]).toEqual({
      id_borrador:'purchase-old',cantidades:[{id_producto:7,presentaciones:4}],
    })
    await waitFor(()=>expect((screen.getByRole('spinbutton',{name:'Cantidad de presentaciones de Gin'}) as HTMLInputElement).value).toBe('4'))
    await waitFor(()=>expect(screen.getByRole('checkbox').hasAttribute('disabled')).toBe(false))
    fireEvent.click(screen.getByRole('checkbox'))
    fireEvent.click(screen.getByRole('button',{name:'Enviar pedido'}))
    await waitFor(()=>expect(mocks.request.mock.calls.find(call=>call[1]==='realizar')?.[2].id).toBe('purchase-new'))
    await screen.findByRole('heading',{name:'Cambio realizado'})
    expect(screen.getByRole('columnheader',{name:'Total a pedir'})).toBeTruthy()
    expect(screen.getByRole('cell',{name:'2.4 L'})).toBeTruthy()
    expect(screen.queryByRole('spinbutton')).toBeNull()
    expect(screen.queryByText(/Antes de redondear/)).toBeNull()
  })
  it('sends a short correction after a large report without resending every table row', async () => {
    const report='### Informe de compras\nEntrega: 2026-11-22\n| Insumo | Cantidad |\n| --- | --- |\n'+
      Array.from({length:1000},(_,i)=>`| Producto ${i} | 10 unidades |`).join('\n')
    mocks.request.mockResolvedValueOnce({respuesta:report,consultas:[],borrador:null,flujo_compra:'signed-purchase-flow'})
      .mockResolvedValueOnce({respuesta:'Confirma los incrementos.',consultas:[],borrador:null})
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const input=await screen.findByRole('textbox',{name:'Consulta o corrección'})
    await waitFor(()=>expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.change(input,{target:{value:'Analiza mi pedido'}})
    fireEvent.click(screen.getByRole('button',{name:'Enviar'}))
    await screen.findByRole('heading',{name:'Informe de compras'})
    await waitFor(()=>expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.change(input,{target:{value:'10% general y 20% para pisco sour'}})
    fireEvent.click(screen.getByRole('button',{name:'Enviar'}))
    await waitFor(()=>expect(mocks.request).toHaveBeenCalledTimes(2))
    const request=mocks.request.mock.calls[1][2]
    expect(request.instruccion).toBe('10% general y 20% para pisco sour')
    expect(request.borrador_previo.length).toBeLessThanOrEqual(16000)
    expect(request.contexto_previo.length).toBeLessThanOrEqual(16000)
    expect(request.flujo_compra).toBe('signed-purchase-flow')
  })
  it('keeps chat as default and opens an optional sheet prefilled from the proposal', async () => {
    const result: RespuestaAsistente = { respuesta: 'Revisa.', consultas: [], agente: 'menajes', borrador: {
      id_borrador: 'sheet-draft', recurso: 'menajes', accion: 'crear', id: null,
      datos: { nombre: 'Vaso especial' }, vista: { nombre: 'Vaso especial' }, anterior: null } }
    mocks.request.mockImplementation(async (_token, route) => route === 'preparar' ? result : {
      formulario: { recurso: 'menajes', titulo: 'Crear menaje', categorias: [], proveedores: [],
        unidades_medida: [], categorias_proveedor_configurables: false, dependencias_creables: [], menajes: [], items: [], tipos: [] } })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const input = await screen.findByRole('textbox', { name: 'Consulta o corrección' })
    await waitFor(() => expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.change(input, { target: { value: 'Crear menaje Vaso especial' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    await screen.findByRole('button', { name: 'Editar ficha (opcional)' })
    expect(mocks.request.mock.calls[0][2].modo).toBe('conversacion')
    expect(screen.queryByRole('textbox', { name: 'Nombre' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Editar ficha (opcional)' }))
    const name = await screen.findByRole('textbox', { name: 'Nombre' }) as HTMLInputElement
    expect(name.value).toBe('Vaso especial')
    expect(screen.getByRole('button', { name: 'Realizar' }).hasAttribute('disabled')).toBe(true)
    expect(mocks.request.mock.calls.map(call => call[1])).toEqual(['preparar', 'formulario'])
  })
  it('sends a typed query with Enter', async () => {
    mocks.request.mockResolvedValue({ respuesta: 'Consulta recibida.', consultas: [], borrador: null })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const input = await screen.findByRole('textbox', { name: 'Consulta o corrección' })
    await waitFor(() => expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.change(input, { target: { value: 'Consultar stock' } })
    fireEvent.keyDown(input, { key: 'Enter', code: 'Enter' })
    await screen.findByText('Consulta recibida.')
    expect(mocks.request).toHaveBeenCalledTimes(1)
    expect(mocks.request.mock.calls[0][2].instruccion).toBe('Consultar stock')
  })

  it('keeps Shift+Enter for newlines and ignores empty Enter and composition', async () => {
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const input = await screen.findByRole('textbox', { name: 'Consulta o corrección' })
    await waitFor(() => expect(input.hasAttribute('disabled')).toBe(false))
    fireEvent.keyDown(input, { key: 'Enter' })
    fireEvent.change(input, { target: { value: 'Primera línea' } })
    expect(fireEvent.keyDown(input, { key: 'Enter', shiftKey: true })).toBe(true)
    fireEvent.keyDown(input, { key: 'Enter', isComposing: true })
    expect(mocks.request).not.toHaveBeenCalled()
  })

  it('sends the signed purchasing flow when selecting an analysis option', async () => {
    const result: RespuestaAsistente = { respuesta: 'Elige un análisis.', consultas: [], borrador: null,
      flujo_compra: 'signed-purchasing-flow', agente: 'eventos',
      opciones: [{ etiqueta: 'Desde la última orden', instruccion: 'Analizar desde la última orden enviada' }] }
    const restored = { ...blankWorkspace(), result, review: result.respuesta, original: result.respuesta }
    vi.mocked(fetch).mockResolvedValue(new Response(JSON.stringify({ workspace: restored, revision: 4 })))
    mocks.request.mockResolvedValue({ respuesta: 'Informe del periodo.', consultas: [], borrador: null,
      flujo_compra: 'next-purchasing-step', agente: 'demanda' })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const option = await screen.findByRole('button', { name: 'Desde la última orden' })
    await waitFor(() => expect(option.hasAttribute('disabled')).toBe(false))
    fireEvent.click(option)
    await screen.findByText('Informe del periodo.')
    expect(mocks.request.mock.calls[0][2]).toMatchObject({
      instruccion: 'Analizar desde la última orden enviada', flujo_compra: 'signed-purchasing-flow' })
  })

  it('recovers a pending draft without restoring approval or automatically executing it', async () => {
    const restored = { ...blankWorkspace(), result: proposal(false), draftId: 'confirmed-draft',
      review: 'Crear receta de hamburguesa', original: 'Crear receta de hamburguesa', lastPrompt: 'Crear receta' }
    vi.mocked(fetch).mockResolvedValue(new Response(JSON.stringify({ workspace: restored, revision: 4 })))
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const checkbox = await screen.findByRole('checkbox')
    expect((checkbox as HTMLInputElement).checked).toBe(false)
    expect(screen.getByRole('button', { name: 'Realizar' }).hasAttribute('disabled')).toBe(true)
    expect(mocks.request).not.toHaveBeenCalled()
  })

  it('recovers a completed prerequisite with only the option to return to its parent', async () => {
    const restored = { ...blankWorkspace(), result: { ...proposal(true), borrador: null },
      confirmed: true, resumeDraft: 'confirmed-draft', draftId: 'confirmed-draft',
      review: 'Presentación creada.', original: 'Presentación creada.' }
    vi.mocked(fetch).mockResolvedValue(new Response(JSON.stringify({ workspace: restored, revision: 4 })))
    mocks.request.mockResolvedValue({ respuesta: 'Continuamos con los ingredientes.', consultas: [],
      borrador: null, agente: 'recetas', continuacion: 'root-step' })
    render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
    const retry = await screen.findByRole('button', { name: 'Retomar tarea pendiente' })
    await waitFor(() => expect(retry.hasAttribute('disabled')).toBe(false))
    fireEvent.click(retry)
    await screen.findByText('Continuamos con los ingredientes.')
    expect(mocks.request.mock.calls.map(call => call[1])).toEqual(['continuar'])
  })

  it('finishes a root draft without trying to return to a nonexistent parent', async () => {
    mocks.request.mockImplementation(async (_token, route) => {
      if (route === 'preparar') return proposal(false)
      if (route === 'realizar') return { mensaje: 'Receta creada.' }
      throw new Error('No hay un padre pendiente.')
    })
    await prepare()
    await screen.findByText('Realizado')
    expect(mocks.request.mock.calls.filter(call => call[1] === 'continuar')).toHaveLength(0)
    fireEvent.change(screen.getByRole('textbox', { name: 'Consulta o corrección' }), { target: { value: 'Otra consulta' } })
    fireEvent.click(screen.getByRole('button', { name: 'Enviar' }))
    await waitFor(() => expect(mocks.request.mock.calls.filter(call => call[1] === 'preparar')).toHaveLength(2))
    expect(mocks.request.mock.calls.filter(call => call[1] === 'preparar')[1][2].continuacion).toBeUndefined()
  })

  it('returns a confirmed prerequisite to its parent', async () => {
    mocks.request.mockImplementation(async (_token, route) => {
      if (route === 'preparar') return proposal(true)
      if (route === 'realizar') return { mensaje: 'Presentación creada.' }
      return { respuesta: 'Continuamos con los ingredientes.', consultas: [], borrador: null,
        agente: 'recetas', continuacion: 'root-step' }
    })
    await prepare()
    await screen.findByText('Continuamos con los ingredientes.')
    expect(mocks.request).toHaveBeenCalledWith('test-session', 'continuar', {
      continuacion: 'child-step', id_borrador: 'confirmed-draft',
    }, expect.any(AbortSignal))
    expect(mocks.request.mock.calls.filter(call => call[1] === 'realizar')).toHaveLength(1)
  })

  it('retries only the return when resuming fails after a successful creation', async () => {
    let attempts = 0
    mocks.request.mockImplementation(async (_token, route) => {
      if (route === 'preparar') return proposal(true)
      if (route === 'realizar') return { mensaje: 'Presentación creada.' }
      if (++attempts === 1) throw new Error('Conexión interrumpida al retomar.')
      return { respuesta: 'Continuamos con los ingredientes.', consultas: [], borrador: null,
        agente: 'recetas', continuacion: 'root-step' }
    })
    await prepare()
    const retry = await screen.findByRole('button', { name: 'Retomar tarea pendiente' })
    await waitFor(() => expect(retry.hasAttribute('disabled')).toBe(false))
    fireEvent.click(retry)
    await screen.findByText('Continuamos con los ingredientes.')
    expect(mocks.request.mock.calls.filter(call => call[1] === 'realizar')).toHaveLength(1)
    expect(mocks.request.mock.calls.filter(call => call[1] === 'continuar')).toHaveLength(2)
  })
})

it('clears the conversation on role and local changes even with the same token',async()=>{
  const view=render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  await waitFor(()=>expect(screen.getByRole('textbox').hasAttribute('disabled')).toBe(false))
  fireEvent.change(screen.getByRole('textbox'),{target:{value:'private previous scope'}})
  mocks.scope.local=2
  view.rerender(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  expect((screen.getByRole('textbox') as HTMLTextAreaElement).value).toBe('')
  fireEvent.change(screen.getByRole('textbox'),{target:{value:'private role'}})
  mocks.scope.perfil=2
  view.rerender(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  expect((screen.getByRole('textbox') as HTMLTextAreaElement).value).toBe('')
  mocks.scope.changing=true
  view.rerender(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  expect(screen.queryByRole('textbox')).toBeNull()
  mocks.scope={perfil:1,local:1,changing:false}
})

it('ignores an old response arriving after switching store',async()=>{
  let finish!:(value:RespuestaAsistente)=>void
  mocks.request.mockImplementationOnce(()=>new Promise<RespuestaAsistente>(resolve=>{finish=resolve}))
  const view=render(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  await waitFor(()=>expect(screen.getByRole('textbox').hasAttribute('disabled')).toBe(false))
  fireEvent.change(screen.getByRole('textbox'),{target:{value:'query old store'}})
  fireEvent.click(screen.getByRole('button',{name:'Enviar'}))
  await waitFor(()=>expect(mocks.request).toHaveBeenCalled())
  mocks.scope.local=3
  view.rerender(<MemoryRouter><AssistantWorkspace /></MemoryRouter>)
  finish({respuesta:'PRIVATE OLD STORE',consultas:[],borrador:null})
  await waitFor(()=>expect(screen.getByRole('textbox').hasAttribute('disabled')).toBe(false))
  expect(screen.queryByText('PRIVATE OLD STORE')).toBeNull()
  expect(screen.queryByText('query old store')).toBeNull()
  mocks.scope={perfil:1,local:1,changing:false}
})
