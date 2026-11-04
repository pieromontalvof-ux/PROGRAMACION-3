import { useEffect, useRef, useState } from 'react'
import { Link, Navigate, useNavigate, useLocation } from 'react-router-dom'
import { Bot, FolderOpen, FileText, Network, Save, Upload, Trash2, X, ScanSearch, ShieldCheck, Sparkles, Download } from 'lucide-react'
import { useAuth } from '../../context/AuthContext'
import { AgentMap } from './AgentMap'
import { AgentConnections } from './AgentConnections'
import { bibliotecaAgentes, originalDocumentoAgente, obtenerAgentesAsistente, type CarpetaAgente, type CatalogoAgentes, type ConfiguracionAgente, type RevisionConfiguracion, type InformeConfiguracion, type DocumentoAgente, type PropuestaSkill } from './service'
import './AssistantPage.css'
import './AgentAdminPage.css'

type Mode = 'mapa' | 'archivos' | 'permisos'
type Preview = { nombre: string; contenido: string; url: string; mime: string; original: boolean }

export function AgentAdminPage({ mode }: { mode: Mode }) {
  const { token, perfilActivo } = useAuth()
  if (perfilActivo?.id_perfil !== 1) return <Navigate to="/home/asistente-ia" replace />
  return <AgentAdministration key={`${token}-${mode}`} token={token!} mode={mode} />
}

function AgentAdministration({ token, mode }: { token: string; mode: Mode }) {
  const navigate = useNavigate()
  const location = useLocation()
  const initialAgent = useRef(new URLSearchParams(location.search).get('agente'))
  const [catalog, setCatalog] = useState<CatalogoAgentes | null>(null)
  const [folders, setFolders] = useState<Pick<CarpetaAgente, 'id' | 'nombre' | 'documentos'>[]>([])
  const [selected, setSelected] = useState('')
  const [folder, setFolder] = useState<CarpetaAgente | null>(null)
  const [draft, setDraft] = useState<ConfiguracionAgente | null>(null)
  const [skillFile, setSkillFile] = useState('')
  const [sources, setSources] = useState<string[]>([])
  const [inspection, setInspection] = useState<RevisionConfiguracion | null>(null)
  const [proposal, setProposal] = useState<PropuestaSkill | null>(null)
  const [preview, setPreview] = useState<Preview | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [working, setWorking] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [reload, setReload] = useState(0)
  const controller = useRef<AbortController | null>(null)
  const uploadInput = useRef<HTMLInputElement>(null)
  const validationPanel = useRef<HTMLElement>(null)
  const dirty = Boolean(folder && draft && JSON.stringify(mode === 'permisos' ? draft.accesos : draft.skills) !== JSON.stringify(mode === 'permisos' ? folder.configuracion.accesos : folder.configuracion.skills))
  const skill = draft?.skills.find(item => item.archivo === skillFile)

  useEffect(() => {
    const signal = new AbortController()
    const request = mode === 'mapa' ? obtenerAgentesAsistente(token, signal.signal).then(setCatalog)
      : bibliotecaAgentes<{ agentes: typeof folders }>(token, '', 'GET', undefined, signal.signal).then(data => { setFolders(data.agentes); setSelected(data.agentes.find(agent => agent.id === initialAgent.current)?.id ?? data.agentes[0]?.id ?? '') })
    void request.catch(e => { if (!signal.signal.aborted) setError(e.message) }).finally(() => { if (!signal.signal.aborted) setLoading(false) })
    return () => { signal.abort(); controller.current?.abort() }
  }, [token, mode])

  useEffect(() => {
    if (!selected) return
    const signal = new AbortController()
    setFolder(null); setPreview(null); setInspection(null); setProposal(null); setError(''); setMessage('')
    void bibliotecaAgentes<CarpetaAgente>(token, `/${selected}`, 'GET', undefined, signal.signal).then(data => {
      setFolder(data); setDraft(data.configuracion); setSkillFile(data.configuracion.skills[0]?.archivo ?? '')
      setSources(data.documentos.map(document => document.id))
    }).catch(e => { if (!signal.signal.aborted) setError(e.message) })
    return () => signal.abort()
  }, [token, selected, reload])

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview.url) }, [preview])
  useEffect(() => { if (inspection) validationPanel.current?.scrollIntoView?.({ behavior: 'smooth', block: 'start' }) }, [inspection])
  useEffect(() => {
    if (!dirty) return
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = '' }
    const leave = (event: MouseEvent) => {
      const link = (event.target as Element).closest?.('a[href]') as HTMLAnchorElement | null
      if (!link || link.target === '_blank' || link.download || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || link.pathname === window.location.pathname) return
      if (!window.confirm('Hay cambios sin guardar. ¿Descartarlos y salir?')) { event.preventDefault(); event.stopPropagation() }
    }
    window.addEventListener('beforeunload', warn); document.addEventListener('click', leave, true)
    return () => { window.removeEventListener('beforeunload', warn); document.removeEventListener('click', leave, true) }
  }, [dirty])

  function choose(id: string) {
    if (busy || selected === id) return
    if (dirty && !window.confirm('Hay cambios sin guardar. ¿Descartarlos y abrir otra carpeta?')) return
    setSelected(id)
  }

  async function action(label: string, work: (signal: AbortSignal) => Promise<void>) {
    if (busy) return
    const signal = new AbortController()
    controller.current = signal
    setBusy(true); setWorking(label); setError(''); setMessage('')
    try { await work(signal.signal) }
    catch (e) { if (!signal.signal.aborted) setError(e instanceof Error ? e.message : 'No se completó la operación.') }
    finally { if (!signal.signal.aborted) { setBusy(false); setWorking('') } }
  }

  function update(data: CarpetaAgente) {
    setFolder(data)
    setFolders(current => current.map(row => row.id === data.id ? { ...row, documentos: data.documentos } : row))
  }

  function editSkills(content: string) {
    setDraft(current => current ? { ...current, skills: current.skills.map(item => item.archivo === skillFile ? { ...item, contenido: content } : item) } : current)
    setInspection(null); setProposal(null); setMessage('')
  }

  async function fresh(signal: AbortSignal) {
    const data = await bibliotecaAgentes<CarpetaAgente>(token, `/${selected}`, 'GET', undefined, signal)
    if (folder && data.revision !== folder.revision && JSON.stringify(data.configuracion.skills) !== JSON.stringify(folder.configuracion.skills)) throw new Error('La skill cambió en otra ventana. Conserva tu texto y recarga antes de continuar.')
    update(data)
    setDraft(current => current ? { ...data.configuracion, skills: current.skills } : data.configuracion)
    return data
  }

  function validate() {
    if (!draft) return
    void action('Validando skill…', async signal => {
      setInspection(null)
      const data = await fresh(signal)
      setInspection(await bibliotecaAgentes<RevisionConfiguracion>(token, `/${selected}/skills/validar`, 'POST', { skills: draft.skills, revision: data.revision }, signal))
      setMessage('Validación terminada. Revisa si hay permisos o información pendientes antes de guardar.')
    })
  }

  function saveSkill() {
    if (!folder || !draft || !inspection?.puede_guardar) return
    void action('Guardando skill…', async signal => {
      const data = await bibliotecaAgentes<CarpetaAgente>(token, `/${selected}/skills/guardar`, 'POST', { skills: draft.skills, revision: folder.revision, revision_ia: inspection.revision_ia }, signal)
      update(data); setDraft(data.configuracion); setInspection(null); setProposal(null)
      setMessage('Skill guardada. Los permisos no se modificaron.')
    })
  }

  function updateSkill() {
    if (!draft || !skill || !sources.length) return
    void action('Analizando archivos y proponiendo la skill…', async signal => {
      setInspection(null)
      const data = await fresh(signal)
      const result = await bibliotecaAgentes<PropuestaSkill>(token, `/${selected}/skills/actualizar`, 'POST', { skills: draft.skills, archivo_skill: skillFile, documentos: sources, revision: data.revision }, signal)
      setDraft(current => current ? { ...current, skills: current.skills.map(item => item.archivo === result.archivo_skill ? { ...item, contenido: result.contenido } : item) } : current)
      setProposal(result); setMessage('Propuesta de skill preparada. Puedes editarla; después debes validarla y guardarla.')
    })
  }

  function savePermissions() {
    if (!draft || !folder) return
    void action('Guardando permisos…', async signal => {
      const data = await bibliotecaAgentes<CarpetaAgente>(token, `/${selected}/accesos`, 'PUT', { accesos: draft.accesos, revision: folder.revision }, signal)
      update(data); setDraft(data.configuracion); setMessage('Permisos guardados. Las skills y los archivos no se modificaron.')
    })
  }

  function upload(file?: File) {
    if (!file || !folder) return
    if (file.size > 2 * 1024 * 1024) { setError('El archivo debe pesar como máximo 2 MB.'); return }
    void action('Subiendo archivo…', async signal => {
      setInspection(null); setProposal(null)
      const form = new FormData(); form.append('archivo', file); form.append('revision', String(folder.revision))
      const data = await bibliotecaAgentes<CarpetaAgente>(token, `/${selected}/documentos`, 'POST', form, signal)
      update(data); setSources(current => [...new Set([...current, ...data.documentos.filter(row => !folder.documentos.some(old => old.id === row.id)).map(row => row.id)])])
      setMessage('Archivo subido. Ábrelo para verlo y pulsa “Actualizar skill con archivos” cuando quieras analizarlo.')
    })
  }

  function remove(document: DocumentoAgente) {
    if (!folder || !window.confirm(`¿Eliminar «${document.nombre}»?`)) return
    void action('Eliminando archivo…', async signal => {
      setInspection(null); setProposal(null)
      update(await bibliotecaAgentes<CarpetaAgente>(token, `/${selected}/documentos/${document.id}`, 'DELETE', { revision: folder.revision }, signal))
      setSources(current => current.filter(id => id !== document.id)); setPreview(null)
      setMessage('Archivo eliminado. La skill guardada no se modificó.')
    })
  }

  function view(document: DocumentoAgente) {
    void action('Abriendo archivo…', async signal => {
      const [metadata, blob] = await Promise.all([
        bibliotecaAgentes<{ contenido: string }>(token, `/${selected}/documentos/${document.id}`, 'GET', undefined, signal),
        originalDocumentoAgente(token, selected, document.id, signal),
      ])
      if (!signal.aborted) setPreview({ nombre: document.nombre, contenido: metadata.contenido, url: URL.createObjectURL(blob), mime: blob.type, original: Boolean(document.original_disponible) })
    })
  }

  const title = mode === 'mapa' ? 'Mapa de agentes' : mode === 'permisos' ? 'Permisos de agentes' : 'Archivos de agentes'
  return <main className="agent-admin-page">
    <header className="agent-admin-header"><div className="agent-admin-heading-icon">{mode === 'mapa' ? <Network /> : mode === 'permisos' ? <ShieldCheck /> : <FolderOpen />}</div>
      <div><h1>{title}</h1><p>{mode === 'mapa' ? 'Una red de especialistas, conectados por sus tareas y requisitos.' : mode === 'permisos' ? 'Define a qué módulos puede acceder cada especialista.' : 'Edita una skill o actualízala con archivos, valídala y guarda.'}</p></div>
      <Link to="/home/asistente-ia">Ir a la conversación</Link>
    </header>
    {error && <div role="alert" className="agent-admin-error">{error}<button disabled={busy} onClick={() => { if (!dirty || window.confirm('¿Descartar cambios y recargar?')) { if (selected) setReload(value => value + 1); else window.location.reload() } }}>Recargar</button></div>}
    {message && <p role="status" className="agent-admin-success">{message}</p>}
    {busy && <p role="status" className="agent-library-working">{working}</p>}
    {loading ? <p role="status">Cargando agentes…</p> : mode === 'mapa' ? catalog && <div className="assistant-page agent-admin-map"><AgentMap catalog={catalog} onClose={() => navigate('/home/asistente-ia')} /></div> :
      <div className="agent-library-layout"><nav className="agent-folder-list" aria-label="Carpetas de agentes">
        {folders.map(agent => <button key={agent.id} disabled={busy} aria-pressed={selected === agent.id} onClick={() => choose(agent.id)}><FolderOpen size={20} /><span>{agent.nombre}<small>{mode === 'permisos' ? 'Accesos a módulos' : `${agent.documentos.length} archivos`}</small></span></button>)}
      </nav>
      {!folder || !draft ? <p role="status">Cargando carpeta…</p> : <section className="agent-library-content" aria-busy={busy}>
        <header><Bot size={25} /><div><h2>{folder.nombre}</h2><p>{folder.descripcion}</p></div></header>
        {mode === 'permisos' ? <>
          <p className="agent-library-note">Los permisos se asignan solo aquí. Editar o actualizar una skill nunca los cambia. Los permisos del perfil y local siguen siendo obligatorios. Después de guardar permisos, vuelve a validar la skill.</p>
          <section className="agent-access-editor"><h3>Conexiones y permisos</h3>
            {!Object.keys(folder.accesos_disponibles).length ? <p>Este agente usa un flujo dedicado. Sus conexiones se gestionan mediante los especialistas.</p> : <AgentConnections key={selected} draft={draft} setDraft={setDraft} available={folder.accesos_disponibles} busy={busy} />}
            <div className="agent-config-actions"><button disabled={busy || !dirty} onClick={savePermissions}><Save size={18} />Guardar permisos</button></div>
          </section>
        </> : <>
          <div className="agent-skill-workflow" aria-label="Flujo de la skill"><span>1 · Editar o actualizar con archivos</span><span>2 · Validar skill</span><span>3 · Guardar skill</span></div>
          <section className="agent-skill-editors agent-primary-skill"><h3>Skill</h3>
            {draft.skills.length > 1 && <label className="agent-skill-picker">Skill a editar<select value={skillFile} disabled={busy} onChange={event => { setSkillFile(event.target.value); setProposal(null) }}>{draft.skills.map(item => <option key={item.archivo} value={item.archivo}>{item.nombre}</option>)}</select></label>}
            {skill && <><label htmlFor="skill-content">{skill.nombre}</label><textarea id="skill-content" aria-label={`Skill ${skill.nombre}`} rows={14} maxLength={30000} disabled={busy} value={skill.contenido} onChange={event => editSkills(event.target.value)} /><small>{skill.contenido.length} / 30000 · {dirty ? 'Propuesta sin guardar' : 'Skill vigente'}</small></>}
            {proposal && <div className="agent-skill-proposal"><h4>Propuesta del Actualizador de skills</h4><p>{proposal.resumen}</p><small>Fuentes: {proposal.fuentes.join(', ')}</small>{proposal.informacion_faltante.length > 0 && <ul>{proposal.informacion_faltante.map((row, index) => <li key={index}>{row}</li>)}</ul>}<p>Es una propuesta editable. Todavía no está validada ni guardada.</p></div>}
          </section>
          <section className="agent-documents"><header><div><h3>Archivos subidos ({folder.documentos.length})</h3><p>Imágenes PNG/JPG/WebP, PDF, DOCX, TXT, MD, CSV o JSON · 2 MB por archivo.</p></div><button disabled={busy || folder.documentos.length >= 10} onClick={() => uploadInput.current?.click()}><Upload size={17} />Subir archivo</button>
            <input ref={uploadInput} type="file" aria-label="Subir archivo del agente" accept=".txt,.md,.csv,.json,.docx,.pdf,.png,.jpg,.jpeg,.webp" hidden onChange={event => { upload(event.target.files?.[0]); event.target.value = '' }} /></header>
            {!folder.documentos.length ? <div className="agent-documents-empty"><FileText /><p>Este agente no tiene archivos subidos. Pulsa Subir archivo para agregarlos y verlos en esta lista.</p></div> : <ul>{folder.documentos.map(document => <li key={document.id}>
              <input type="checkbox" aria-label={`Usar ${document.nombre} para actualizar skill`} disabled={busy} checked={sources.includes(document.id)} onChange={event => { setSources(current => event.target.checked ? [...current, document.id] : current.filter(id => id !== document.id)); setProposal(null) }} />
              <FileText size={21} /><div><strong>{document.nombre}</strong><small>{document.activo ? 'Referencia guardada' : 'Pendiente de guardar con la skill'}{document.bytes ? ` · ${(document.bytes / 1024).toFixed(0)} KB` : ''}</small></div>
              <button disabled={busy} onClick={() => view(document)}>Ver archivo</button><button className="agent-document-delete" disabled={busy} aria-label={`Eliminar ${document.nombre}`} onClick={() => remove(document)}><Trash2 size={18} /></button>
            </li>)}</ul>}
            <div className="agent-config-actions"><button disabled={busy || !sources.length || !skill} onClick={updateSkill}><Sparkles size={18} />Actualizar skill con archivos</button><small>El Actualizador solo propone texto; no guarda ni modifica permisos.</small></div>
            {preview && <section className="agent-document-preview" aria-label={`Archivo ${preview.nombre}`}><header><h4>{preview.nombre}</h4><a href={preview.url} download={preview.original ? preview.nombre : preview.nombre + '.txt'}><Download size={16} />{preview.original ? 'Descargar original' : 'Descargar texto guardado'}</a><button aria-label="Cerrar archivo" onClick={() => setPreview(null)}><X size={18} /></button></header>
              {preview.mime.startsWith('image/') ? <img src={preview.url} alt={preview.nombre} /> : preview.mime.startsWith('application/pdf') ? <iframe src={preview.url} title={`PDF ${preview.nombre}`} /> : <pre>{preview.contenido}</pre>}
            </section>}
          </section>
          <section ref={validationPanel} className="agent-config-review"><header><ShieldCheck size={24} /><div><h3>Validador de skills</h3><p>Un agente independiente revisa la propuesta. Indica qué permisos o información faltan y para qué; nunca los concede.</p></div></header>
            <div className="agent-config-actions"><button disabled={busy || !skill} onClick={validate}><ScanSearch size={18} />Validar skill</button><button disabled={busy || !inspection?.puede_guardar} onClick={saveSkill}><Save size={18} />Guardar skill</button><Link to={`/home/asistente-ia/permisos?agente=${encodeURIComponent(selected)}`}>Abrir permisos de agentes</Link></div>
            {inspection && <><p className={inspection.puede_guardar ? 'agent-validation-ok' : 'agent-validation-blocked'}>{inspection.puede_guardar ? 'Validación sin bloqueos. Puedes guardar la skill.' : 'Hay pendientes que debes resolver antes de guardar. Ajusta la skill o sus permisos y vuelve a validar.'}</p><ConfigurationReport report={inspection.informe} /></>}
            <small>Si modificas la skill o sus archivos, debes validarla nuevamente. Los permisos se guardan en su propio menú.</small>
          </section>
        </>}
      </section>}
      </div>}
  </main>
}

function ConfigurationReport({ report }: { report: InformeConfiguracion }) {
  const sections = [['Información necesaria', report.informacion_faltante], ['Permisos necesarios y para qué', report.accesos_necesarios], ['Problemas que debes corregir', report.conflictos], ['Sugerencias opcionales', report.recomendaciones]] as const
  return <div className="agent-review-report"><h4>Resultado de la validación</h4><p>{report.resumen}</p>{sections.filter(([, rows]) => rows.length).map(([title, rows]) => <section key={title}><h4>{title}</h4><ul>{rows.map((row, index) => <li key={index}>{row}</li>)}</ul></section>)}</div>
}
