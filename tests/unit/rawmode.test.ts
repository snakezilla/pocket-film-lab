import { describe, expect, it, vi } from 'vitest'
import type { NativeRaw, RenderResult } from '../../src/native'
import { RawMode, WB_TEMP_LIMITS, WB_TEMP_RANGE, WB_TINT_LIMITS, WB_TINT_RANGE, rangeIncluding, wbValue } from '../../src/rawmode'

describe('white balance slider range', () => {
  it('keeps the usual range for ordinary as-shot values', () => {
    expect(rangeIncluding(5201, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual(WB_TEMP_RANGE)
    expect(rangeIncluding(6.4, WB_TINT_RANGE, WB_TINT_LIMITS)).toEqual(WB_TINT_RANGE)
  })

  it('widens on the step grid so odd light is not clamped', () => {
    expect(rangeIncluding(1890, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual({ min: 1850, max: 12000, step: 50 })
    expect(rangeIncluding(14_020, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual({ min: 2000, max: 14_050, step: 50 })
    expect(rangeIncluding(-121.5, WB_TINT_RANGE, WB_TINT_LIMITS)).toEqual({ min: -122, max: 100, step: 1 })
  })

  it('ignores values that are not numbers', () => {
    expect(rangeIncluding(Number.NaN, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual(WB_TEMP_RANGE)
  })

  it('never widens past what the native side accepts', () => {
    expect(rangeIncluding(1790, WB_TEMP_RANGE, WB_TEMP_LIMITS).min).toBe(1800)
    expect(rangeIncluding(60_000, WB_TEMP_RANGE, WB_TEMP_LIMITS).max).toBe(50_000)
    expect(rangeIncluding(-170, WB_TINT_RANGE, WB_TINT_LIMITS).min).toBe(-150)
  })
})

describe('white balance value sent to the engine', () => {
  it('sends the exact as-shot value until the slider is moved', () => {
    expect(wbValue(5200, 5201.4, false)).toBe(5201.4)
    expect(wbValue(5600, 5201.4, true)).toBe(5600)
    expect(wbValue(5200, undefined, false)).toBe(5200)
    expect(wbValue(5200, Number.NaN, false)).toBe(5200)
  })
})

describe('RawMode lifecycle', () => {
  const g = globalThis as unknown as { window?: unknown }
  const info = { name: 'a.dng', width: 4032, height: 3024, wbTemp: 5200, wbTint: 6 }
  const settings = () => ({ look: 'x', strength: 1, exposure: 0, grain: 0, halation: 0, softness: 0, warmth: 0, wbTemp: 5200, wbTint: 6 })

  function setup() {
    g.window = { devicePixelRatio: 2 }
    let finish: (v: RenderResult) => void = () => undefined
    const bridge: NativeRaw = {
      looks: async () => [],
      open: vi.fn(async () => ({ raw: info })),
      render: vi.fn(() => new Promise<RenderResult>((resolve) => (finish = resolve))),
      exportFile: vi.fn(async () => ({ shared: true, ms: 1 })),
      clear: vi.fn(async () => undefined),
    }
    const view = { src: '', clientWidth: 400, clientHeight: 300 } as unknown as HTMLImageElement
    const mode = new RawMode(bridge, { view, say: () => undefined })
    return { bridge, view, mode, finish: (v: RenderResult) => finish(v) }
  }

  it('drops a slow render that finishes after close, and clears the native side', async () => {
    const { bridge, view, mode, finish } = setup()
    await mode.open('photos')
    const pending = mode.render(settings, 'L')
    await mode.close()
    finish({ url: 'app://local/__raw/p1.jpg', ms: 900 })
    await pending
    expect(view.src).toBe('')
    expect(bridge.clear).toHaveBeenCalledTimes(1)
    expect(mode.active).toBe(false)
  })

  it('drops a slow render from the previous file when a new file opens', async () => {
    const { view, mode, finish } = setup()
    await mode.open('photos')
    const pending = mode.render(settings, 'L')
    await mode.open('files')
    finish({ url: 'app://local/__raw/p1.jpg', ms: 900 })
    await pending
    expect(view.src).toBe('')
    expect(mode.active).toBe(true)
  })

  it('does not export after close', async () => {
    const { bridge, mode } = setup()
    await mode.open('photos')
    await mode.close()
    await mode.exportFile(settings(), 'heic')
    expect(bridge.exportFile).not.toHaveBeenCalled()
  })

  it('a failed open leaves RAW mode', async () => {
    const { bridge, mode } = setup()
    await mode.open('photos')
    ;(bridge.open as ReturnType<typeof vi.fn>).mockRejectedValueOnce(new Error('broken'))
    await expect(mode.open('files')).rejects.toThrow('broken')
    expect(mode.active).toBe(false)
  })
})
