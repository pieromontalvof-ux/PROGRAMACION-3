import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { Bot, Send, ShieldCheck, Sparkles, UserRound, Plus, PencilLine, CheckCheck } from 'lucide-react'
import { useAuth } from '../../context/AuthContext'
import { obtenerEstadoAsistente, solicitar, type Consulta, type EstadoAsistente, type RespuestaAsistente } from './service'
import { VoiceButton } from './VoiceButton'
import { ReviewDetails } from './ReviewDetails'
import { etiqueta, textoRevision } from './labels'
import { AnswerContent } from './AnswerContent'

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
  const [instruction, setInstruction] = useState('')
  const [review, setReview] = useState('')
  const [original, setOriginal] = useState('')
  const [context, setContext] = useState('')
  const [result, setResult] = useState<RespuestaAsistente | null>(null)
  const [busy, setBusy] = useState(false)
  const [voiceBusy, setVoiceBusy] = useState(false)
  const [checked, setChecked] = useState(false)
  const [confirmed, setConfirmed] = useState(false)
  const [editing, setEditing] = useState(false)
  const [lastPrompt, setLastPrompt] = useState('')
  const [time, setTime] = useState('')
  const [history, setHistory] = useState<{ prompt: string; response: string; time: string; done: boolean; queries: Consulta[] }[]>([])
  const latest = useRef<HTMLDivElement>(null)
  const controllers = useRef(new Set<AbortController>())
  const alive = useRef(true)
  const input = useRef<HTMLTextAreaElement>(null)
  const locked = busy || voiceBusy
  const inventoryEnabled = Boolean(estado?.capacidades?.conteos || estado?.capacidades?.stock)
  const suggestions = inventoryEnabled ? [
    ...(estado?.capacidades?.stock ? ['Muéstrame los productos bajo el mínimo'] : []),
    ...(estado?.capacidades?.conteos ? ['¿Cómo va el conteo del equipo?'] : []),
    ...(estado?.capacidades?.conteos?.includes('crear') ? ['Quiero abrir un nuevo conteo'] : []),
  ] : ['Consultar productos de la carta', 'Revisar una receta', 'Preparar un cambio de precio']
  const modified = review !== original || Boolean(instruction.trim())
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

  function prepare() {
    void action(async signal => {
      setChecked(false)
      // Retain editable text after failure, but never execute a superseded plan.
      const old = result?.borrador?.id_borrador
      if (result) setResult({ ...result, borrador: null })
      const data = await solicitar<RespuestaAsistente>(token!, 'preparar', {
        instruccion: instruction.trim() || 'Prepara nuevamente este borrador con las correcciones del texto.',
        borrador_previo: confirmed ? `YA REALIZADO: ${review}` : review, contexto_previo: context, reemplaza: old,
      }, signal)
      if (!alive.current) return
      const text = summary(data)
      if (original) setHistory(items => [...items, { prompt: lastPrompt, response: original, time, done: confirmed,
        queries: !confirmed && !result?.borrador ? result?.consultas ?? [] : [] }].slice(-10))
      setLastPrompt(instruction.trim() || 'Corregir el borrador con el texto editado.')
      setTime(new Date().toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' }))
      setEditing(false)
      setContext(current => `${current}\nUsuario: ${instruction}\nAsistente: ${text}`.slice(-16000))
      setResult(data); setReview(text); setOriginal(text); setInstruction(''); setConfirmed(false)
    })
  }

  function execute() {
    if (!result?.borrador || modified || !checked || confirmed) return
    void action(async signal => {
      const data = await solicitar<{ mensaje: string }>(token!, 'realizar', {
        id: result.borrador!.id_borrador, confirmar: true,
      }, signal)
      if (alive.current) { setConfirmed(true); setChecked(false); setSuccess(data.mensaje); setResult({ ...result, borrador: null }); setContext(current => `${current}\nOPERACIÓN CONFIRMADA Y REALIZADA: ${data.mensaje}`.slice(-16000)) }
    })
  }

  function clear() {
    void action(async signal => {
      if (result?.borrador) await solicitar(token!, 'cancelar', { id: result.borrador.id_borrador }, signal)
      if (alive.current) { setResult(null); setReview(''); setOriginal(''); setInstruction(''); setContext(''); setConfirmed(false); setChecked(false); setHistory([]); setLastPrompt(''); setEditing(false) }
    })
  }

  return <main className="assistant-page">
    <header className="assistant-heading">
      <div><h1>Barbarito<span className="assistant-brand-dot" /></h1><p>Consulta y revisa antes de realizar cambios.</p></div>
      <div className="assistant-heading-actions">
        <span className="assistant-scope"><ShieldCheck size={15} />{perfilActivo?.id_perfil === 1 ? 'Administración global' : localActivo?.nombre}</span>
        <button className="assistant-secondary" onClick={clear} disabled={locked || (!instruction && !result && !review)}><Plus size={17} />Nueva consulta</button>
      </div>
    </header>
    <details className="assistant-access"><summary><ShieldCheck size={15} />Tu acceso · {perfilActivo?.nombre}</summary>
      <div className="assistant-module-list">{estado?.modulos_consultables.map(m => <Link key={m.ruta} to={m.ruta}>{m.nombre}<span>↗</span></Link>)}</div>
      <p>Las consultas y acciones respetan tu perfil y el local activo. Los cambios requieren tu confirmación.</p>
    </details>
    {(!estado || !estado.ia_disponible || !estado.ejecucion_disponible) && <p className="assistant-status" role="status"><Sparkles size={18} />
      {!estado ? 'Verificando acceso…' : !estado.ia_disponible ? 'Falta configurar la conexión con OpenAI.' : 'Puedes consultar y dictar. La confirmación de cambios requiere completar la configuración.'}</p>}
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
          <small>{turn.done ? 'Cambio realizado' : 'Respuesta anterior · solo lectura'}</small></article></div>
      </section>)}
      {(result || review) && <div ref={latest} className="assistant-latest">
        <div className="assistant-user-row"><div className="assistant-user-bubble"><p>{lastPrompt}</p><time>{time}</time></div><span className="assistant-user-avatar"><UserRound size={20} /></span></div>
        <div className="assistant-answer-row"><span className="assistant-avatar"><Bot size={23} /></span>
          <section className="assistant-card assistant-review">
            <header className="assistant-answer-heading"><h2>{confirmed ? 'Cambio realizado' : result?.borrador ? 'Propuesta de Barbarito' : 'Respuesta de Barbarito'}</h2><time>{time}</time></header>
            <p className="assistant-answer-caption">{result?.borrador ? 'Revisa los datos antes de confirmar. Puedes corregir o añadir instrucciones.' : 'Aquí tienes la información solicitada. Puedes continuar la conversación abajo.'}</p>
            {editing ? <div className="assistant-editor"><label htmlFor="assistant-review">Editar resumen</label>
              <textarea id="assistant-review" rows={7} maxLength={16000} disabled={locked} value={review} onChange={e => { setReview(e.target.value); setChecked(false) }} />
              <small>Pulsa Enviar para preparar una nueva propuesta con tus correcciones.</small></div> :
              !result?.borrador && <AnswerContent text={review}
                queries={!confirmed && review === original ? result?.consultas ?? [] : []}
              />}
            {result?.borrador && <section className="assistant-proposal"><header><span className="assistant-eyebrow">{etiqueta(result.borrador.accion)}</span><h3>{etiqueta(result.borrador.recurso)}</h3></header>
              <ReviewDetails value={result.borrador.vista} />
              {result.borrador.recurso === 'presentaciones' && <p className="assistant-note">Nombre, tipo y categoría se comparten con las demás presentaciones del artículo.</p>}
              {result.borrador.anterior && <details><summary>Ver datos antes del cambio</summary><ReviewDetails value={result.borrador.anterior} /></details>}
            </section>}
            {result?.borrador && <label className="assistant-confirm"><input type="checkbox" checked={checked} disabled={locked || modified} onChange={e => setChecked(e.target.checked)} />Revisé los datos que se guardarán.</label>}
            {modified && result?.borrador && <p className="assistant-note">Hay correcciones pendientes. Pulsa Enviar para revisar la nueva propuesta.</p>}
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
            onChange={e => { setInstruction(e.target.value); setChecked(false) }} placeholder="Escribe una consulta o una corrección…" />
        </div>
        {token && <VoiceButton token={token} disabled={locked || !estado?.dictado_disponible} onBusy={setVoiceBusy} onError={setError}
          onText={text => { setInstruction(current => (current ? current + '\n' : '') + text); setChecked(false) }} />}
        <button className="assistant-send" onClick={prepare} disabled={locked || !estado?.ia_disponible || (!instruction.trim() && review === original) || instruction.length > 8000}><Send size={20} />{busy ? 'Procesando…' : 'Enviar'}</button>
      </div>
      <p className="assistant-compose-hint">Dicta o escribe. Tú revisas y decides qué cambios realizar.</p>
    </section>
  </main>
}
