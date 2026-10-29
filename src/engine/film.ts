/**
 * Film-style rendering of already-decoded 8-bit sRGB pixels.
 *
 * Order (per pixel): sRGB -> linear, exposure, red-weighted halation from
 * blurred highlights, soft shoulder, sRGB encode, film LUT, mix with the
 * plain exposed pixel by strength, luminance-weighted grain. This is NOT a RAW pipeline and NOT Chromagraph's
 * or Yedlin's transform; the LUT is a datasheet-based negative + print
 * simulation from Spectral Film LUT (MIT).
 */
import { blurGaussianApprox, downsample, sampleBilinear } from './blur'
import { SRGB_TO_LINEAR, clamp01, luminance, shoulder, srgbEncodeFast } from './color'
import { type Lut3D, sampleLut } from './lut'

export interface Recipe {
  /** 0..1 mix of the film LUT over the neutral render. */
  readonly strength: number
  /** 0..1 grain amount. */
  readonly grain: number
  /** 0..1 halation amount. */
  readonly halo: number
  /** Exposure in stops, -2..2. */
  readonly exposure: number
}

export interface FilmJob {
  readonly pixels: Uint8ClampedArray
  readonly width: number
  readonly height: number
  readonly recipe: Recipe
  readonly lut: Lut3D
  readonly seed?: number
}

export const DEFAULT_RECIPE: Recipe = { strength: 1, grain: 0.35, halo: 0.4, exposure: 0 }

const HALO_THRESHOLD = 0.5 // linear luminance where halation starts (~sRGB 188)
const HALO_GAIN = 0.3
const HALO_COLOR = [1, 0.35, 0.05] as const // red layer spreads most (Raw2Film defaults ~1/0.4/0)
const HALO_RADIUS = 0.008 // fraction of the long edge
const GRAIN_AMPLITUDE = 0.05
const GRAIN_CELLS_ON_LONG_EDGE = 1400 // keeps grain size tied to the frame, not pixels

export function validateRecipe(r: Recipe): Recipe {
  const finite = (v: number, lo: number, hi: number) => (Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : lo)
  return {
    strength: finite(r.strength, 0, 1),
    grain: finite(r.grain, 0, 1),
    halo: finite(r.halo, 0, 1),
    exposure: Number.isFinite(r.exposure) ? Math.min(2, Math.max(-2, r.exposure)) : 0,
  }
}

export function renderFilmPixels(job: FilmJob): Uint8ClampedArray {
  const { pixels, width: w, height: h, lut } = job
  if (pixels.length !== w * h * 4) throw new Error('Pixel buffer does not match image size')
  const recipe = validateRecipe(job.recipe)
  const gain = Math.pow(2, recipe.exposure)
  const halo = recipe.halo > 0 ? haloField(pixels, w, h, gain) : null
  const grain = recipe.grain > 0 ? grainField(w, h, job.seed ?? 87123) : null
  const out = new Uint8ClampedArray(pixels.length)
  const film = new Float32Array(3)
  const lin = new Float32Array(3)
  const base = new Float32Array(3)
  const enc = new Float32Array(3)
  const haloK = recipe.halo * HALO_GAIN
  const grainK = recipe.grain * GRAIN_AMPLITUDE

  for (let y = 0, i = 0; y < h; y++) {
    for (let x = 0; x < w; x++, i += 4) {
      lin[0] = SRGB_TO_LINEAR[pixels[i]] * gain
      lin[1] = SRGB_TO_LINEAR[pixels[i + 1]] * gain
      lin[2] = SRGB_TO_LINEAR[pixels[i + 2]] * gain
      if (halo) {
        const v = sampleBilinear(halo.data, halo.w, halo.h, halo.f, x, y) * haloK
        lin[0] += v * HALO_COLOR[0]
        lin[1] += v * HALO_COLOR[1]
        lin[2] += v * HALO_COLOR[2]
      }
      for (let c = 0; c < 3; c++) {
        base[c] = srgbEncodeFast(lin[c]) // hard clip: strength 0 + exposure 0 is the original
        enc[c] = srgbEncodeFast(shoulder(lin[c])) // film branch rolls highlights off
      }
      sampleLut(lut, enc[0], enc[1], enc[2], film)
      let n = 0
      if (grain) {
        const yl = clamp01(0.2126 * film[0] + 0.7152 * film[1] + 0.0722 * film[2])
        const weight = 0.35 + 0.65 * Math.sin(yl * Math.PI)
        n = sampleBilinear(grain.data, grain.w, grain.h, grain.f, x, y) * grainK * weight
      }
      for (let c = 0; c < 3; c++) {
        const v = base[c] + (film[c] - base[c]) * recipe.strength + n
        out[i + c] = Math.round(clamp01(v) * 255)
      }
      out[i + 3] = 255
    }
  }
  return out
}

interface Field {
  readonly data: Float32Array
  readonly w: number
  readonly h: number
  readonly f: number
}

/** Blurred highlight energy, computed at reduced resolution for speed. */
function haloField(px: Uint8ClampedArray, w: number, h: number, gain: number): Field {
  const long = Math.max(w, h)
  const f = Math.max(1, Math.round(long / 480))
  const mask = new Float32Array(w * h)
  for (let p = 0, i = 0; p < mask.length; p++, i += 4) {
    const y = luminance(SRGB_TO_LINEAR[px[i]], SRGB_TO_LINEAR[px[i + 1]], SRGB_TO_LINEAR[px[i + 2]]) * gain
    const m = (y - HALO_THRESHOLD) / (1 - HALO_THRESHOLD)
    mask[p] = m > 0 ? m * m : 0
  }
  const small = downsample(mask, w, h, f)
  const radius = Math.max(1, (HALO_RADIUS * long) / f)
  return { data: blurGaussianApprox(small.data, small.w, small.h, radius), w: small.w, h: small.h, f }
}

/** Zero-mean, unit-variance noise on a grid scaled to the frame. */
function grainField(w: number, h: number, seed: number): Field {
  const long = Math.max(w, h)
  const f = Math.max(1, long / GRAIN_CELLS_ON_LONG_EDGE)
  const gw = Math.ceil(w / f) + 1
  const gh = Math.ceil(h / f) + 1
  const data = new Float32Array(gw * gh)
  let s = seed >>> 0
  const rand = () => {
    s = (Math.imul(1664525, s) + 1013904223) >>> 0
    return s / 4294967296
  }
  // Sum of 3 uniforms: variance 1/4, so scale by 2 for unit variance.
  for (let i = 0; i < data.length; i++) data[i] = (rand() + rand() + rand() - 1.5) * 2
  return { data, w: gw, h: gh, f }
}
