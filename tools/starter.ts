/**
 * Pixel-only port of the original starter engine, kept only for measurement.
 * Difference from the original: canvas `filter: blur()` is replaced by the
 * same box-blur approximation (canvas filters do not exist in Node).
 */
import { blurGaussianApprox } from '../src/engine/blur'
import type { Recipe } from '../src/engine/film'

export function renderStarterPixels(src: Uint8ClampedArray, w: number, h: number, r: Recipe): Uint8ClampedArray {
  const d = src.slice()
  const mask = new Float32Array(w * h)
  for (let p = 0, i = 0; p < mask.length; p++, i += 4) {
    const lum = (d[i] * 0.2126 + d[i + 1] * 0.7152 + d[i + 2] * 0.0722) / 255
    let v = Math.max(0, (lum - 0.67) / 0.33)
    v = v * v
    mask[p] = (v * 180) / 255
  }
  const halo = blurGaussianApprox(mask, w, h, Math.max(2, w / 210) / 1.7)
  let seed = 87123
  const random = () => ((seed = (1664525 * seed + 1013904223) >>> 0), seed / 4294967296)
  const clamp = (v: number) => Math.max(0, Math.min(1, v))
  const curve = (v: number) => ((v = clamp(v)), 0.022 + 0.956 * (v * v * (3 - 2 * v) * 0.27 + v * 0.73))
  const exposure = Math.pow(2, r.exposure)
  const mix = r.strength
  for (let i = 0, p = 0; i < d.length; i += 4, p++) {
    const a = d[i] / 255, b = d[i + 1] / 255, c = d[i + 2] / 255
    let red = curve(a * exposure), green = curve(b * exposure), blue = curve(c * exposure)
    const lum = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    const shadow = Math.pow(1 - lum, 2), light = lum * lum
    red += 0.018 * light - 0.009 * shadow
    green += 0.005 * shadow
    blue += 0.018 * shadow - 0.025 * light
    const sat = 0.91
    red = lum + (red - lum) * sat
    green = lum + (green - lum) * sat
    blue = lum + (blue - lum) * sat
    const noise = (random() + random() + random() - 1.5) * r.grain * 0.07 * (0.35 + Math.sin(clamp(lum) * Math.PI) * 0.65)
    const alpha = halo[p] * r.halo * 0.34
    d[i] = clamp(a * (1 - mix) + (red + noise + alpha) * mix) * 255
    d[i + 1] = clamp(b * (1 - mix) + (green + noise + alpha * 0.19) * mix) * 255
    d[i + 2] = clamp(c * (1 - mix) + (blue + noise + alpha * 0.07) * mix) * 255
  }
  return d
}
