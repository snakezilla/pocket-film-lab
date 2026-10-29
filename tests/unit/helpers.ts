import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { type Lut3D, parseLut } from '../../src/engine/lut'

export function loadLut(id: string): Lut3D {
  const path = fileURLToPath(new URL(`../../public/luts/${id}.bin`, import.meta.url))
  const buf = readFileSync(path)
  return parseLut(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength), 33)
}

/** Solid or callback-generated RGBA image. */
export function makeImage(w: number, h: number, fn: (x: number, y: number) => [number, number, number]): Uint8ClampedArray {
  const px = new Uint8ClampedArray(w * h * 4)
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const [r, g, b] = fn(x, y)
      const i = (y * w + x) * 4
      px[i] = r
      px[i + 1] = g
      px[i + 2] = b
      px[i + 3] = 255
    }
  return px
}

export function stats(values: number[]): { mean: number; std: number } {
  const mean = values.reduce((a, b) => a + b, 0) / values.length
  const std = Math.sqrt(values.reduce((a, b) => a + (b - mean) ** 2, 0) / values.length)
  return { mean, std }
}
