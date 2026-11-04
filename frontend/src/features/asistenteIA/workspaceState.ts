import { useCallback, useMemo, useReducer, type SetStateAction } from 'react'
import type { Consulta, FormularioCatalogo, RespuestaAsistente } from './service'
import type { WorkflowSnapshot } from './CatalogWorkflow'

export interface WorkspaceState {
  version: 1
  instruction: string
  review: string
  original: string
  context: string
  result: RespuestaAsistente | null
  catalogForm: FormularioCatalogo | null
  formVersion: number
  formDirty: boolean
  confirmed: boolean
  lastPrompt: string
  time: string
  history: { prompt: string; response: string; time: string; done: boolean; queries: Consulta[] }[]
  resumeDraft: string | null
  draftId: string | null
  workflow: WorkflowSnapshot | null
}

export function blankWorkspace(): WorkspaceState {
  return { version: 1, instruction: '', review: '', original: '', context: '', result: null,
    catalogForm: null, formVersion: 0, formDirty: false, confirmed: false, lastPrompt: '',
    time: '', history: [], resumeDraft: null, draftId: null, workflow: null }
}

type FieldAction = { [K in keyof WorkspaceState]: { type: 'field'; key: K; value: SetStateAction<WorkspaceState[K]> } }[keyof WorkspaceState]
type Action = FieldAction | { type: 'restore'; value: WorkspaceState } | { type: 'clear' }

export function workspaceReducer(state: WorkspaceState, action: Action): WorkspaceState {
  if (action.type === 'clear') return blankWorkspace()
  if (action.type === 'restore') return { ...blankWorkspace(), ...action.value }
  const key = action.key
  const value = typeof action.value === 'function'
    ? (action.value as (current: WorkspaceState[typeof key]) => WorkspaceState[typeof key])(state[key])
    : action.value
  return { ...state, [action.key]: value }
}

export function normalizeWorkspace(value: WorkspaceState): WorkspaceState {
  const defaults = blankWorkspace()
  // Recovery metadata stays outside the editable UI snapshot.
  return Object.fromEntries(Object.entries(defaults).map(([key, fallback]) =>
    [key, value[key as keyof WorkspaceState] ?? fallback])) as unknown as WorkspaceState
}

export function useWorkspaceState() {
  const [state, dispatch] = useReducer(workspaceReducer, undefined, blankWorkspace)
  const field = useCallback(<K extends keyof WorkspaceState>(key: K) =>
    (value: SetStateAction<WorkspaceState[K]>) => dispatch({ type: 'field', key, value } as FieldAction), [])
  const setters = useMemo(() => ({
    setInstruction: field('instruction'), setReview: field('review'), setOriginal: field('original'),
    setContext: field('context'), setResult: field('result'), setCatalogForm: field('catalogForm'),
    setFormVersion: field('formVersion'), setFormDirty: field('formDirty'), setConfirmed: field('confirmed'),
    setLastPrompt: field('lastPrompt'), setTime: field('time'), setHistory: field('history'),
    setResumeDraft: field('resumeDraft'), setDraftId: field('draftId'), setWorkflow: field('workflow'),
  }), [field])
  return { state, ...setters,
    restore: useCallback((value: WorkspaceState) => dispatch({ type: 'restore', value }), []),
    reset: useCallback(() => dispatch({ type: 'clear' }), []),
  }
}

export function hasWorkspace(state: WorkspaceState) {
  return Boolean(state.instruction || state.review || state.result || state.workflow || state.history.length)
}
