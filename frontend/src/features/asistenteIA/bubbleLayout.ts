export type Bubble = { id: string; x: number; y: number; width: number; height: number; offsetY: number }
type Bounds = { width: number; height: number }
const gap = 10

function clamp(b: Bubble, bounds: Bounds): Bubble {
  return { ...b, x: Math.max(b.width / 2, Math.min(bounds.width - b.width / 2, b.x)),
    y: Math.max(b.height / 2 - b.offsetY, Math.min(bounds.height - b.height / 2 - b.offsetY, b.y)) }
}
function overlaps(a: Bubble, b: Bubble) {
  return Math.abs(a.x - b.x) < (a.width + b.width) / 2 + gap - .01 &&
    Math.abs(a.y + a.offsetY - b.y - b.offsetY) < (a.height + b.height) / 2 + gap - .01
}
function push(anchor: Bubble, other: Bubble, bounds: Bounds): Bubble | null {
  const dx = (anchor.width + other.width) / 2 + gap
  const dy = (anchor.height + other.height) / 2 + gap
  const candidates = [
    { ...other, x: anchor.x + dx }, { ...other, x: anchor.x - dx },
    { ...other, y: anchor.y + anchor.offsetY - other.offsetY + dy },
    { ...other, y: anchor.y + anchor.offsetY - other.offsetY - dy },
  ].filter(b => { const bounded = clamp(b, bounds); return bounded.x === b.x && bounded.y === b.y })
  candidates.sort((a, b) => Math.hypot(a.x - other.x, a.y - other.y) - Math.hypot(b.x - other.x, b.y - other.y))
  return candidates[0] ?? null
}

function nearestFree(node: Bubble, placed: Bubble[], bounds: Bounds): Bubble | null {
  const xs = [node.x, node.width / 2, bounds.width - node.width / 2]
  const ys = [node.y, node.height / 2 - node.offsetY, bounds.height - node.height / 2 - node.offsetY]
  for (const other of placed) {
    const dx = (node.width + other.width) / 2 + gap
    const dy = (node.height + other.height) / 2 + gap
    xs.push(other.x - dx, other.x + dx)
    ys.push(other.y + other.offsetY - node.offsetY - dy, other.y + other.offsetY - node.offsetY + dy)
  }
  let best: Bubble | null = null, distance = Infinity
  for (const x of xs) for (const y of ys) {
    const candidate = clamp({ ...node, x, y }, bounds)
    const cost = Math.hypot(candidate.x - node.x, candidate.y - node.y)
    if (cost >= distance || placed.some(other => overlaps(candidate, other))) continue
    best = candidate; distance = cost
  }
  return best
}

// Footprints include the labels. The held node stays pinned while neighbours move.
export function moveBubble(input: Bubble[], id: string, target: { x: number; y: number }, bounds: Bounds): Bubble[] {
  const nodes = input.map(b => clamp(b.id === id && Number.isFinite(target.x) && Number.isFinite(target.y) ? { ...b, ...target } : { ...b }, bounds))
  const order = [...nodes.keys()].sort((a, b) => Number(nodes[b].id === id) - Number(nodes[a].id === id))
  for (let pass = 0; pass < 80; pass++) {
    let changed = false
    for (let i = 0; i < order.length; i++) for (let j = i + 1; j < order.length; j++) {
      const a = order[i], b = order[j]
      if (!overlaps(nodes[a], nodes[b])) continue
      const pushed = push(nodes[a], nodes[b], bounds)
      if (pushed) { nodes[b] = pushed; changed = true }
      else if (nodes[a].id !== id) {
        const alternative = push(nodes[b], nodes[a], bounds)
        if (alternative) { nodes[a] = alternative; changed = true }
      }
    }
    if (!changed) break
  }
  if (!nodes.some((a, i) => nodes.slice(i + 1).some(b => overlaps(a, b)))) return nodes
  // Crowded corners can trap local pushes. Repack around the held bubble using
  // nearby free footprints rather than leaving an unresolved collision.
  const held = nodes.find(node => node.id === id)
  if (!held) return nodes
  const others = nodes.filter(node => node.id !== id)
  for (const sequence of [others, [...others].reverse(), [...others].sort((a, b) => b.width * b.height - a.width * a.height)]) {
    const placed = [held]
    for (const node of sequence) {
      const free = nearestFree(node, placed, bounds)
      if (!free) break
      placed.push(free)
    }
    if (placed.length === nodes.length) return nodes.map(node => placed.find(other => other.id === node.id)!)
  }
  // A reserved grid guarantees space for the 13 current operational footprints,
  // even when the pinned bubble prevents a greedy nearest-position packing.
  const cellWidth = Math.max(...nodes.map(node => node.width))
  const cellHeight = Math.max(...nodes.map(node => node.height))
  const columns = Math.floor((bounds.width + gap) / (cellWidth + gap))
  const rows = Math.floor((bounds.height + gap) / (cellHeight + gap))
  const packed = [held]
  for (const node of others) {
    let best: Bubble | null = null, distance = Infinity
    for (let row = 0; row < rows; row++) for (let column = 0; column < columns; column++) {
      const candidate = { ...node, x: cellWidth / 2 + column * (cellWidth + gap), y: cellHeight / 2 + row * (cellHeight + gap) - node.offsetY }
      const cost = Math.hypot(candidate.x - node.x, candidate.y - node.y)
      if (cost >= distance || packed.some(other => overlaps(candidate, other))) continue
      best = candidate; distance = cost
    }
    if (!best) return input.map(node => ({ ...node })) // Refuse an infeasible move.
    packed.push(best)
  }
  return nodes.map(node => packed.find(other => other.id === node.id)!)
}
