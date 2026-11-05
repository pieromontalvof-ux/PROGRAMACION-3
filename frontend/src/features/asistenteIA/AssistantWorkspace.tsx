import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { Bot, Send, ShieldCheck, Sparkles, UserRound, Plus, PencilLine, CheckCheck } from 'lucide-react'
import { useAuth } from '../../context/AuthContext'
import { obtenerEstadoAsistente, solicitar, type EstadoAsistente, type RespuestaAsistente } from './service'
import { CatalogWorkflow, type WorkflowSnapshot } from './CatalogWorkflow'
import { useWorkspaceState, hasWorkspace, normalizeWorkspace } from './workspaceState'
import { useWorkspacePersistence } from './useWorkspacePersistence'
import { nombresAgentes } from './service'
import { VoiceButton } from './VoiceButton'
import { ReviewDetails } from './ReviewDetails'
import { etiqueta, textoRevision } from './labels'
import { AnswerContent } from './AnswerContent'
import { AgentActivity } from './AgentActivity'

function summary(result: RespuestaAsistente) {
  const b = result.borrador
  return b ? `${etiqueta(b.accion)} ${etiqueta(b.recurso)}${b.id ? ` (registro ${b.id})` : ''}\n` +
    textoRevision(b.vista) : result.respuesta
}

export function AssistantWorkspace() {
  const { token, perfilActivo, localActivo } = useAuth()
  const [estado, setEstado] = useState<EstadoAsistente | null>(null)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const workspace = useWorkspaceState()
  const { state, setInstruction, setReview, setOriginal, setContext, setResult, setCatalogForm,
    setFormVersion, setFormDirty, setConfirmed, setLastPrompt, setTime, setHistory,
    setResumeDraft, setDraftId, setWorkflow } = workspace
  const { instruction, review, original, context, result, catalogForm, formVersion, formDirty,
    confirmed, lastPrompt, time, history, resumeDraft, workflow } = state
  const [continuation, setContinuation] = useState<string | undefined>()
  const [busy, setBusy] = useState(false)
  const [voiceBusy, setVoiceBusy] = useState(false)
  const [workflowBusy, setWorkflowBusy] = useState(false)
  const [dependencyOpen, setDependencyOpen] = useState(false)
  const [checked, setChecked] = useState(false)
  const [editing, setEditing] = useState(false)
  const latest = useRef<HTMLDivElement>(null)
  const controllers = useRef(new Set<AbortController>())
  const alive = useRef(true)
  const input = useRef<HTMLTextAreaElement>(null)
  const progress = useWorkspacePersistence(token, hasWorkspace(state) ? state : null, saved => {
    const restored = normalizeWorkspace(saved)
    workspace.restore(restored); setContinuation(restored.result?.continuacion)
    setChecked(false); setEditing(false); setDependencyOpen(Boolean(restored.workflow && restored.workflow.frames.length > 1))
  })
  const locked = busy || voiceBusy || workflowBusy || dependencyOpen || progress.status === 'loading' || progress.status === 'conflict'
  const inventoryEnabled = Boolean(estado?.capacidades?.conteos || estado?.capacidades?.stock)
  const catalogFormsEnabled = ['categorias_productos', 'proveedores', 'productos', 'categorias_carta', 'menajes', 'presentaciones'].some(r => estado?.capacidades?.[r]?.includes('crear'))
  const suggestions = [
    ...(estado?.capacidades?.ordenes_compra?.includes('consultar') ? ['Quiero hacer un pedido'] : []),
    ...(inventoryEnabled ? [
    ...(estado?.capacidades?.stock ? ['Muéstrame los productos bajo el mínimo'] : []),
    ...(estado?.capacidades?.conteos ? ['¿Cómo va el conteo del equipo?'] : []),
    ...(estado?.capacidades?.conteos?.includes('crear') ? ['Quiero abrir un nuevo conteo'] : []),
  ] : catalogFormsEnabled ? ['Crear categoría de productos', 'Crear proveedor', 'Crear producto'] : ['Consultar productos de la carta', 'Revisar una receta', 'Preparar un cambio de precio']),
  ]
  const modified = review !== original || Boolean(instruction.trim()) || formDirty
  const sendDisabled = locked || Boolean(resumeDraft) || (!estado?.ia_disponible && !catalogFormsEnabled) || (!instruction.trim() && review === original) || instruction.length > 8000
  useEffect(() => { if (original) latest.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }) }, [original])
  useEffect(() => {
    alive.current = true
    const controller = new AbortController()
    if (token) obtenerEstadoAsistente(token, controller.signal)
      .then(data => { if (!controller.signal.aborted) setEstado(data) })
      .catch(e => { if (!controller.signal.aborted) setError(e.message) })
    const pending = controllers.current
    return () => { alive.current = false; controller.abort(); pending.forEach(c => c.abort()) }
  }, [token])

  async function action(work: (signal: AbortSignal) => Promise<void>) {
    if (!token || locked) return
    const controller = new AbortController()
    controllers.current.add(controller)
    setBusy(true); setError(''); setSuccess('')
    try { await work(controller.signal) }
    catch (e) { if (alive.current) setError(e instanceof Error ? e.message : 'No se pudo completar la operación.') }
    finally { controllers.current.delete(controller); if (alive.current) setBusy(false) }
  }

  function prepare(selectedInstruction?: string) {
    const prompt = selectedInstruction ?? instruction.trim()
    void action(async signal => {
      setChecked(false)
      // Retain editable text after failure, but never execute a superseded plan.
      const old = result?.borrador?.id_borrador
      if (result) setResult({ ...result, borrador: null })
      const data = await solicitar<RespuestaAsistente>(token!, 'preparar', {
        instruccion: prompt || 'Prepara nuevamente este borrador con las correcciones del texto.',
        borrador_previo: confirmed ? `YA REALIZADO: ${review}` : review, contexto_previo: context, reemplaza: old,
        continuacion: continuation,
        flujo_compra: confirmed ? undefined : result?.flujo_compra,
      }, signal)
      if (!alive.current) return
      const text = summary(data)
      if (original) setHistory(items => [...items, { prompt: lastPrompt, response: original, time, done: confirmed,
        actividad: result?.actividad,
        queries: !confirmed && !result?.borrador ? result?.consultas ?? [] : [] }].slice(-10))
      setLastPrompt(prompt || 'Corregir el borrador con el texto editado.')
      setTime(new Date().toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' }))
      setEditing(false)
      setContext(current => `${current}\nUsuario: ${prompt}\nAsistente: ${text}`.slice(-16000))
      setResult(data); setReview(text); setOriginal(text); setInstruction(''); setConfirmed(false)
      setContinuation(data.continuacion); setResumeDraft(null)
      setCatalogForm(data.formulario ?? null); setWorkflow(null); setDraftId(data.borrador?.id_borrador ?? null); setFormVersion(v => v + 1); setFormDirty(false)
    })
  }

  function reviewForm(datos: Record<string, unknown>) {
    if (!catalogForm) return
    void action(async signal => {
      const data = await solicitar<RespuestaAsistente>(token!, 'formulario/preparar', {
        recurso: catalogForm.recurso, datos, reemplaza: result?.borrador?.id_borrador,
        continuacion: continuation,
      }, signal)
      if (!alive.current) return
      const text = summary(data)
      setResult({ ...data, continuacion: continuation, tarea_pendiente: result?.tarea_pendiente,
        comunicaciones: result?.comunicaciones }); setReview(text); setOriginal(text); setInstruction(''); setFormDirty(false)
      setChecked(false); setConfirmed(false); setEditing(false); setDraftId(data.borrador?.id_borrador ?? null)
      setContext(current => `${current}\nFormulario: ${catalogForm.titulo}\nPropuesta: ${text}`.slice(-16000))
    })
  }

  async function invalidateFormProposal() {
    if (result?.borrador) await solicitar(token!, 'cancelar', { id: result.borrador.id_borrador })
    if (!alive.current) return
    setResult(current => current ? { ...current, borrador: null } : null)
    setDraftId(null)
    const text = 'Completa los requisitos del formulario para continuar con la creación.'
    setReview(text); setOriginal(text); setInstruction(''); setChecked(false); setFormDirty(true)
  }

  function execute() {
    if (!result?.borrador || modified || !checked || confirmed) return
    void action(async signal => {
      const draftId = result.borrador!.id_borrador
      await progress.flush()
      const data = await solicitar<{ mensaje: string }>(token!, 'realizar', {
        id: draftId, confirmar: true,
      }, signal)
      if (alive.current) { setConfirmed(true); setChecked(false); setCatalogForm(null); setWorkflow(null); setFormDirty(false); setSuccess(data.mensaje); setResult({ ...result, borrador: null }); setContext(current => `${current}\nOPERACIÓN CONFIRMADA Y REALIZADA: ${data.mensaje}`.slice(-16000)) }
      if (alive.current && continuation && result.tarea_pendiente) {
        setResumeDraft(draftId)
        await resumeTask(draftId, signal)
      } else if (alive.current) {
        setContinuation(undefined)
        setResult(current => current ? { ...current, continuacion: undefined } : null)
      }
    })
  }

  async function resumeTask(draftId: string, signal: AbortSignal) {
    const data = await solicitar<RespuestaAsistente>(token!, 'continuar', {
      continuacion: continuation, id_borrador: draftId,
    }, signal)
    if (!alive.current) return
    const text = summary(data)
    setResult(data); setContinuation(data.continuacion); setResumeDraft(null)
    setReview(text); setOriginal(text); setInstruction(''); setConfirmed(false); setChecked(false)
    setCatalogForm(data.formulario ?? null); setWorkflow(null); setDraftId(data.borrador?.id_borrador ?? null); setFormVersion(v => v + 1); setFormDirty(false)
    setContext(current => `${current}\nTAREA RETOMADA: ${text}`.slice(-16000))
  }

  function clear() {
    void action(async signal => {
      if (result?.borrador) await solicitar(token!, 'cancelar', { id: result.borrador.id_borrador }, signal)
      await progress.clear()
      if (alive.current) { workspace.reset(); setResult(null); setContinuation(undefined); setResumeDraft(null); setCatalogForm(null); setFormDirty(false); setReview(''); setOriginal(''); setInstruction(''); setContext(''); setConfirmed(false); setChecked(false); setHistory([]); setLastPrompt(''); setEditing(false) }
    })
  }

  return <main className="assistant-page">
    <header className="assistant-heading">
      <div><h1>Barbarito<span className="assistant-brand-dot" /></h1><p>Consulta y revisa antes de realizar cambios.</p></div>
      <div className="assistant-heading-actions">
        <span className="assistant-scope"><ShieldCheck size={15} />{perfilActivo?.id_perfil === 1 ? 'Administración global' : localActivo?.nombre}</span>
        <button className="assistant-secondary" onClick={clear} disabled={locked || (!instruction && !result && !review)}><Plus size={17} />Limpiar conversación</button>
      </div>
    </header>
    <div className="assistant-progress" role="status">
      {progress.status === 'loading' ? 'Recuperando tu progreso…' : progress.status === 'saving' ? 'Guardando progreso…' : progress.message || 'El progreso se guarda para este perfil y tienda.'}
      {(progress.status === 'error' || progress.status === 'conflict' || progress.status === 'unavailable') && <button className="assistant-secondary" disabled={busy || workflowBusy} onClick={progress.reload}>Recargar progreso</button>}
    </div>
    <details className="assistant-access"><summary><ShieldCheck size={15} />Tu acceso · {perfilActivo?.nombre}</summary>
      <div className="assistant-module-list">{estado?.modulos_consultables.map(m => <Link key={m.ruta} to={m.ruta}>{m.nombre}<span>↗</span></Link>)}</div>
      <p>Las consultas y acciones respetan tu perfil y el local activo. Los cambios requieren tu confirmación.</p>
    </details>
    {(!estado || !estado.ia_disponible || !estado.ejecucion_disponible) && <p className="assistant-status" role="status"><Sparkles size={18} />
      {!estado ? 'Verificando acceso…' : !estado.ia_disponible ? catalogFormsEnabled ? 'Los formularios de catálogo están disponibles. Las consultas libres y el dictado requieren configurar la conexión con OpenAI.' : 'Falta configurar la conexión con OpenAI.' : 'Puedes consultar y dictar. La confirmación de cambios requiere completar la configuración.'}</p>}
    <div className="assistant-conversation">
      {!result && !review && !history.length && <section className="assistant-welcome">
        <div className="assistant-avatar assistant-avatar-large"><Bot size={32} /></div>
        <span className="assistant-eyebrow">TU ASISTENTE DE GESTIÓN</span>
        <h2>Empecemos con una consulta</h2><p>Escribe o dicta lo que necesitas.<br />Yo te ayudo a encontrarlo y preparar el siguiente paso.</p>
        {inventoryEnabled && <p className="assistant-note">Agente de inventario disponible: consulta existencias y conteos desde esta conversación.</p>}
        <div className="assistant-suggestions">{suggestions.map(s =>
          <button key={s} className="assistant-secondary" disabled={locked} onClick={() => { setInstruction(s); input.current?.focus() }}>{s}<span>↗</span></button>)}</div>
      </section>}
      {history.map((turn, i) => <section key={i} className="assistant-past-turn">
        <div className="assistant-user-row"><div className="assistant-user-bubble"><p>{turn.prompt}</p><time>{turn.time}</time></div><span className="assistant-user-avatar"><UserRound size={20} /></span></div>
        <div className="assistant-answer-row"><span className="assistant-avatar"><Bot size={23} /></span><article className="assistant-card assistant-past-answer">
          <header className="assistant-answer-heading"><h2>Barbarito</h2><time>{turn.time}</time></header>
          <AnswerContent text={turn.response} queries={turn.queries} />
          {turn.actividad && token && <AgentActivity activity={turn.actividad} token={token} />}
          <small>{turn.done ? 'Cambio realizado' : 'Respuesta anterior · solo lectura'}</small></article></div>
      </section>)}
      {(result || review) && <div ref={latest} className="assistant-latest">
        <div className="assistant-user-row"><div className="assistant-user-bubble"><p>{lastPrompt}</p><time>{time}</time></div><span className="assistant-user-avatar"><UserRound size={20} /></span></div>
        <div className="assistant-answer-row"><span className="assistant-avatar"><Bot size={23} /></span>
          <section className="assistant-card assistant-review">
            <header className="assistant-answer-heading"><h2>{confirmed ? 'Cambio realizado' : result?.borrador ? 'Propuesta de Barbarito' : 'Respuesta de Barbarito'}</h2>
              {result?.agente && <small className="assistant-agent-label">{nombresAgentes[result.agente]}</small>}
              <time>{time}</time></header>
            <p className="assistant-answer-caption">{result?.borrador ? 'Revisa los datos antes de confirmar. Puedes corregir o añadir instrucciones.' : 'Aquí tienes la información solicitada. Puedes continuar la conversación abajo.'}</p>
            {result?.actividad && token && <AgentActivity activity={result.actividad} token={token} />}
            {result?.nota_actividad && <p className="assistant-note" role="status">{result.nota_actividad}</p>}
            {Boolean(result?.comunicaciones?.length) && <details className="assistant-access"><summary>Colaboración entre agentes</summary>
              {result?.comunicaciones?.map((message, index) => <p key={index}><strong>{nombresAgentes[message.de]} → {nombresAgentes[message.a]}</strong>: {message.motivo}</p>)}
            </details>}
            {result?.tarea_pendiente && <p className="assistant-note">Después de este requisito retomaremos: {result.tarea_pendiente}</p>}
            {resumeDraft && <button className="assistant-secondary" disabled={locked} onClick={() => { void action(signal => resumeTask(resumeDraft, signal)) }}>Retomar tarea pendiente</button>}
            {catalogForm && token && <CatalogWorkflow key={formVersion} token={token} form={catalogForm} disabled={busy || voiceBusy}
              onChange={() => { setFormDirty(true); setChecked(false) }} onReview={reviewForm} onInvalidate={invalidateFormProposal}
              initialSnapshot={workflow} onSnapshot={setWorkflow}
              onCheckpoint={async (snapshot: WorkflowSnapshot) => { setWorkflow(snapshot); await progress.flush({ ...state, workflow: snapshot }) }}
              onNestedChange={setDependencyOpen} onBusy={setWorkflowBusy} onSaved={message => { setSuccess(message); setContext(current => `${current}\nREQUISITO CREADO: ${message}`.slice(-16000)) }} />}
            {editing ? <div className="assistant-editor"><label htmlFor="assistant-review">Editar resumen</label>
              <textarea id="assistant-review" rows={7} maxLength={16000} disabled={locked} value={review} onChange={e => { setReview(e.target.value); setChecked(false) }} />
              <small>Pulsa Enviar para preparar una nueva propuesta con tus correcciones.</small></div> :
              !result?.borrador && <AnswerContent text={review}
                queries={!confirmed && review === original ? result?.consultas ?? [] : []}
              />}
            {!confirmed && Boolean(result?.opciones?.length) && <div className="assistant-suggestions" aria-label="Opciones para continuar">
              {result?.opciones?.map(option => <button key={option.instruccion} className="assistant-secondary" disabled={locked} onClick={() => prepare(option.instruccion)}>{option.etiqueta}</button>)}
            </div>}
            {result?.borrador && <section className="assistant-proposal"><header><span className="assistant-eyebrow">{etiqueta(result.borrador.accion)}</span><h3>{etiqueta(result.borrador.recurso)}</h3></header>
              <ReviewDetails value={result.borrador.vista} />
              {result.borrador.recurso === 'presentaciones' && <p className="assistant-note">Nombre, tipo y categoría se comparten con las demás presentaciones del artículo.</p>}
              {result.borrador.anterior && <details><summary>Ver datos antes del cambio</summary><ReviewDetails value={result.borrador.anterior} /></details>}
            </section>}
            {result?.borrador && <label className="assistant-confirm"><input type="checkbox" checked={checked} disabled={locked || modified} onChange={e => setChecked(e.target.checked)} />Revisé los datos que se guardarán.</label>}
            {modified && result?.borrador && <p className="assistant-note">Hay correcciones pendientes. {formDirty ? 'Pulsa Revisar propuesta en el formulario.' : 'Pulsa Enviar para revisar la nueva propuesta.'}</p>}
            <footer className="assistant-answer-actions"><div>
              <button className="assistant-secondary" disabled={locked} onClick={() => { input.current?.focus(); input.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }) }}><PencilLine size={16} />Corregir / más instrucciones</button>
              <button className="assistant-text-button" disabled={locked} onClick={() => setEditing(v => !v)}>{editing ? 'Ver respuesta' : 'Editar resumen'}</button>
            </div>{confirmed ? <span className="assistant-completed"><CheckCheck size={18} />Realizado</span> : result?.borrador &&
              <button onClick={execute} disabled={locked || modified || !checked || !estado?.ejecucion_disponible}>Realizar</button>}
            </footer>
          </section>
        </div>
      </div>}
      {busy && <p className="assistant-working" role="status"><span />Barbarito está trabajando…</p>}
    </div>
    <section className="assistant-compose-wrap" aria-label="Escribe a Barbarito">
      {error && <p role="alert" className="assistant-error">{error}</p>}
      {success && <p role="status" className="assistant-status"><CheckCheck size={18} />{success}</p>}
      <div className="assistant-composer">
        <div className="assistant-input-wrap"><PencilLine size={20} /><label className="assistant-sr-only" htmlFor="assistant-instruction">Consulta o corrección</label>
          <textarea ref={input} id="assistant-instruction" disabled={locked} rows={2} maxLength={8000} value={instruction}
            onKeyDown={e => {
              if (e.key !== 'Enter' || e.shiftKey || e.ctrlKey || e.altKey || e.metaKey || e.nativeEvent.isComposing || e.repeat) return
              e.preventDefault()
              if (!sendDisabled) prepare()
            }}
            onChange={e => { setInstruction(e.target.value); setChecked(false) }} placeholder="Escribe una consulta o una corrección…" />
        </div>
        {token && <VoiceButton token={token} disabled={locked || !estado?.dictado_disponible} onBusy={setVoiceBusy} onError={setError}
          onText={text => { setInstruction(current => (current ? current + '\n' : '') + text); setChecked(false) }} />}
        <button className="assistant-send" onClick={() => prepare()} disabled={sendDisabled}><Send size={20} />{busy ? 'Procesando…' : 'Enviar'}</button>
      </div>
      <p className="assistant-compose-hint">Enter para enviar · Shift + Enter para salto de línea. Tú confirmas los cambios.</p>
    </section>
  </main>
}
