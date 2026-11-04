import { expect, it } from 'vitest'
import { moveBubble, type Bubble } from './bubbleLayout'

const bubble = (id: string, x: number, y: number): Bubble => ({ id, x, y, width: 100, height: 100, offsetY: 0 })
const bounds = { width: 1000, height: 800 }
function overlaps(a: Bubble, b: Bubble) {
  return Math.abs(a.x - b.x) < (a.width + b.width) / 2 - .1 && Math.abs(a.y + a.offsetY - b.y - b.offsetY) < (a.height + b.height) / 2 - .1
}
it('pins the dragged bubble and pushes a chain without changing the input', () => {
  const original = [bubble('a', 100, 300), bubble('b', 220, 300), bubble('c', 330, 300)]
  const result = moveBubble(original, 'a', { x: 200, y: 300 }, bounds)
  expect(result[0].x).toBe(200)
  expect(result[1].x).toBeGreaterThan(220)
  expect(original[0].x).toBe(100)
  result.forEach((a, i) => result.slice(i + 1).forEach(b => expect(overlaps(a, b)).toBe(false)))
})
it('keeps labels and bubbles inside the canvas, including near a boundary', () => {
  const nodes = [bubble('a', 100, 100), { ...bubble('b', 950, 700), height: 180, offsetY: 40 }]
  const result = moveBubble(nodes, 'a', { x: 950, y: 700 }, bounds)
  expect(overlaps(result[0], result[1])).toBe(false)
  for (const b of result) {
    expect(b.x - b.width / 2).toBeGreaterThanOrEqual(0)
    expect(b.x + b.width / 2).toBeLessThanOrEqual(bounds.width)
    expect(b.y + b.offsetY + b.height / 2).toBeLessThanOrEqual(bounds.height)
  }
})

it('separates the full operational map including its labels after several drags', () => {
  const positions = [[570,445],[225,420],[110,155],[105,650],[380,185],[510,70],[360,650],[255,835],[830,425],[1030,235],[1060,560],[785,745],[790,130]]
  let nodes = positions.map(([x,y], index) => ({ id: String(index), x, y, width: index ? 230 : 204, height: index ? 230 : 204, offsetY: index ? 60 : 0 }))
  const cornerCase = moveBubble(nodes, '0', { x: 165, y: 555 }, { width: 1200, height: 1040 })
  cornerCase.forEach((a, i) => cornerCase.slice(i + 1).forEach(b => expect(overlaps(a, b), `Corner: ${a.id} overlaps ${b.id}`).toBe(false)))
  for (const target of [{ x: 570, y: 445 }, { x: 1100, y: 900 }, { x: 115, y: 55 }]) {
    nodes = moveBubble(nodes, '7', target, { width: 1200, height: 1040 })
    nodes.forEach((a, i) => nodes.slice(i + 1).forEach(b => expect(overlaps(a, b), `${a.id} overlaps ${b.id}`).toBe(false)))
  }
  for (let index = 0; index < 30; index++) {
    nodes = moveBubble(nodes, String(index % nodes.length), { x: (index * 173) % 1200, y: (index * 271) % 1040 }, { width: 1200, height: 1040 })
    nodes.forEach((a, i) => nodes.slice(i + 1).forEach(b => expect(overlaps(a, b), `Drag ${index}: ${a.id} overlaps ${b.id}`).toBe(false)))
  }
})
