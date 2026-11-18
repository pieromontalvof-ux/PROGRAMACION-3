// Visible answers stay intact; requests need references, not another copy of every row.
export function conversationReference(text: string, maximum = 12000): string {
  if (text.length <= maximum) return text
  const lines = text.split('\n'), result: string[] = []
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*\|/.test(lines[i])) {
      const heading = lines[i].trim()
      let count = 0
      while (i < lines.length && /^\s*\|/.test(lines[i])) { count++; i++ }
      i--
      result.push(`Cuadro consultado: ${heading} (${Math.max(0,count-2)} filas). Consultar los registros vigentes para obtener cifras.`)
    } else result.push(lines[i])
  }
  const reference = result.join('\n')
  if (reference.length <= maximum) return reference
  const note='\n[Referencia resumida; consultar los datos vigentes para el detalle.]\n'
  const half=Math.max(0,Math.floor((maximum-note.length)/2))
  return reference.slice(0,half)+note+reference.slice(-half)
}

export function appendConversation(current: string, prompt: string, answer: string): string {
  const recent=`\nUsuario: ${prompt}\nAsistente: ${conversationReference(answer,6000)}`
  const available=Math.max(0,16000-recent.length)
  return (available ? conversationReference(current).slice(-available) : '')+recent
}
