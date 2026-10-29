import { describe, expect, it } from 'vitest'
import { SRGB_TO_LINEAR, shoulder, srgbDecode, srgbEncode } from '../../src/engine/color'

describe('sRGB transfer', () => {
  it('round-trips every 8-bit code value', () => {
    for (let i = 0; i < 256; i++) expect(Math.round(srgbEncode(SRGB_TO_LINEAR[i]) * 255)).toBe(i)
  })
  it('maps 0.18 linear to about code 118', () => {
    expect(Math.round(srgbEncode(0.18) * 255)).toBe(118)
    expect(srgbDecode(1)).toBeCloseTo(1, 6)
  })
})

describe('shoulder', () => {
  it('is identity below the knee, monotonic and bounded above it', () => {
    expect(shoulder(0.5)).toBe(0.5)
    let prev = 0
    for (let v = 0; v < 8; v += 0.05) {
      const s = shoulder(v)
      expect(s).toBeGreaterThanOrEqual(prev)
      expect(s).toBeLessThanOrEqual(1)
      prev = s
    }
  })
})

describe('srgbEncodeFast', () => {
  it('matches the exact encoder within 0.1 of an 8-bit code', async () => {
    const { srgbEncodeFast } = await import('../../src/engine/color')
    let worst = 0
    for (let i = 0; i <= 100000; i++) {
      const v = i / 100000
      worst = Math.max(worst, Math.abs(srgbEncodeFast(v) - srgbEncode(v)))
    }
    expect(worst * 255).toBeLessThan(0.1)
    for (let i = 0; i < 256; i++) expect(Math.round(srgbEncodeFast(SRGB_TO_LINEAR[i]) * 255)).toBe(i)
  })
})
