import type { AgenteId, CatalogoAgentes, ConexionAgentes } from './service'

// Older servers expose the same ownership and prerequisites in each agent.
// Never infer dependencies from the visual arrangement of nodes.
export function agentGraph(catalog: CatalogoAgentes): ConexionAgentes[] {
  if (catalog.conexiones) return catalog.conexiones
  const owners = new Map<string, AgenteId>()
  const catalogOwner = catalog.agentes.find(agent => agent.id === 'carta_recetas')
  for (const resource of catalogOwner?.recursos ?? []) owners.set(resource, 'carta_recetas')
  for (const agent of catalog.agentes) {
    for (const resource of agent.recursos_modificables ?? []) owners.set(resource, agent.id)
  }
  const edges: ConexionAgentes[] = catalog.agentes
    .filter(agent => catalog.coordinador.relaciones.includes(agent.id))
    .map(agent => ({ origen: 'orquestador', destino: agent.id, tipo: 'coordinacion' }))
  for (const agent of catalog.agentes) {
    const dependencies = new Set(agent.recursos_solo_consulta?.map(resource => owners.get(resource)))
    for (const owner of dependencies) {
      if (owner && owner !== agent.id) edges.push({ origen: agent.id, destino: owner, tipo: 'dependencia' })
    }
  }
  return edges
}
