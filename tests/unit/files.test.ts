import { describe, expect, it } from 'vitest'
import { MAX_CANVAS_PIXELS, checkFile, downscaleSteps, exportName, fitSize } from '../../src/files'

describe('checkFile', () => {
  it('accepts JPEG and PNG', () => {
    expect(checkFile('a.JPG', 'image/jpeg', 10).kind).toBe('ok')
    expect(checkFile('a.png', '', 10).kind).toBe('ok')
  })
  it('marks HEIC as conditional', () => {
    expect(checkFile('IMG_1.HEIC', 'image/heic', 10).kind).toBe('heic')
  })
  it('rejects RAW clearly', () => {
    for (const name of ['x.dng', 'x.CR3', 'x.nef', 'x.ARW', 'x.raf']) {
      const r = checkFile(name, '', 10)
      expect(r.kind).toBe('rejected')
      if (r.kind === 'rejected') expect(r.reason).toMatch(/RAW/)
    }
    expect(checkFile('x', 'image/x-adobe-dng', 10).kind).toBe('rejected')
  })
  it('rejects empty, huge and unknown files', () => {
    expect(checkFile('a.jpg', 'image/jpeg', 0).kind).toBe('rejected')
    expect(checkFile('a.jpg', 'image/jpeg', 200 * 1048576).kind).toBe('rejected')
    expect(checkFile('a.gif', 'image/gif', 10).kind).toBe('rejected')
    expect(checkFile('notes.pdf', 'application/pdf', 10).kind).toBe('rejected')
  })
})

describe('sizing', () => {
  it('fits the long edge and never upscales', () => {
    expect(fitSize(4032, 3024, 2400)).toEqual({ width: 2400, height: 1800 })
    expect(fitSize(3024, 4032, 2400)).toEqual({ width: 1800, height: 2400 })
    expect(fitSize(800, 600, 2400)).toEqual({ width: 800, height: 600 })
    expect(() => fitSize(0, 10, 100)).toThrow()
  })
  it('halves down in steps that respect the canvas limit', () => {
    const target = fitSize(12000, 9000, 2400)
    const steps = downscaleSteps(12000, 9000, target)
    expect(steps.at(-1)).toEqual(target)
    for (const s of steps) expect(s.width * s.height).toBeLessThanOrEqual(MAX_CANVAS_PIXELS)
  })
  it('names exports by local time', () => {
    expect(exportName(new Date(2026, 9, 29, 7, 5, 3))).toBe('film-20261029-070503.jpg')
  })
})
