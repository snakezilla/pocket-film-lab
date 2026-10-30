import { afterEach, describe, expect, it, vi } from 'vitest'
import { canSaveWith, nativeRaw, toBase64 } from '../../src/native'

const g = globalThis as unknown as { window?: unknown }
const settings = { look: 'vision3-250d-2383', strength: 1, exposure: 0, grain: 0.35, halation: 0.3, softness: 0, warmth: 0 }

function withHandler(postMessage: (body: Record<string, unknown>) => Promise<unknown>) {
  const spy = vi.fn(postMessage)
  g.window = { webkit: { messageHandlers: { raw: { postMessage: spy } } } }
  return { bridge: nativeRaw()!, spy }
}

describe('native bridge client', () => {
  afterEach(() => {
    delete g.window
  })

  it('is absent outside the iOS app', () => {
    g.window = {}
    expect(nativeRaw()).toBeNull()
  })

  it('sends commands with the item id and unwraps replies', async () => {
    const { bridge, spy } = withHandler(async (body) => {
      if (body.cmd === 'looks') return { looks: [{ id: 'vision3-250d-2383', label: '250D Print' }] }
      if (body.cmd === 'render') return { url: 'app://local/__raw/p1.jpg', ms: 40, info: { width: 4032, height: 3024, wbTemp: 5200, wbTint: 6 } }
      if (body.cmd === 'saveAccess') return { access: 'limited' }
      if (body.cmd === 'save' || body.cmd === 'saveData') return { saved: true }
      throw new Error('boom')
    })
    expect(await bridge.looks()).toEqual([{ id: 'vision3-250d-2383', label: '250D Print' }])
    const res = await bridge.render('i1', settings, { compare: false, maxEdge: 1600, hero: true })
    expect(res).toMatchObject({ url: 'app://local/__raw/p1.jpg' })
    expect(spy).toHaveBeenLastCalledWith({ cmd: 'render', id: 'i1', settings, compare: false, maxEdge: 1600, hero: true })
    expect(await bridge.saveAccess()).toBe('limited')
    await bridge.save('i1', settings, 'heic')
    expect(spy).toHaveBeenLastCalledWith({ cmd: 'save', id: 'i1', settings, format: 'heic' })
    await bridge.saveData('film.jpg', new Blob([new Uint8Array([0xff, 0xd8, 0xff])]))
    expect(spy).toHaveBeenLastCalledWith({ cmd: 'saveData', name: 'film.jpg', data: '/9j/' })
    await expect(bridge.exportFile('i1', settings, 'heic')).rejects.toThrow('boom')
  })

  it('returns the picked items, or null for a cancelled or stale pick', async () => {
    const replies: unknown[] = [
      { items: [{ id: 'i1', kind: 'raw', name: 'a.dng' }, { id: 'i2', kind: 'photo', name: 'b.jpg' }], skipped: 1, truncated: 0 },
      { cancelled: true },
      { stale: true },
    ]
    const { bridge } = withHandler(async () => replies.shift())
    expect(await bridge.open('photos')).toEqual({
      items: [{ id: 'i1', kind: 'raw', name: 'a.dng' }, { id: 'i2', kind: 'photo', name: 'b.jpg' }],
      skipped: 1,
      truncated: 0,
    })
    expect(await bridge.open('files')).toBeNull()
    expect(await bridge.open('photos')).toBeNull()
  })

  it('serves a non-RAW source, or null when the batch changed', async () => {
    const replies: unknown[] = [{ url: 'app://local/__raw/s1.jpg', name: 'b.jpg' }, { stale: true }]
    const { bridge } = withHandler(async () => replies.shift())
    expect(await bridge.source('i2')).toEqual({ url: 'app://local/__raw/s1.jpg', name: 'b.jpg' })
    expect(await bridge.source('i2')).toBeNull()
  })
})

describe('helpers', () => {
  it('only authorized or limited access can save', () => {
    expect(canSaveWith('authorized')).toBe(true)
    expect(canSaveWith('limited')).toBe(true)
    expect(canSaveWith('denied')).toBe(false)
    expect(canSaveWith('notDetermined')).toBe(false)
  })

  it('base64-encodes large blobs in chunks', async () => {
    const bytes = new Uint8Array(100_000).map((_, i) => i % 251)
    const b64 = await toBase64(new Blob([bytes]))
    expect(Buffer.from(b64, 'base64').equals(Buffer.from(bytes))).toBe(true)
  })
})
