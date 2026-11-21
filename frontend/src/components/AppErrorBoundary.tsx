import { Component, type ReactNode } from 'react'

export class AppErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }

  static getDerivedStateFromError() { return { failed: true } }

  render() {
    if (this.state.failed) return (
      <main role="alert" style={{ padding: '2rem', maxWidth: '42rem', margin: 'auto' }}>
        <h1>No se pudo mostrar esta pantalla</h1>
        <p>Vuelve a intentarlo. Tu sesión se conserva.</p>
        <button type="button" onClick={() => this.setState({ failed: false })}>Volver a intentar</button>
        <button type="button" onClick={() => window.location.reload()}>Recargar aplicación</button>
      </main>
    )
    return this.props.children
  }
}
