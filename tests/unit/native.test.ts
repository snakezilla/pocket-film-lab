import { afterEach, describe, expect, it, vi } from 'vitest'
import { nativeRaw } from '../../src/native'

const g = globalThis as unknown as { window?: unknown }

describe('native RAW bridge client', () => {
  afterEach(() => {
    delete g.window
  })

  it('is absent outside the iOS app', () => {
    g.window = {}
    expect(nativeRaw()).toBeNull()
  })

  it('sends commands and unwraps replies', async () => {
    const postMessage = vi.fn(async (body: { cmd: string }) => {
      if (body.cmd === 'looks') return { looks: [{ id: 'vision3-250d-2383', label: '250D Print' }] }
      if (body.cmd === 'open') return { cancelled: true }
      if (body.cmd === 'render') return { url: 'app://local/__raw/p1.jpg', ms: 40 }
      throw new Error('boom')
    })
    g.window = { webkit: { messageHandlers: { raw: { postMessage } } } }
    const bridge = nativeRaw()
    expect(bridge).not.toBeNull()
    expect(await bridge!.looks()).toEqual([{ id: 'vision3-250d-2383', label: '250D Print' }])
    expect(await bridge!.open('photos')).toBeNull()
    const settings = { look: 'vision3-250d-2383', strength: 1, exposure: 0, grain: 0.35, halation: 0.3, softness: 0, wbTemp: 5200, wbTint: 6 }
    expect(await bridge!.render(settings, false, 1600)).toEqual({ url: 'app://local/__raw/p1.jpg', ms: 40 })
    expect(postMessage).toHaveBeenLastCalledWith({ cmd: 'render', settings, compare: false, maxEdge: 1600 })
    await expect(bridge!.exportFile(settings, 'heic')).rejects.toThrow('boom')
  })

  it('tells a RAW apart from a JPEG/PNG fallback', async () => {
    const replies: unknown[] = [
      { name: 'a.dng', width: 4032, height: 3024, wbTemp: 5200, wbTint: 6 },
      { fallback: { url: 'app://local/__raw/p2.png', name: 'b.png' } },
    ]
    const postMessage = vi.fn(async () => replies.shift())
    g.window = { webkit: { messageHandlers: { raw: { postMessage } } } }
    const bridge = nativeRaw()!
    expect(await bridge.open('files')).toEqual({ raw: { name: 'a.dng', width: 4032, height: 3024, wbTemp: 5200, wbTint: 6 } })
    expect(await bridge.open('photos')).toEqual({ photo: { url: 'app://local/__raw/p2.png', name: 'b.png' } })
  })
})
