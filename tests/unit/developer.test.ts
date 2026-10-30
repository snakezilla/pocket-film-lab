import { describe, expect, it } from 'vitest'
import { newItem, updateItem, type Batch, type BatchItem } from '../../src/batch'
import { Developer } from '../../src/developer'
import { CancelledError } from '../../src/processor'

/** A host with controllable develop() results and a fake clock. */
function harness(n: number, idleMs = 600) {
  let batch: Batch | null = { epoch: 1, hero: 0, items: Array.from({ length: n }, (_, i) => newItem(`k${i}`, `p${i}`, 'raw')) }
  let version = 0
  let clock = 0
  const calls: string[] = []
  const pending: { key: string; resolve: (p: Partial<BatchItem> | null) => void; reject: (e: Error) => void }[] = []
  const dev = new Developer(
    {
      snapshot: () => ({ batch, version }),
      develop: (item) =>
        new Promise((resolve, reject) => {
          calls.push(item.key)
          pending.push({ key: item.key, resolve, reject })
        }),
      commit: (epoch, key, patch) => {
        if (batch && batch.epoch === epoch) batch = updateItem(batch, key, patch)
      },
    },
    idleMs,
    () => clock,
  )
  const flush = () => new Promise((r) => setTimeout(r, 0))
  return {
    dev,
    calls,
    pending,
    flush,
    get batch() {
      return batch
    },
    setBatch: (b: Batch | null) => (batch = b),
    bump: () => (version += 1),
    tick: (ms: number) => (clock += ms),
    /** Resolves the oldest pending develop and lets the loop continue. */
    async finish(patch: Partial<BatchItem> | null = { filmUrl: 'u' }) {
      pending.shift()?.resolve(patch)
      await flush()
    },
  }
}

describe('Developer', () => {
  it('develops every photo once, one at a time, hero first', async () => {
    const h = harness(3)
    h.dev.kick()
    await h.flush()
    expect(h.calls).toEqual(['k0'])
    expect(h.pending.length).toBe(1)
    await h.finish()
    await h.finish()
    await h.finish()
    expect(h.calls).toEqual(['k0', 'k1', 'k2'])
    expect(h.batch?.items.every((it) => it.state === 'ready' && it.developed === 0)).toBe(true)
    expect(h.dev.busy).toBe(false)
  })

  it('after a settings change only the hero re-develops until the sliders rest', async () => {
    const h = harness(3)
    h.dev.kick()
    for (let i = 0; i < 4; i++) await h.finish()
    h.bump()
    h.dev.touched()
    await h.flush()
    await h.finish()
    expect(h.calls.slice(3)).toEqual(['k0'])
    expect(h.dev.busy).toBe(false)
    h.tick(700)
    h.dev.kick()
    await h.flush()
    await h.finish()
    await h.finish()
    expect(h.calls.slice(3)).toEqual(['k0', 'k1', 'k2'])
  })

  it('a failure marks only that photo, and the rest continue', async () => {
    const h = harness(2)
    h.dev.kick()
    await h.flush()
    h.pending.shift()?.reject(new Error('Could not read'))
    await h.flush()
    await h.finish()
    expect(h.batch?.items.map((it) => it.state)).toEqual(['failed', 'ready'])
    expect(h.batch?.items[0].error).toBe('Could not read')
  })

  it('a result for an old batch is dropped and the new batch develops', async () => {
    const h = harness(1)
    h.dev.kick()
    await h.flush()
    h.setBatch({ epoch: 2, hero: 0, items: [newItem('n0', 'new', 'web')] })
    h.dev.kick() // ignored while busy; the loop picks the new batch up itself
    await h.finish({ filmUrl: 'old' })
    expect(h.calls).toEqual(['k0', 'n0'])
    await h.finish({ filmUrl: 'new' })
    expect(h.batch?.items[0]).toMatchObject({ key: 'n0', filmUrl: 'new', state: 'ready' })
  })

  it('a cancelled render (new pick) is not an error', async () => {
    const h = harness(1)
    h.dev.kick()
    await h.flush()
    h.setBatch({ epoch: 2, hero: 0, items: [newItem('n0', 'new', 'web')] })
    h.pending.shift()?.reject(new CancelledError())
    await h.flush()
    expect(h.calls).toEqual(['k0', 'n0'])
    expect(h.batch?.items[0].state).not.toBe('failed')
  })

  it('a stale reply is retried, but not forever', async () => {
    const h = harness(1)
    h.dev.kick()
    for (let i = 0; i < 3; i++) await h.finish(null)
    expect(h.calls).toEqual(['k0', 'k0', 'k0'])
    expect(h.dev.busy).toBe(false)
  })
})
