import { describe, expect, it } from 'vitest'
import { renderFilmPixels, validateRecipe, type Recipe } from '../../src/engine/film'
import { loadLut, makeImage, stats } from './helpers'

const lut = loadLut('print')
const OFF: Recipe = { strength: 0, grain: 0, halo: 0, exposure: 0 }
const gradient = makeImage(64, 48, (x, y) => [x * 4, y * 5, (x + y) * 2])

describe('renderFilmPixels', () => {
  it('returns the original pixels when every control is off', () => {
    const out = renderFilmPixels({ pixels: gradient, width: 64, height: 48, recipe: OFF, lut })
    expect(Array.from(out)).toEqual(Array.from(gradient))
  })

  it('does not mutate the input buffer', () => {
    const copy = gradient.slice()
    renderFilmPixels({ pixels: gradient, width: 64, height: 48, recipe: { strength: 1, grain: 1, halo: 1, exposure: 1 }, lut })
    expect(Array.from(gradient)).toEqual(Array.from(copy))
  })

  it('is deterministic for the same seed and differs for another seed', () => {
    const job = { pixels: gradient, width: 64, height: 48, recipe: { strength: 1, grain: 1, halo: 0.5, exposure: 0 }, lut }
    const a = renderFilmPixels(job)
    const b = renderFilmPixels(job)
    const c = renderFilmPixels({ ...job, seed: 1 })
    expect(Array.from(a)).toEqual(Array.from(b))
    expect(Array.from(a)).not.toEqual(Array.from(c))
  })

  it('brightens by about one stop at +1 EV', () => {
    const grey = makeImage(8, 8, () => [100, 100, 100])
    const out = renderFilmPixels({ pixels: grey, width: 8, height: 8, recipe: { ...OFF, exposure: 1 }, lut })
    // 100/255 -> 0.1274 linear -> x2 = 0.2549 -> sRGB 0.5397 -> code 138
    expect(out[0]).toBe(138)
  })

  it('applies the film LUT at full strength', () => {
    const out = renderFilmPixels({ pixels: gradient, width: 64, height: 48, recipe: { ...OFF, strength: 1 }, lut })
    let diff = 0
    for (let i = 0; i < out.length; i++) diff += Math.abs(out[i] - gradient[i])
    expect(diff / out.length).toBeGreaterThan(2)
    for (let i = 3; i < out.length; i += 4) expect(out[i]).toBe(255)
  })

  it('adds red-heavy halation next to highlights and nothing far away', () => {
    const w = 200
    const h = 100
    const px = makeImage(w, h, (x, y) => ((x - 50) ** 2 + (y - 50) ** 2 < 64 ? [255, 255, 255] : [40, 40, 40]))
    const off = renderFilmPixels({ pixels: px, width: w, height: h, recipe: OFF, lut })
    const on = renderFilmPixels({ pixels: px, width: w, height: h, recipe: { ...OFF, halo: 1 }, lut })
    const at = (buf: Uint8ClampedArray, x: number, y: number) => buf.slice((y * w + x) * 4, (y * w + x) * 4 + 3)
    const near = at(on, 60, 50)
    const nearOff = at(off, 60, 50)
    expect(near[0] - nearOff[0]).toBeGreaterThan(8)
    expect(near[0] - nearOff[0]).toBeGreaterThan(2 * (near[2] - nearOff[2]))
    expect(Array.from(at(on, 190, 50))).toEqual(Array.from(at(off, 190, 50)))
  })

  it('adds zero-mean grain that is weaker in deep shadows than in midtones', () => {
    const size = 120
    const sample = (code: number) => {
      const px = makeImage(size, size, () => [code, code, code])
      const ref = renderFilmPixels({ pixels: px, width: size, height: size, recipe: { ...OFF, strength: 1 }, lut })
      const out = renderFilmPixels({ pixels: px, width: size, height: size, recipe: { ...OFF, strength: 1, grain: 1 }, lut })
      const d: number[] = []
      for (let i = 0; i < out.length; i += 4) d.push(out[i + 1] - ref[i + 1])
      return stats(d)
    }
    const mid = sample(118)
    const dark = sample(8)
    expect(Math.abs(mid.mean)).toBeLessThan(0.5)
    expect(mid.std).toBeGreaterThan(5)
    expect(dark.std).toBeLessThan(mid.std)
  })

  it('rejects a buffer that does not match the size', () => {
    expect(() => renderFilmPixels({ pixels: new Uint8ClampedArray(12), width: 2, height: 2, recipe: OFF, lut })).toThrow()
  })
})

describe('validateRecipe', () => {
  it('clamps and replaces non-finite values', () => {
    expect(validateRecipe({ strength: 3, grain: -1, halo: NaN, exposure: 9 })).toEqual({ strength: 1, grain: 0, halo: 0, exposure: 2 })
  })
})
