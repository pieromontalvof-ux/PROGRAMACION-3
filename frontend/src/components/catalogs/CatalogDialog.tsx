import { useEffect, useId, useRef, type FormEvent, type ReactNode } from 'react'
import './CatalogDialog.css'

interface Props {
  titulo: string
  abierto: boolean
  procesando?: boolean
  children: ReactNode
  guardar: () => void | Promise<void>
  cerrar: () => void
  textoGuardar?: string
  error?: string
}

export function CatalogDialog({
  titulo, abierto, procesando = false, children, guardar, cerrar, textoGuardar = 'Guardar', error,
}: Props) {
  const dialog = useRef<HTMLDialogElement>(null)
  const titleId = useId()
  useEffect(() => {
    if (!abierto || !dialog.current) return
    const previousFocus = document.activeElement as HTMLElement | null
    const element = dialog.current
    element.showModal()
    element.querySelector<HTMLElement>('input:not([disabled]), select:not([disabled]), textarea:not([disabled]), button:not([disabled])')?.focus()
    return () => {
      if (element.open) element.close()
      if (previousFocus?.isConnected) previousFocus.focus()
    }
  }, [abierto])
  if (!abierto) return null

  function enviar(evento: FormEvent) {
    evento.preventDefault()
    if (!procesando) void guardar()
  }

  return (
    <dialog ref={dialog} className="catalog-dialog-backdrop" aria-labelledby={titleId}
      onCancel={event => { event.preventDefault(); if (!procesando) cerrar() }}>
      <form className="catalog-dialog" onSubmit={enviar}>
        <h2 id={titleId}>{titulo}</h2>
        {error && <p className="catalog-dialog__error" role="alert">{error}</p>}
        <div className="catalog-dialog__body">{children}</div>
        <footer>
          <button type="button" onClick={cerrar} disabled={procesando}>Cancelar</button>
          <button className="primary" type="submit" disabled={procesando}>
            {procesando ? 'Procesando...' : textoGuardar}
          </button>
        </footer>
      </form>
    </dialog>
  )
}
