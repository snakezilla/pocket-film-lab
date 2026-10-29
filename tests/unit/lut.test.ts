import { describe, expect, it } from 'vitest'
import { identityLut, parseLut, sampleLut } from '../../src/engine/lut'
import { loadLut } from './helpers'

describe('tetrahedral LUT sampling', () => {
  it('reproduces input exactly through an identity LUT', () => {
    const lut = identityLut(17)
    const out = new Float32Array(3)
    for (const [r, g, b] of [[0, 0, 0], [1, 1, 1], [0.3, 0.7, 0.1], [0.99, 0.01, 0.5], [0.5, 0.5, 0.5]]) {
      sampleLut(lut, r, g, b, out)
      expect(out[0]).toBeCloseTo(r, 5)
      expect(out[1]).toBeCloseTo(g, 5)
      expect(out[2]).toBeCloseTo(b, 5)
    }
  })
  it('clamps out-of-range input', () => {
    const out = new Float32Array(3)
    sampleLut(identityLut(5), -1, 2, 0.5, out)
    expect([...out].map((v) => +v.toFixed(5))).toEqual([0, 1, 0.5])
  })
  it('rejects a buffer of the wrong size', () => {
    expect(() => parseLut(new ArrayBuffer(10), 33)).toThrow(/expected/)
  })
})

describe.each(['print', 'portra'])('shipped %s LUT', (id) => {
  const lut = loadLut(id)
  const out = new Float32Array(3)
  it('keeps greys neutral and monotonic', () => {
    let prev = -1
    for (let v = 0.05; v <= 1; v += 0.05) {
      sampleLut(lut, v, v, v, out)
      expect(Math.max(...out) - Math.min(...out)).toBeLessThan(0.02)
      expect(out[1]).toBeGreaterThan(prev)
      prev = out[1]
    }
  })
  it('lifts black slightly and rolls white off below 1', () => {
    sampleLut(lut, 0, 0, 0, out)
    expect(out[1]).toBeGreaterThan(0.01)
    expect(out[1]).toBeLessThan(0.05)
    sampleLut(lut, 1, 1, 1, out)
    expect(out[1]).toBeGreaterThan(0.95)
    expect(out[1]).toBeLessThan(0.99)
  })
  it('changes colour (it is not a tone-only curve)', () => {
    sampleLut(lut, 0.2, 0.45, 0.85, out) // sky blue
    const shift = Math.abs(out[0] - 0.2) + Math.abs(out[1] - 0.45) + Math.abs(out[2] - 0.85)
    expect(shift).toBeGreaterThan(0.05)
  })
})
