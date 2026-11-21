import { useEffect, useState } from 'react'

export function FactApiPreviewPane({ onTarget }: { onTarget: (node: HTMLDivElement | null) => void }) {
  return <aside className="fact-api-preview-pane" aria-label="Visor del comprobante">
    <div className="fact-api-preview-target" ref={onTarget} />
    <p className="fact-api-preview-placeholder">Selecciona PDF A4 o ticket de 80 mm para ver el comprobante.</p>
  </aside>
}

export function FactApiPdfPreview({ url, token, format }: { url: string; token: string; format: string }) {
  const [objectUrl, setObjectUrl] = useState('')
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    const controller = new AbortController()
    let previewUrl: string | undefined
    async function load() {
      try {
        const response = await fetch(url, {
          headers: { Authorization: `Bearer ${token}` },
          signal: controller.signal,
        })
        if (!response.ok || response.headers.get('content-type')?.split(';')[0] !== 'application/pdf') {
          throw new Error('El archivo no es un PDF disponible')
        }
        const pdf = await response.blob()
        if (controller.signal.aborted) return
        previewUrl = URL.createObjectURL(pdf)
        setObjectUrl(previewUrl)
      } catch {
        if (!controller.signal.aborted) setFailed(true)
      }
    }
    void load()
    return () => {
      controller.abort()
      if (previewUrl) URL.revokeObjectURL(previewUrl)
    }
  }, [url, token])

  if (failed) return <p role="alert">No se pudo abrir la vista previa. Puedes intentar descargar el archivo.</p>
  if (!objectUrl) return <p role="status">Abriendo vista previa…</p>
  return <iframe className="fact-api-preview" title={`Vista previa ${format}`} src={objectUrl} />
}
