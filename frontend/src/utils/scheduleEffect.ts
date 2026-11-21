/** Starts request setup after the current commit, and cancels it if React disposes
 * the effect first (including StrictMode's setup/cleanup check). The callback
 * must return its abort/unsubscribe cleanup when it owns external resources.
 */
export function scheduleEffect(start: () => void | (() => void)): () => void {
  let cancelled = false
  let cleanup: void | (() => void)
  queueMicrotask(() => { if (!cancelled) cleanup = start() })
  return () => {
    if (cancelled) return
    cancelled = true
    cleanup?.()
  }
}
