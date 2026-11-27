import {describe,it,expect} from 'vitest'
import {textoRevision} from './labels'
import {purchaseSummary,legacyPurchaseSummary} from './purchaseSummary'

describe('purchase result summary',()=>{
  const rows=[{producto:'Gin',unidad:'LTR',unidad_medida:{simbolo:'L',factor_a_base:'1'},unidad_fraccion:{simbolo:'mL',factor_a_base:'0.001'},presentacion_compra:0.6,cantidad_final:2.4,porcentaje_general:10,porcentaje_adicional:10}]
  it('keeps presentation, package count and final quantity in a clean table',()=>{
    const text=purchaseSummary(rows)
    expect(text).toContain('| Gin | 10% + 10% extra | 600 mL | 4 | 2.4 L |')
    expect(text).not.toContain('Antes de redondear')
  })
  it('reformats already saved legacy results without saving another order',()=>{
    const text='Crear Ordenes compra\n'+textoRevision({advertencia:'Aviso técnico',eventos_cercanos:null,productos:rows})
    const formatted=legacyPurchaseSummary(text)
    expect(formatted).toContain('| Gin | 10% + 10% extra | 0.6 LTR | 4 | 2.4 LTR |')
    expect(formatted).not.toContain('Aviso técnico')
    expect(legacyPurchaseSummary('Consulta general')).toBeNull()
  })
})
