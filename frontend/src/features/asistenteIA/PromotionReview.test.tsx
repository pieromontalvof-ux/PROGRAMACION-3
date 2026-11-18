import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import { ReviewDetails } from './ReviewDetails'
import { AnswerContent } from './AnswerContent'
import { textoRevision } from './labels'

afterEach(cleanup)
it('renders older saved promotion summaries as a clean table', () => {
  const text='Crear Promociones\n'+textoRevision({activo:true,grupos:[
    {cantidad_elegir:2,opciones:['174 IPA · 0.2 LTR (#118)'],permite_repetir:true},
    {cantidad_elegir:1,opciones:['Nachos · 1.0 PORCION (#68)','Papas · 1.0 PORCION (#61)'],permite_repetir:false},
  ],hora_fin:null,hora_inicio:null,nombre:'Inicio para 2',precio:39.9})
  render(<AnswerContent text={text} />)
  expect(screen.getByRole('heading',{name:'Inicio para 2'})).toBeTruthy()
  expect(screen.getByRole('table')).toBeTruthy()
  expect(screen.getByRole('cell',{name:'Incluye 2'})).toBeTruthy()
  expect(screen.queryByText(/Permite repetir/)).toBeNull()
})
it('shows fixed quantities and customer choices without technical fields', () => {
  render(<ReviewDetails resource="promociones" value={{ nombre:'Inicio para 2', precio:39.9, activo:true,
    hora_inicio:null, hora_fin:null, grupos:[
      {cantidad_elegir:2, permite_repetir:true, opciones:['174 IPA · 0.2 LTR (#118)']},
      {cantidad_elegir:1, permite_repetir:false, opciones:['Nachos Pulled Pork · 1.0 PORCION (#68)','Papas Bárbaras · 1.0 PORCION (#61)']},
    ] }} />)
  expect(screen.getByRole('heading',{name:'Inicio para 2'})).toBeTruthy()
  expect(screen.getByText('S/ 39.90')).toBeTruthy()
  expect(screen.getByText('Incluye 2')).toBeTruthy()
  expect(screen.getByText('Elige 1')).toBeTruthy()
  expect(screen.getByText(/Sin restricción horaria/)).toBeTruthy()
  expect(screen.queryByText('Permite repetir')).toBeNull()
  expect(screen.queryByText(/#118/)).toBeNull()
})
