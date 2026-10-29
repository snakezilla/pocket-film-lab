/** 3D LUT with tetrahedral interpolation. Data is RGB triplets, red fastest. */

export interface Lut3D {
  readonly size: number
  readonly data: Float32Array
}

export function parseLut(buffer: ArrayBuffer, size: number): Lut3D {
  const expected = size * size * size * 3
  const raw = new Uint16Array(buffer)
  if (raw.length !== expected) {
    throw new Error(`LUT has ${raw.length} values, expected ${expected}`)
  }
  const data = new Float32Array(expected)
  for (let i = 0; i < expected; i++) data[i] = raw[i] / 65535
  return { size, data }
}

export function identityLut(size: number): Lut3D {
  const data = new Float32Array(size * size * size * 3)
  let o = 0
  for (let b = 0; b < size; b++)
    for (let g = 0; g < size; g++)
      for (let r = 0; r < size; r++) {
        data[o++] = r / (size - 1)
        data[o++] = g / (size - 1)
        data[o++] = b / (size - 1)
      }
  return { size, data }
}

/**
 * Tetrahedral interpolation (same scheme as the MIT Tetrahedral-Interpolation
 * reference by calvinsilly). Inputs are 0..1; writes the result into out[0..2].
 */
export function sampleLut(lut: Lut3D, r: number, g: number, b: number, out: Float32Array): void {
  const n = lut.size - 1
  const d = lut.data
  const fr = clampIndex(r * n, n)
  const fg = clampIndex(g * n, n)
  const fb = clampIndex(b * n, n)
  const r0 = Math.min(fr | 0, n - 1)
  const g0 = Math.min(fg | 0, n - 1)
  const b0 = Math.min(fb | 0, n - 1)
  const dr = fr - r0
  const dg = fg - g0
  const db = fb - b0
  const s = lut.size
  const i000 = ((b0 * s + g0) * s + r0) * 3
  const sr = 3
  const sg = s * 3
  const sb = s * s * 3
  const i111 = i000 + sr + sg + sb
  let ia: number, ib: number, wa: number, wb: number, w0: number, w1: number
  if (dr > dg) {
    if (dg > db) {
      ia = i000 + sr; ib = i000 + sr + sg; w0 = 1 - dr; wa = dr - dg; wb = dg - db; w1 = db
    } else if (dr > db) {
      ia = i000 + sr; ib = i000 + sr + sb; w0 = 1 - dr; wa = dr - db; wb = db - dg; w1 = dg
    } else {
      ia = i000 + sb; ib = i000 + sr + sb; w0 = 1 - db; wa = db - dr; wb = dr - dg; w1 = dg
    }
  } else if (db > dg) {
    ia = i000 + sb; ib = i000 + sg + sb; w0 = 1 - db; wa = db - dg; wb = dg - dr; w1 = dr
  } else if (db > dr) {
    ia = i000 + sg; ib = i000 + sg + sb; w0 = 1 - dg; wa = dg - db; wb = db - dr; w1 = dr
  } else {
    ia = i000 + sg; ib = i000 + sr + sg; w0 = 1 - dg; wa = dg - dr; wb = dr - db; w1 = db
  }
  for (let c = 0; c < 3; c++) {
    out[c] = w0 * d[i000 + c] + wa * d[ia + c] + wb * d[ib + c] + w1 * d[i111 + c]
  }
}

function clampIndex(v: number, n: number): number {
  return v < 0 ? 0 : v > n ? n : v
}
