import { expect, it, vi } from 'vitest'
import { scheduleEffect } from './scheduleEffect'

it('cancels startup before its microtask and runs cleanup once after startup', async () => {
  const cleanup = vi.fn()
  const start = vi.fn(() => cleanup)
  const cancel = scheduleEffect(start)
  cancel()
  await Promise.resolve()
  expect(start).not.toHaveBeenCalled()
  const stop = scheduleEffect(start)
  await Promise.resolve()
  expect(start).toHaveBeenCalledTimes(1)
  stop(); stop()
  expect(cleanup).toHaveBeenCalledTimes(1)
})
