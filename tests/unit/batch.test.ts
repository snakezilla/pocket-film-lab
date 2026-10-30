import { describe, expect, it } from 'vitest'
import { newItem, nextToDevelop, pickNote, progress, saveable, statusLine, updateItem, type Batch } from '../../src/batch'
import { saveLabel } from '../../src/view'

const batchOf = (n: number, hero = 0): Batch => ({
  epoch: 1,
  hero,
  items: Array.from({ length: n }, (_, i) => newItem(`k${i}`, `p${i}.dng`, i % 2 ? 'web' : 'raw')),
})

describe('which photo develops next', () => {
  it('the photo on screen first, then the rest in pick order', () => {
    const b = batchOf(3, 1)
    expect(nextToDevelop(b, 0, true)?.key).toBe('k1')
    const b2 = updateItem(b, 'k1', { developed: 0, state: 'ready' })
    expect(nextToDevelop(b2, 0, true)?.key).toBe('k0')
  })

  it('holds the others back while sliders move', () => {
    const b = updateItem(batchOf(3), 'k0', { developed: 0, state: 'ready' })
    expect(nextToDevelop(b, 0, false)).toBeNull()
    expect(nextToDevelop(b, 1, false)?.key).toBe('k0') // the hero is never held back
  })

  it('shows every photo once before redoing old ones', () => {
    let b = batchOf(3)
    b = updateItem(b, 'k0', { developed: 0, state: 'ready' })
    b = updateItem(b, 'k1', { developed: 0, state: 'ready' })
    // Settings changed (version 1): the never-developed k2 goes before stale k1.
    b = updateItem(b, 'k0', { developed: 1 })
    expect(nextToDevelop(b, 1, true)?.key).toBe('k2')
  })

  it('never retries a failed photo', () => {
    const b = updateItem(batchOf(1), 'k0', { state: 'failed', developed: 0 })
    expect(nextToDevelop(b, 5, true)).toBeNull()
  })
})

describe('progress and labels', () => {
  it('counts developed and failed photos', () => {
    let b = batchOf(4)
    b = updateItem(b, 'k0', { developed: 0, state: 'ready' })
    b = updateItem(b, 'k1', { developed: 0, state: 'failed' })
    expect(progress(b)).toEqual({ total: 4, done: 2, failed: 1 })
    expect(saveable(b).map((it) => it.key)).toEqual(['k0', 'k2', 'k3'])
    expect(statusLine(b, 'Daylight')).toBe('Developing 3 of 4…')
  })

  it('a finished batch and a single photo', () => {
    let b = batchOf(3)
    for (const k of ['k0', 'k1', 'k2']) b = updateItem(b, k, { developed: 0, state: 'ready' })
    expect(statusLine(b, 'Daylight')).toBe('3 photos, Daylight look')
    b = updateItem(b, 'k2', { state: 'failed' })
    expect(statusLine(b, 'Daylight')).toBe('2 photos, Daylight look. 1 didn’t work.')
    const one = updateItem(batchOf(1), 'k0', { developed: 0, state: 'ready', width: 4032, height: 3024 })
    expect(statusLine(one, 'Daylight')).toBe('Daylight look')
  })

  it('notes photos left out of a pick', () => {
    expect(pickNote(0, 0)).toBe('')
    expect(pickNote(2, 0)).toBe('2 photos didn’t open.')
    expect(pickNote(0, 1)).toBe('We kept the first 50. 1 more was left out.')
  })

  it('save button labels', () => {
    const idle = { phase: 'idle' } as const
    expect(saveLabel(true, 1, idle, false)).toBe('Save to Photos')
    expect(saveLabel(true, 12, idle, false)).toBe('Save 12 to Photos')
    expect(saveLabel(false, 3, idle, false)).toBe('Download 3')
    expect(saveLabel(true, 12, { phase: 'saving', done: 2, total: 12, stopping: false }, false)).toBe('Saving 3 of 12…')
    expect(saveLabel(true, 1, { phase: 'saving', done: 0, total: 1, stopping: false }, false)).toBe('Saving…')
    expect(saveLabel(true, 12, { phase: 'saving', done: 2, total: 12, stopping: true }, false)).toBe('Stopping…')
    expect(saveLabel(true, 12, { phase: 'done', version: 0, epoch: 1 }, true)).toBe('Saved to Photos')
  })
})
