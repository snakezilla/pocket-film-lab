import { describe, expect, it } from 'vitest'
import { blurGaussianApprox, downsample, sampleBilinear } from '../../src/engine/blur'

describe('blur helpers', () => {
  it('keeps a constant image constant and preserves the mean of an impulse', () => {
    const flat = new Float32Array(50 * 40).fill(0.3)
    for (const v of blurGaussianApprox(flat, 50, 40, 4)) expect(v).toBeCloseTo(0.3, 5)
    const imp = new Float32Array(61 * 61)
    imp[30 * 61 + 30] = 1
    const out = blurGaussianApprox(imp, 61, 61, 3)
    expect(out.reduce((a, b) => a + b, 0)).toBeCloseTo(1, 4)
    expect(out[30 * 61 + 30]).toBeLessThan(0.1)
  })
  it('downsamples and samples back a constant exactly', () => {
    const src = new Float32Array(30 * 20).fill(0.7)
    const s = downsample(src, 30, 20, 4)
    expect(s.w).toBe(8)
    expect(sampleBilinear(s.data, s.w, s.h, 4, 29, 19)).toBeCloseTo(0.7, 6)
  })
})
