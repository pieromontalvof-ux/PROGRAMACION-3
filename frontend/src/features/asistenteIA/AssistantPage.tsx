import { useAuth } from '../../context/authState'
import { AssistantWorkspace } from './AssistantWorkspace'
import './AssistantPage.css'

export function AssistantPage() {
  const { token } = useAuth()
  return <AssistantWorkspace key={token ?? 'sin-sesion'} />
}
