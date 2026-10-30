import { describe, expect, it } from 'vitest'
import { newItem } from '../../src/batch'
import { SaveStopped, saveAll, saveSummary, type SaveTarget } from '../../src/save'

const items = ['a.dng', 'b.jpg', 'c.dng'].map((name, i) => newItem(`k${i}`, name, 'raw'))

function target(opts: { denied?: boolean; failOn?: string; stopOn?: string } = {}) {
  const log: string[] = []
  let active = 0
  let maxActive = 0
  const t: SaveTarget = {
    prepare: async () => (opts.denied ? 'denied' : 'ok'),
    save: async (item) => {
      active += 1
      maxActive = Math.max(maxActive, active)
      await new Promise((r) => setTimeout(r, 1))
      active -= 1
      if (item.name === opts.failOn) throw new Error('disk full')
      if (item.name === opts.stopOn) throw new SaveStopped()
      log.push(item.name)
    },
  }
  return { t, log, maxActive: () => maxActive }
}

describe('saving a batch', () => {
  it('saves one photo at a time, in order, with progress', async () => {
    const { t, log, maxActive } = target()
    const seen: string[] = []
    const report = await saveAll(items, t, (d, n) => seen.push(`${d}/${n}`), () => false)
    expect(log).toEqual(['a.dng', 'b.jpg', 'c.dng'])
    expect(maxActive()).toBe(1)
    expect(seen).toEqual(['0/3', '1/3', '2/3', '3/3'])
    expect(report).toEqual({ saved: ['k0', 'k1', 'k2'], failed: [], stopped: false, denied: false })
    expect(saveSummary(report, 3, true)).toBe('3 photos saved to your Photos ✓')
    expect(saveSummary({ ...report, saved: ['k0'] }, 1, true)).toBe('Saved to your Photos ✓')
    expect(saveSummary(report, 3, false)).toBe('Downloaded 3 photos.')
  })

  it('keeps going past a failure and reports it', async () => {
    const { t, log } = target({ failOn: 'b.jpg' })
    const report = await saveAll(items, t, () => undefined, () => false)
    expect(log).toEqual(['a.dng', 'c.dng'])
    // A technical error is never shown; people get a friendly line.
    expect(report.failed).toEqual([{ key: 'k1', name: 'b.jpg', error: 'That one didn’t work. Try another photo.' }])
    expect(saveSummary(report, 3, true)).toBe('2 of 3 saved. One didn’t work, so try it again.')
  })

  it('denied permission saves nothing', async () => {
    const { t, log } = target({ denied: true })
    const report = await saveAll(items, t, () => undefined, () => false)
    expect(log).toEqual([])
    expect(report.denied).toBe(true)
    expect(saveSummary(report, 3, true)).toBe('Silver Hour needs your OK to add photos. Turn it on in Settings.')
  })

  it('stops between photos when asked', async () => {
    const { t, log } = target()
    let calls = 0
    const report = await saveAll(items, t, () => undefined, () => ++calls > 1)
    expect(log).toEqual(['a.dng'])
    expect(report.stopped).toBe(true)
    expect(saveSummary(report, 3, true)).toBe('Stopped. 1 of 3 saved.')
  })

  it('a dismissed share sheet stops without an error', async () => {
    const { t } = target({ stopOn: 'a.dng' })
    const report = await saveAll(items, t, () => undefined, () => false)
    expect(report).toMatchObject({ stopped: true, failed: [] })
  })
})
