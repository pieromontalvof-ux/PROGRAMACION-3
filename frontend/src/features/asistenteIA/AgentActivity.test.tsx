import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import { AgentActivity } from './AgentActivity'
import type { ActividadAgentes } from './service'
afterEach(cleanup)
it('shows actual participants, delegation, tool parameters and evidence download', () => {
  const activity: ActividadAgentes = { id: 'request-1', inicio: '2026-11-04T20:00:00Z', fin: '2026-11-04T20:00:02Z', entrada: 'analiza ventas', url: 'https://demo.example', estado: 'completada', agentes: ['orquestador', 'demanda'], respuesta_final: 'Informe', truncada: false, nota: 'Registro del servidor', eventos: [
    { paso: 1, fecha: '2026-11-04T20:00:00Z', tipo: 'delegacion', agente: 'orquestador', de: 'orquestador', a: 'demanda', mensaje: 'analiza ventas' },
    { paso: 2, fecha: '2026-11-04T20:00:01Z', tipo: 'herramienta_inicio', agente: 'demanda', herramienta: 'analizar_demanda', parametros: { desde: '2026-10-01' } },
  ] }
  render(<AgentActivity activity={activity} token="test" />)
  expect(screen.getByText('2 participantes')).toBeTruthy()
  expect(screen.getByText('Coordinador → Demanda y rotación', { selector: 'strong' })).toBeTruthy()
  expect(screen.getByText('analizar_demanda', { exact: false })).toBeTruthy()
  expect(screen.getByText('Descargar traza JSON')).toBeTruthy()
})
