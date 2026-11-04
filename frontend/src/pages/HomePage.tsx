import { ArrowUpRight, Bot, Boxes, CalendarDays, ClipboardCheck, PackageCheck, Settings2, ShoppingBag } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import './HomePage.css'

const quickModules = [
  { id: 15, icon: Boxes, description: 'Existencias, mínimos y productos por reponer.' },
  { id: 22, icon: ShoppingBag, description: 'Prepara y revisa tus pedidos de compra.' },
  { id: 24, icon: PackageCheck, description: 'Verifica entregas y cantidades pendientes.' },
  { id: 38, icon: ClipboardCheck, description: 'Compara el conteo físico con lo registrado.' },
  { id: 33, icon: Settings2, description: 'Revisa los límites de stock por producto.' },
  { id: 36, icon: CalendarDays, description: 'Consulta y gestiona la jornada de tu tienda.' },
]

export function HomePage() {
  const { usuario, perfilActivo, localActivo, menu } = useAuth()
  const operational = [2, 3, 4].includes(perfilActivo?.id_perfil ?? 0)
  const modules = quickModules.flatMap(module => {
    const option = menu.find(item => item.id_opcion_menu === module.id && item.permisos.consultar && item.url_menu)
    return option && operational ? [{ ...module, name: option.nombre, route: option.url_menu! }] : []
  })
  const catalog = menu.filter(item => [2, 4, 5, 6, 8, 9, 10, 12, 28, 14].includes(item.id_opcion_menu)
    && item.permisos.consultar && item.url_menu)
  const date = new Intl.DateTimeFormat('es-PE', { dateStyle: 'long', timeZone: 'America/Lima' }).format(new Date())
  return <div className="home-page">
    <section className="home-welcome">
      <div><span className="home-welcome__label">TU ESPACIO DE TRABAJO</span>
        <h1>Hola, {usuario?.nombres?.split(' ')[0] || 'bienvenido'}</h1>
        <p>{operational ? `Todo listo para trabajar en ${localActivo?.nombre || 'tu tienda'}.` : 'Gestiona tus catálogos, equipo y configuración desde un mismo lugar.'}</p>
        <div className="home-context"><span>{perfilActivo?.nombre}</span>{localActivo && <span>{localActivo.nombre}</span>}</div>
      </div>
      <div className="home-welcome__date"><CalendarDays aria-hidden="true" /><div><span>HOY · LIMA</span><strong>{date}</strong></div></div>
    </section>
    <section className="home-shortcuts" aria-labelledby="home-shortcuts-title">
      <div className="home-section-heading"><div><span>ACCESOS DIRECTOS</span><h2 id="home-shortcuts-title">¿Por dónde empezamos?</h2></div><p>Las herramientas disponibles para tu perfil.</p></div>
      <div className="home-shortcut-grid">
        <Link to="/home/asistente-ia" className="home-shortcut home-shortcut--assistant">
          <span className="home-shortcut__icon"><Bot aria-hidden="true" /></span><ArrowUpRight className="home-shortcut__arrow" aria-hidden="true" />
          <h3>Barbarito, tu asistente</h3><p>Consulta inventario, compras, recepción o eventos.</p><span className="home-shortcut__action">Abrir asistente</span>
        </Link>
        {modules.map(({ id, icon: Icon, name, route, description }) => <Link to={route} key={id} className="home-shortcut">
          <span className="home-shortcut__icon"><Icon aria-hidden="true" /></span><ArrowUpRight className="home-shortcut__arrow" aria-hidden="true" />
          <h3>{name}</h3><p>{description}</p><span className="home-shortcut__action">Ir al módulo</span>
        </Link>)}
      </div>
    </section>
    {catalog.length > 0 && <section className="home-catalog" aria-labelledby="home-catalog-title">
      <div className="home-section-heading"><div><span>ORGANIZA TU OPERACIÓN</span><h2 id="home-catalog-title">Catálogos y equipo</h2></div></div>
      <div className="home-catalog-links">{catalog.map(option => <Link key={option.id_opcion_menu} to={option.url_menu!}>{option.nombre}<ArrowUpRight size={16} aria-hidden="true" /></Link>)}</div>
    </section>}
    {operational && <p className="home-operational-note"><ClipboardCheck size={18} aria-hidden="true" /> Tú verificas las cantidades en tienda. El sistema te ayuda a comparar y revisar antes de confirmar.</p>}
  </div>
}
