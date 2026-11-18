import {describe,it,expect} from 'vitest'
import {conversationReference,appendConversation} from './conversationContext'

describe('bounded conversation references',()=>{
  it('keeps normal replies unchanged and summarizes large tables for the next request',()=>{
    expect(conversationReference('Confirma 10%')).toBe('Confirma 10%')
    const report='Entrega: 2026-11-22\n### Stock\n| Insumo | Cantidad |\n| --- | --- |\n'+Array.from({length:1000},(_,i)=>`| Insumo ${i} | 10 unidades |`).join('\n')
    const reference=conversationReference(report)
    expect(reference.length).toBeLessThanOrEqual(12000)
    expect(reference).toContain('2026-11-22')
    expect(reference).toContain('1000 filas')
    expect(report).toContain('Insumo 999')
  })
  it('preserves the newest user instruction in full when history is large',()=>{
    const prompt='Instrucción '.repeat(600)
    const context=appendConversation('Historia '.repeat(3000),prompt,'Respuesta '.repeat(3000))
    expect(context.length).toBeLessThanOrEqual(16000)
    expect(context).toContain(`Usuario: ${prompt}`)
  })
})
