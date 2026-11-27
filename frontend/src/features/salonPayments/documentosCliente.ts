export const documentosCliente = {
  DNI: { etiqueta: 'DNI', patron: '[0-9]{8}', maximo: 8, numerico: true },
  RUC: { etiqueta: 'RUC', patron: '[0-9]{11}', maximo: 11, numerico: true },
  CE: { etiqueta: 'Carné de extranjería', patron: '[A-Za-z0-9]{1,20}', maximo: 20, numerico: false },
  PASAPORTE: { etiqueta: 'Pasaporte', patron: '[A-Za-z0-9]{1,30}', maximo: 30, numerico: false },
} as const

export type TipoDocumentoCliente = keyof typeof documentosCliente

export function personaDelDocumento(tipo: TipoDocumentoCliente, numero: string) {
  if (tipo !== 'RUC') return 'NATURAL'
  if (!/^[0-9]{11}$/.test(numero)) return null
  if (numero.startsWith('20')) return 'JURIDICA'
  return numero.startsWith('10') || numero.startsWith('15') ? 'NATURAL' : null
}
