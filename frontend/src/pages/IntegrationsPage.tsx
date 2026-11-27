import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../context/authState'
import { API_BASE_URL } from '../config'
import './IntegrationsPage.css'

type Solicitud = {
  id: string
  id_local: number
  origen: string
  tipo: 'clientes' | 'proveedores'
  datos: Record<string, unknown>
  estado: 'PENDIENTE' | 'ERROR' | 'AGREGADO' | 'DESCARTADO'
  recibido_en: string
  revisado_por: number | null
  revisado_en: string | null
  id_registro: string | null
  mensaje: string | null
  eventos: { usuario: number; fecha: string; estado: Solicitud['estado']; mensaje: string }[]
}
type Tipo = Solicitud['tipo']
type ClaveAPI = {
  id: string
  nombre: string
  id_local: number
  creado_en: string
  permiso: Tipo | 'ambos' | 'leer_clientes'
  vence_en: string | null
  revocado_en: string | null
}
type Conteo = { recibidos: number; nuevos: number; repetidos: number; invalidos: number }
const estadosConsulta = {
  EN_COLA: 'En cola o procesando', REINTENTO: 'Reintento programado',
  RESPONDIO: 'Respondida', FALLIDA: 'Fallida',
}
type Historial = {
  consultas: {
    id: string
    host: string
    usuario: number
    fecha: string
    codigo: number
    estado: keyof typeof estadosConsulta
    intentos: number
    reintentar_en: string | null
    mensaje: string | null
    resumen: Partial<Record<Tipo, Conteo>> | null
    errores: { tipo: Tipo; fila: number; mensaje: string }[]
    tiene_siguiente: boolean
    registros: Partial<Record<Solicitud['estado'], number>>
  }[]
  hay_mas: boolean
}
const tipos = { clientes: 'Clientes', proveedores: 'Proveedores' } as const
type Bandeja = {
  solicitudes: Solicitud[]
  categorias: { id_categoria: number; nombre: string }[]
  hay_mas: boolean
}
const estados = {
  PENDIENTE: 'Pendiente',
  ERROR: 'Con errores',
  AGREGADO: 'Agregado',
  DESCARTADO: 'Descartado',
  TODOS: 'Todos',
}

export function IntegrationsPage() {
  const { token, localActivo } = useAuth()
  const { seccion: ruta } = useParams()
  const seccion = ruta === 'consulta' || ruta === 'bandeja' || ruta === 'historial' ? ruta : 'claves'
  const seguimiento = seccion === 'bandeja' || seccion === 'historial'
  const [actualizacion, setActualizacion] = useState(0)
  const [formularioClave, setFormularioClave] = useState(false)
  const [nombreClave, setNombreClave] = useState('')
  const [permiso, setPermiso] = useState<ClaveAPI['permiso']>('leer_clientes')
  const [vigencia, setVigencia] = useState('30')
  const [historial, setHistorial] = useState<Historial | null>(null)
  const [paginaHistorial, setPaginaHistorial] = useState(1)
  const [errorHistorial, setErrorHistorial] = useState('')
  const [filtro, setFiltro] = useState<keyof typeof estados>('PENDIENTE')
  const [tipo, setTipo] = useState<Tipo>('clientes')
  const [url, setUrl] = useState('')
  const [claveExterna, setClaveExterna] = useState('')
  const [tipoConsulta, setTipoConsulta] = useState<Tipo | ''>('')
  const [seleccion, setSeleccion] = useState<string[]>([])
  const [mostrarClave, setMostrarClave] = useState(false)
  const [identificadorVisible, setIdentificadorVisible] = useState<string | null>(null)
  const [claveGenerada, setClaveGenerada] = useState<(ClaveAPI & { clave: string }) | null>(null)
  const [claves, setClaves] = useState<ClaveAPI[]>([])
  const [revisionClaves, setRevisionClaves] = useState(0)
  const [errorClaves, setErrorClaves] = useState('')
  const [pagina, setPagina] = useState(1)
  const [version, setVersion] = useState(0)
  const [bandeja, setBandeja] = useState<Bandeja | null>(null)
  const [categorias, setCategorias] = useState<Record<string, number[]>>({})
  const [ocupado, setOcupado] = useState<string | null>(null)
  const [aviso, setAviso] = useState('')
  const [error, setError] = useState('')
  const clavePropia = claveGenerada?.id_local === localActivo?.id_local ? claveGenerada?.clave : undefined
  const base = API_BASE_URL.replace(/\/$/, '') + '/v1/integraciones'
  const urlLectura = new URL(`${base}/salida/clientes`, window.location.origin).href

  useEffect(() => {
    if (!seguimiento) return
    const timer = window.setInterval(() => setActualizacion(valor => valor + 1), 5000)
    return () => window.clearInterval(timer)
  }, [seguimiento])

  useEffect(() => {
    if (!token || (seccion !== 'bandeja' && seccion !== 'historial')) return
    const control = new AbortController()
    fetch(`${base}/bandeja?estado=${seccion === 'historial' ? 'TODOS' : filtro}&pagina=${pagina}&tipo=${tipo}`, {
      headers: { Authorization: `Bearer ${token}` }, signal: control.signal,
    }).then(async respuesta => {
      const datos = await respuesta.json()
      if (!respuesta.ok) throw new Error(datos.mensaje || 'No se pudo cargar la bandeja.')
      if (!control.signal.aborted) setBandeja(datos)
    }).catch(fallo => {
      if (!control.signal.aborted) setError(String(fallo.message))
    })
    return () => control.abort()
  }, [base, token, filtro, pagina, tipo, version, seccion, actualizacion])

  useEffect(() => {
    if (!token || seccion !== 'claves') return
    const control = new AbortController()
    fetch(`${base}/mi-api/clave`, {
      headers: { Authorization: `Bearer ${token}` }, signal: control.signal, cache: 'no-store',
    }).then(async respuesta => {
      const datos = await respuesta.json()
      if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudieron cargar las claves.')
      if (!control.signal.aborted) {
        setClaves(datos.claves)
        setErrorClaves('')
      }
    }).catch(fallo => {
      if (!control.signal.aborted) setErrorClaves(String(fallo.message))
    })
    return () => control.abort()
  }, [base, revisionClaves, seccion, token])

  useEffect(() => {
    if (!token || !seguimiento) return
    const control = new AbortController()
    setErrorHistorial('')
    fetch(`${base}/historial/consultas?pagina=${paginaHistorial}&activas=${seccion === 'bandeja' ? 1 : 0}`, {
      headers: { Authorization: `Bearer ${token}` }, signal: control.signal,
    }).then(async respuesta => {
      const datos = await respuesta.json()
      if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo cargar el historial.')
      if (!control.signal.aborted) setHistorial(datos)
    }).catch(fallo => {
      if (!control.signal.aborted) setErrorHistorial(String(fallo.message))
    })
    return () => control.abort()
  }, [base, paginaHistorial, seccion, seguimiento, token, version, actualizacion])

  useEffect(() => {
    setPagina(1)
    setPaginaHistorial(1)
    setBandeja(null)
    setHistorial(null)
    setSeleccion([])
    setError('')
    setAviso('')
  }, [seccion])

  async function copiar(valor: string) {
    try {
      await navigator.clipboard.writeText(valor)
      setAviso('Copiado al portapapeles.')
    } catch {
      setError('No se pudo copiar. Selecciona y copia el texto visible.')
    }
  }

  async function generarClave() {
    setErrorClaves('')
    setOcupado('clave')
    try {
      const respuesta = await fetch(`${base}/mi-api/clave`, {
        method: 'POST', cache: 'no-store',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ nombre: nombreClave.trim(), permiso, vigencia_dias: vigencia ? Number(vigencia) : null }),
      })
      const datos = await respuesta.json()
      if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo generar la clave.')
      setMostrarClave(false)
      setClaveGenerada(datos)
      setFormularioClave(false)
      setNombreClave('')
      setPermiso('leer_clientes')
      setVigencia('30')
      setRevisionClaves(vez => vez + 1)
    } catch (fallo) {
      setErrorClaves(String((fallo as Error).message))
    } finally {
      setOcupado(null)
    }
  }

  async function revocarClave(clave: ClaveAPI) {
    if (!window.confirm(`¿Revocar la clave de ${clave.nombre}? Ese programa ya no podrá usarla.`)) return
    setErrorClaves('')
    setOcupado('clave')
    try {
      const respuesta = await fetch(`${base}/mi-api/clave/${clave.id}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${token}` },
      })
      const datos = await respuesta.json()
      if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo revocar la clave.')
      if (claveGenerada?.id === clave.id) setClaveGenerada(null)
      setRevisionClaves(vez => vez + 1)
    } catch (fallo) {
      setErrorClaves(String((fallo as Error).message))
    } finally {
      setOcupado(null)
    }
  }

  async function solicitar(anterior?: string) {
    setOcupado('consulta')
    setError('')
    setAviso('')
    try {
      const respuesta = await fetch(`${base}/consultar`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(anterior ? { anterior } : { url: url.trim(), clave: claveExterna.trim(), tipo: tipoConsulta || undefined }),
      })
      const datos = await respuesta.json()
      if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo consultar la API externa.')
      if (!anterior) setClaveExterna('')
      setAviso('Solicitud puesta en cola. Puedes seguir trabajando y revisar su estado en la bandeja.')
      setVersion(value => value + 1)
    } catch (fallo) {
      setError(String((fallo as Error).message))
    } finally {
      setOcupado(null)
    }
  }

  async function enviarDecision(item: Solicitud, accion: 'agregar' | 'descartar') {
    const respuesta = await fetch(`${base}/bandeja/${item.id}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ accion, ids_categorias: categorias[item.id] }),
    })
    const resultado = await respuesta.json()
    if (!respuesta.ok || resultado.estado === 'ERROR') {
      throw new Error(resultado.mensaje ?? 'No se pudo revisar la solicitud.')
    }
  }

  async function revisar(items: Solicitud[], accion: 'agregar' | 'descartar') {
    setOcupado('revision')
    setError('')
    setAviso('')
    const fallos: string[] = []
    let completados = 0
    try {
      for (const item of items) {
        try {
          await enviarDecision(item, accion)
          completados += 1
        } catch (fallo) {
          const nombre = typeof item.datos.nombre === 'string' ? item.datos.nombre : item.id
          fallos.push(`${nombre}: ${(fallo as Error).message}`)
        }
      }
      if (completados) setAviso(`${completados} ${accion === 'agregar' ? 'agregados al catálogo' : 'descartados'}.`)
      if (fallos.length) setError(fallos.join('\n'))
      setSeleccion([])
      setVersion(value => value + 1)
    } finally {
      setOcupado(null)
    }
  }

  function cambiarPagina(nueva: number) {
    setError('')
    setBandeja(null)
    setSeleccion([])
    setPagina(nueva)
  }

  const seleccionados = (bandeja?.solicitudes ?? []).filter(item =>
    seleccion.includes(item.id) && (item.estado === 'PENDIENTE' || item.estado === 'ERROR'))
  const faltanCategorias = seleccionados.some(item => item.tipo === 'proveedores' && !categorias[item.id]?.length)

  return <section className="integration-inbox">
    <header>
      <div><h1>Integraciones API</h1><p>Revisa los clientes y proveedores recibidos antes de agregarlos.</p></div>
      <button type="button" onClick={() => { setError(''); setVersion(value => value + 1); setRevisionClaves(value => value + 1) }}>Actualizar</button>
    </header>
    <div className="integration-panels" hidden={seccion !== 'claves' && seccion !== 'consulta'}>
      <section className="integration-help" hidden={seccion !== 'claves'} aria-labelledby="mis-endpoints">
        <h2 id="mis-endpoints">Nuestra API</h2>
        <div className="integration-copy">
          <label>URL para compartir clientes<input readOnly value={urlLectura} /></label>
          <button type="button" onClick={() => void copiar(urlLectura)}>Copiar URL</button>
        </div>
      </section>
      <form className="integration-help" hidden={seccion !== 'consulta'} autoComplete="off" onSubmit={e => { e.preventDefault(); void solicitar() }}>
        <h2>Consultar otra API</h2>
        <label>URL del otro programa<input type="text" inputMode="url" autoComplete="off" required value={url}
          onChange={e => { setUrl(e.target.value); setClaveExterna('') }} placeholder="https://sistema.example/api/directorio" /></label>
        <label>Clave de la API externa (opcional)
          <input type="password" autoComplete="new-password" value={claveExterna} maxLength={2048}
            onChange={e => setClaveExterna(e.target.value)} />
          <small>Pega la clave que te dio el otro programa, sin escribir Bearer.</small>
        </label>
        <details><summary>Opciones de la consulta</summary>
          <label>Si la API devuelve una lista sin identificar <select value={tipoConsulta} onChange={e => setTipoConsulta(e.target.value as Tipo | '')}>
            <option value="">Detectar automáticamente</option><option value="clientes">La lista contiene clientes</option><option value="proveedores">La lista contiene proveedores</option>
          </select></label>
        </details>
        <button className="integration-primary" type="submit" disabled={ocupado !== null}>
          {ocupado === 'consulta' ? 'Solicitando...' : 'Solicitar datos'}
        </button>
      </form>
    </div>
    <section className="integration-help integration-keys" hidden={seccion !== 'claves'} aria-labelledby="claves-local">
      <div className="integration-toolbar">
        <h2 id="claves-local">Claves de Barbarito</h2>
        <button className="integration-primary" type="button" disabled={ocupado !== null || !localActivo}
          onClick={() => { setErrorClaves(''); setFormularioClave(true) }} aria-expanded={formularioClave}>Generar nueva clave</button>
      </div>
      {formularioClave && <form className="integration-help integration-create-key" onSubmit={evento => {
        evento.preventDefault()
        if (nombreClave.trim() && ocupado === null) void generarClave()
      }}>
        <h2>Nueva clave de Barbarito</h2>
        <label>Nombre<input value={nombreClave} onChange={evento => setNombreClave(evento.target.value)} maxLength={80} required /></label>
        <label>Permiso<select value={permiso} onChange={evento => setPermiso(evento.target.value as ClaveAPI['permiso'])}>
          <option value="leer_clientes">Leer clientes</option>
          <option value="ambos">Recibir clientes y proveedores</option>
          <option value="clientes">Recibir solo clientes</option>
          <option value="proveedores">Recibir solo proveedores</option>
        </select></label>
        <label>Caducidad<select value={vigencia} onChange={evento => setVigencia(evento.target.value)}>
          <option value="7">7 días</option><option value="30">30 días</option>
          <option value="90">90 días</option><option value="365">365 días</option>
          <option value="">Sin caducidad</option>
        </select></label>
        <div className="integration-actions">
          <button type="button" disabled={ocupado !== null} onClick={() => { setFormularioClave(false); setErrorClaves('') }}>Cancelar</button>
          <button className="integration-primary" type="submit" disabled={ocupado !== null || !nombreClave.trim()}>Crear clave</button>
        </div>
      </form>}
        {clavePropia && <div className="integration-copy">
          <label>Nueva clave de Barbarito<input type={mostrarClave ? 'text' : 'password'}
            readOnly value={clavePropia} autoComplete="off" /></label>
          <button type="button" onClick={() => setMostrarClave(valor => !valor)}>{mostrarClave ? 'Ocultar' : 'Mostrar'}</button>
          <button type="button" onClick={() => void copiar(clavePropia)}>Copiar clave</button>
        </div>}
      {errorClaves && <p role="alert">{errorClaves}</p>}
      {claves.length > 0 && <div className="integration-table-scroll" tabIndex={0} role="region" aria-labelledby="claves-local">
        <table aria-labelledby="claves-local">
          <thead><tr>
            <th scope="col">Nombre</th><th scope="col">Estado</th>
            <th scope="col">Identificador</th><th scope="col">Permiso</th><th scope="col">Caducidad</th><th scope="col">Creada</th><th scope="col">Acciones</th>
          </tr></thead>
          <tbody>{claves.map(clave => <tr key={clave.id}>
            <th scope="row">{clave.nombre}</th>
            <td><span className="integration-key-status" data-revoked={Boolean(clave.revocado_en)}>
              {clave.revocado_en ? 'Revocada' : clave.vence_en && Date.parse(clave.vence_en) <= Date.now() ? 'Vencida' : 'Activa'}
            </span></td>
            <td>
              <div className="integration-identifier">
                <code>{identificadorVisible === clave.id ? clave.id : `${clave.id.slice(0, 8)}...`}</code>
                <button type="button" aria-expanded={identificadorVisible === clave.id}
                  aria-label={`${identificadorVisible === clave.id ? 'Ocultar' : 'Mostrar'} identificador de ${clave.nombre}`}
                  onClick={() => setIdentificadorVisible(visible => visible === clave.id ? null : clave.id)}>
                  {identificadorVisible === clave.id ? 'Ocultar' : 'Mostrar'}
                </button>
              </div>
            </td>
            <td>{clave.permiso === 'leer_clientes' ? 'Leer clientes' : clave.permiso === 'ambos' ? 'Recibir clientes y proveedores' : `Recibir ${tipos[clave.permiso].toLowerCase()}`}</td>
            <td>{clave.vence_en ? new Date(clave.vence_en).toLocaleString('es-PE') : 'Sin caducidad'}</td>
            <td>{new Date(clave.creado_en).toLocaleDateString('es-PE')}</td>
            <td>{!clave.revocado_en && <button type="button" disabled={ocupado !== null}
              onClick={() => void revocarClave(clave)} aria-label={`Revocar clave de ${clave.nombre}`}>Revocar</button>}</td>
          </tr>)}</tbody>
        </table>
      </div>}
      {claves.length === 0 && !errorClaves && <p>No hay claves registradas.</p>}
    </section>
    {seccion === 'consulta' && aviso && <Link to="/home/integraciones/bandeja">Ir a la bandeja de solicitudes</Link>}
    {seguimiento && <section className="integration-help integration-keys" aria-label="Consultas externas">
      <h2>{seccion === 'bandeja' ? 'Consultas en curso' : 'Historial de consultas externas'}</h2>
      {errorHistorial && <p role="alert">{errorHistorial}</p>}
      {!historial && !errorHistorial && <p role="status">Cargando consultas...</p>}
      {historial?.consultas.length === 0 && <p>{seccion === 'bandeja' ? 'No hay consultas en curso.' : 'No hay consultas registradas.'}</p>}
      {historial && historial.consultas.length > 0 && <div className="integration-table-scroll" tabIndex={0}>
        <table>
          <thead><tr><th scope="col">Fecha</th><th scope="col">Origen</th><th scope="col">Usuario</th><th scope="col">Resultado</th></tr></thead>
          <tbody>{historial.consultas.map(item => <tr key={item.id}>
            <td>{new Date(item.fecha).toLocaleString('es-PE')}</td><td>{item.host || 'Sin dominio'}</td><td>{item.usuario}</td>
            <td><strong>{estadosConsulta[item.estado]}</strong>
              {item.codigo > 0 && <span> &middot; HTTP {item.codigo}</span>}
              {item.intentos > 0 && <p>Intentos {item.intentos}</p>}
              {item.reintentar_en && <p>Próximo intento {new Date(item.reintentar_en).toLocaleString('es-PE')}</p>}
              {item.mensaje && <p>{item.mensaje}</p>}
              {Object.entries(item.resumen ?? {}).map(([clave, dato]) => <p key={clave}>
                {tipos[clave as Tipo]} · {dato.nuevos} nuevos · {dato.repetidos} repetidos · {dato.invalidos} inválidos
              </p>)}
              {Object.entries(item.registros).map(([estado, cantidad]) => <p key={estado}>
                {estados[estado as Solicitud['estado']]} &middot; {cantidad}
              </p>)}
              {item.errores.length > 0 && <details>
                <summary>Ver filas inválidas</summary>
                <ul className="integration-error-list">{item.errores.map(fallo =>
                  <li key={`${fallo.tipo}-${fallo.fila}`}>{tipos[fallo.tipo]}, fila {fallo.fila}. {fallo.mensaje}</li>
                )}</ul>
              </details>}
              {item.tiene_siguiente && <button type="button" disabled={ocupado !== null}
                onClick={() => void solicitar(item.id)}>Solicitar siguiente página</button>}
            </td>
          </tr>)}</tbody>
        </table>
      </div>}
      {(paginaHistorial > 1 || historial?.hay_mas) && <nav aria-label="Paginación de consultas">
        <button type="button" disabled={paginaHistorial === 1} onClick={() => setPaginaHistorial(valor => valor - 1)}>Anterior</button>
        <span>Página {paginaHistorial}</span>
        <button type="button" disabled={!historial?.hay_mas} onClick={() => setPaginaHistorial(valor => valor + 1)}>Siguiente</button>
      </nav>}
    </section>}
    {error && <p role="alert">{error}</p>}
    {aviso && <p role="status">{aviso}</p>}
    {(seccion === 'bandeja' || seccion === 'historial') && <>
    <h2>{seccion === 'historial' ? 'Registros recibidos' : 'Bandeja de revisión'}</h2>
    <div className="integration-toolbar">
      <div className="integration-tabs" aria-label="Tipo de registro">
        {(Object.keys(tipos) as Tipo[]).map(nombre => <button type="button" key={nombre} aria-pressed={tipo === nombre}
          onClick={() => { if (tipo !== nombre) { cambiarPagina(1); setTipo(nombre) } }}>{tipos[nombre]}</button>)}
      </div>
    {seccion === 'bandeja' && <label>Estado <select value={filtro} onChange={e => {
      cambiarPagina(1)
      setFiltro(e.target.value as keyof typeof estados)
    }}>{Object.entries(estados).map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}</select></label>}
      {seccion === 'bandeja' && <button className="integration-primary" type="button" disabled={ocupado !== null || !seleccionados.length || faltanCategorias}
        onClick={() => void revisar(seleccionados, 'agregar')}>Agregar seleccionados ({seleccionados.length})</button>}
    </div>
    {faltanCategorias && <p>Elige categorías para cada proveedor seleccionado.</p>}
    {!bandeja && !error && <p role="status">Cargando solicitudes...</p>}
    {bandeja?.solicitudes.length === 0 && <p>No hay solicitudes con este estado.</p>}
    <div className="integration-items">{bandeja?.solicitudes.map(item => {
      const comercial = item.datos.datos_comerciales as Record<string, unknown> | undefined
      const documento = item.datos.numero_documento ?? comercial?.ruc
      const editable = seccion === 'bandeja' && (item.estado === 'PENDIENTE' || item.estado === 'ERROR')
      const requiereCategoria = item.tipo === 'proveedores' && !categorias[item.id]?.length
      return <article key={item.id}>
        <div className="integration-heading">
          <div><h2>{typeof item.datos.nombre === 'string' && item.datos.nombre ? item.datos.nombre : 'Sin nombre'}</h2>
            <p>{item.tipo === 'clientes' ? 'Cliente' : 'Proveedor'} · {item.origen} · Local {item.id_local}</p>
          </div>
          <span>{estados[item.estado]}</span>
          {editable && <label className="integration-select-item">
            <input type="checkbox" checked={seleccion.includes(item.id)} disabled={ocupado !== null}
              onChange={e => {
                const marcado = e.target.checked
                setSeleccion(ids => marcado ? [...ids, item.id] : ids.filter(id => id !== item.id))
              }} />Seleccionar
          </label>}
        </div>
        <p>{documento ? `Documento ${String(documento)}` : 'Sin documento'} · {new Date(item.recibido_en).toLocaleString('es-PE')}</p>
        {item.mensaje && <p>{item.mensaje}</p>}
        {item.id_registro && <p>Registro incorporado <code>{item.id_registro}</code></p>}
        {item.revisado_en && <p>Revisado por usuario {item.revisado_por} el {new Date(item.revisado_en).toLocaleString('es-PE')}</p>}
        <details><summary>Ver datos y seguimiento</summary>
          <p><code>{item.id}</code></p>
          {Boolean(item.datos.acadesys) && <p>Alumno en AcadeSys <code>{String((item.datos.acadesys as { idCliente: string }).idCliente)}</code></p>}
          <dl>{Object.entries({ ...item.datos, ...comercial }).filter(([campo, valor]) =>
            campo !== 'datos_comerciales' && typeof valor === 'string' && valor.trim()
          ).map(([campo, valor]) => <div key={campo}>
            <dt>{campo.replaceAll('_', ' ')}</dt><dd>{String(valor)}</dd>
          </div>)}</dl>
          <details><summary>Ver JSON</summary><pre>{JSON.stringify(item.datos, null, 2)}</pre></details>
          {item.eventos.length > 0 && <ul aria-label="Historial de revisión">{item.eventos.map((evento, indice) =>
            <li key={indice}>{new Date(evento.fecha).toLocaleString('es-PE')} &middot; Usuario {evento.usuario} &middot; {estados[evento.estado]} &middot; {evento.mensaje}</li>
          )}</ul>}
        </details>
        {editable && <>
          {item.tipo === 'proveedores' && <fieldset><legend>Categorías para agregar al proveedor</legend>
            {bandeja.categorias.length === 0 && <p>Primero crea una categoría activa en Productos.</p>}
            {bandeja.categorias.map(c => <label key={c.id_categoria}>
              <input type="checkbox" checked={categorias[item.id]?.includes(c.id_categoria) ?? false}
                onChange={e => {
                  const checked = e.target.checked
                  setCategorias(valor => ({ ...valor, [item.id]: checked
                    ? [...(valor[item.id] ?? []), c.id_categoria]
                    : (valor[item.id] ?? []).filter(id => id !== c.id_categoria) }))
                }} />{c.nombre}
            </label>)}
          </fieldset>}
          <div className="integration-actions">
            <button type="button" disabled={ocupado !== null || requiereCategoria} onClick={() => void revisar([item], 'agregar')}>Agregar al catálogo</button>
            <button type="button" disabled={ocupado !== null} onClick={() => void revisar([item], 'descartar')}>Descartar</button>
          </div>
        </>}
      </article>
    })}</div>
    {bandeja && (pagina > 1 || bandeja.hay_mas) && <nav aria-label="Páginas de solicitudes">
      <button type="button" disabled={pagina === 1} onClick={() => cambiarPagina(pagina - 1)}>Anterior</button>
      <span>Página {pagina}</span>
      <button type="button" disabled={!bandeja.hay_mas} onClick={() => cambiarPagina(pagina + 1)}>Siguiente</button>
    </nav>}
    </>}
  </section>
}
