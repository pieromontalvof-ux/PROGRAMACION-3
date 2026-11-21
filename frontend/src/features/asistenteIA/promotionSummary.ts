type Group = { cantidad_elegir: number; permite_repetir?: boolean; opciones: unknown[] }
type Promotion = { nombre?: string; precio?: number; activo?: boolean; hora_inicio?: string | null; hora_fin?: string | null; grupos: Group[] }

export const optionLabel = (value: unknown) => String(value).replace(/\s*\(#\d+\)$/, '').replace(/\bLTR\b/g, 'L').replace(/\bPORCION\b/g, 'porción')
export const money = (value: unknown) => typeof value === 'number' ? `S/ ${value.toFixed(2)}` : 'Precio por definir'
export const schedule = (p: Promotion) => p.hora_inicio && p.hora_fin ? `${p.hora_inicio}–${p.hora_fin}` : p.hora_inicio || p.hora_fin ? 'Horario por completar' : 'Sin restricción horaria'

export function asPromotion(value: unknown): Promotion | null {
  if (!value || typeof value !== 'object') return null
  const p = value as Promotion
  return Array.isArray(p.grupos) && p.grupos.every(g => g && typeof g.cantidad_elegir === 'number' && Array.isArray(g.opciones)) ? p : null
}

export function promotionSummary(value: unknown): string | null {
  const p = asPromotion(value)
  if (!p) return null
  return `### ${p.nombre || 'Promoción'}\n${money(p.precio)} · ${p.activo === true ? 'Activa' : p.activo === false ? 'Inactiva' : 'Estado por definir'} · ${schedule(p)}\n\n` +
    '| Incluye | Productos |\n| --- | --- |\n' +
    p.grupos.map(g => `| ${g.opciones.length === 1 ? 'Incluye' : 'Elige'} ${g.cantidad_elegir} | ${g.opciones.map(optionLabel).join(' o ')}${g.opciones.length > 1 && g.cantidad_elegir > 1 ? (g.permite_repetir ? ' (puedes repetir)' : ' (opciones diferentes)') : ''} |`.replace(/[\r]/g,'').replace(/\n/g,' ')).join('\n')
}

// Restore presentation only: old workspace summaries remain read-only data.
// Unknown formats are left intact instead of hiding unrecognized information.
export function legacyPromotionSummary(text: string): string | null {
  if (!/^(Crear|Editar) Promociones\r?\n/.test(text)) return null
  const p: Promotion = {grupos:[]}
  let group: Group | undefined
  let readingOptions = false
  for (const source of text.split(/\r?\n/).slice(1)) {
    const line = source.trim().replace(/^\d+\.\s*/, '')
    if (!line || line === 'Grupos:') continue
    const count = line.match(/^Cantidad a elegir: (\d+)$/)
    if (count) { group={cantidad_elegir:Number(count[1]),opciones:[]};p.grupos.push(group);readingOptions=false;continue }
    if (line === 'Opciones:' && group) { readingOptions=true;continue }
    const repeat=line.match(/^Permite repetir: (Sí|No)$/)
    if (repeat && group) { group.permite_repetir=repeat[1]==='Sí';readingOptions=false;continue }
    if (line.startsWith('Nombre: ')) {p.nombre=line.slice(8);readingOptions=false;continue}
    if (line.startsWith('Precio: ')) {p.precio=Number(line.slice(8));readingOptions=false;continue}
    if (/^Activo: (Sí|No)$/.test(line)) {p.activo=line==='Activo: Sí';continue}
    const time=line.match(/^Hora de (inicio|fin): (Sin asignar|\d{2}:\d{2}(?::\d{2})?)$/)
    if(time) {p[time[1]==='inicio'?'hora_inicio':'hora_fin']=time[2]==='Sin asignar'?null:time[2];readingOptions=false;continue}
    if(readingOptions && group && /\(#\d+\)$/.test(line)) {group.opciones.push(line);continue}
    return null
  }
  if(!p.nombre || !Number.isFinite(p.precio) || typeof p.activo!=='boolean' || !p.grupos.length || p.grupos.some(g=>!g.opciones.length))return null
  return promotionSummary(p)
}
