/** Separable box blur on a single-channel float image; 3 passes ~ Gaussian. */

export function blurGaussianApprox(src: Float32Array, w: number, h: number, radius: number): Float32Array {
  const r = Math.max(0, Math.round(radius))
  if (r === 0) return src.slice()
  const out = src.slice()
  const tmp = new Float32Array(src.length)
  for (let pass = 0; pass < 3; pass++) {
    boxH(out, tmp, w, h, r)
    boxV(tmp, out, w, h, r)
  }
  return out
}

function boxH(src: Float32Array, dst: Float32Array, w: number, h: number, r: number): void {
  const norm = 1 / (2 * r + 1)
  for (let y = 0; y < h; y++) {
    const row = y * w
    let acc = 0
    for (let k = -r; k <= r; k++) acc += src[row + clampI(k, w)]
    for (let x = 0; x < w; x++) {
      dst[row + x] = acc * norm
      acc += src[row + clampI(x + r + 1, w)] - src[row + clampI(x - r, w)]
    }
  }
}

function boxV(src: Float32Array, dst: Float32Array, w: number, h: number, r: number): void {
  const norm = 1 / (2 * r + 1)
  for (let x = 0; x < w; x++) {
    let acc = 0
    for (let k = -r; k <= r; k++) acc += src[clampI(k, h) * w + x]
    for (let y = 0; y < h; y++) {
      dst[y * w + x] = acc * norm
      acc += src[clampI(y + r + 1, h) * w + x] - src[clampI(y - r, h) * w + x]
    }
  }
}

function clampI(i: number, n: number): number {
  return i < 0 ? 0 : i >= n ? n - 1 : i
}

/** Average-downsample by an integer factor (edge cells average what exists). */
export function downsample(src: Float32Array, w: number, h: number, f: number): { data: Float32Array; w: number; h: number } {
  const dw = Math.ceil(w / f)
  const dh = Math.ceil(h / f)
  const sum = new Float32Array(dw * dh)
  const count = new Float32Array(dw * dh)
  for (let y = 0; y < h; y++) {
    const dy = (y / f) | 0
    for (let x = 0; x < w; x++) {
      const i = dy * dw + ((x / f) | 0)
      sum[i] += src[y * w + x]
      count[i] += 1
    }
  }
  for (let i = 0; i < sum.length; i++) sum[i] /= count[i]
  return { data: sum, w: dw, h: dh }
}

/** Bilinear sample of a downsampled image at full-resolution pixel (x, y). */
export function sampleBilinear(src: Float32Array, sw: number, sh: number, f: number, x: number, y: number): number {
  const fx = Math.min(Math.max((x + 0.5) / f - 0.5, 0), sw - 1)
  const fy = Math.min(Math.max((y + 0.5) / f - 0.5, 0), sh - 1)
  const x0 = fx | 0
  const y0 = fy | 0
  const x1 = Math.min(x0 + 1, sw - 1)
  const y1 = Math.min(y0 + 1, sh - 1)
  const tx = fx - x0
  const ty = fy - y0
  const top = src[y0 * sw + x0] * (1 - tx) + src[y0 * sw + x1] * tx
  const bottom = src[y1 * sw + x0] * (1 - tx) + src[y1 * sw + x1] * tx
  return top * (1 - ty) + bottom * ty
}
