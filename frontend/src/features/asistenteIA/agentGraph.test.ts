import { describe, expect, it } from 'vitest'
import { agentGraph } from './agentGraph'
import type { AgenteAsistente, CatalogoAgentes } from './service'

function agent(overrides: Partial<AgenteAsistente>): AgenteAsistente {
  return { id: 'compras', nombre: 'Agente', descripcion: '', relaciones: ['orquestador'],
    herramientas: [], recursos: [], instrucciones: '', skills: [], ...overrides }
}
function catalog(agentes: AgenteAsistente[]): CatalogoAgentes {
  return { coordinador: { id: 'orquestador', nombre: 'Coordinador', descripcion: '',
    relaciones: agentes.map(a => a.id), skills: [], reglas_ruta: {} },
    agentes, limite_salon: '', regla_ejecucion: '' }
}

describe('manifest graph compatibility', () => {
  it('assigns legacy product dependencies to their catalog owner rather than a querying agent', () => {
    const legacy = catalog([
      agent({ id: 'compras', recursos: ['productos', 'presentaciones'] }),
      agent({ id: 'carta_recetas', recursos: ['productos'] }),
      agent({ id: 'presentaciones', recursos: ['presentaciones'], recursos_modificables: ['presentaciones'] }),
      agent({ id: 'recetas', recursos: ['recetas', 'productos', 'presentaciones'], recursos_modificables: ['recetas'],
        recursos_solo_consulta: ['productos', 'presentaciones'] }),
    ])
    expect(agentGraph(legacy).filter(edge => edge.tipo === 'dependencia')).toEqual([
      { origen: 'recetas', destino: 'carta_recetas', tipo: 'dependencia' },
      { origen: 'recetas', destino: 'presentaciones', tipo: 'dependencia' },
    ])
  })

  it('respects an explicitly empty server graph instead of inventing legacy connections', () => {
    expect(agentGraph({ ...catalog([agent({ id: 'menajes' })]), conexiones: [] })).toEqual([])
  })
})
