/** sRGB transfer helpers. 8-bit decode uses a table; encode is exact. */

export const SRGB_TO_LINEAR: Float32Array = (() => {
  const table = new Float32Array(256)
  for (let i = 0; i < 256; i++) table[i] = srgbDecode(i / 255)
  return table
})()

export function srgbDecode(v: number): number {
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

export function srgbEncode(v: number): number {
  if (v <= 0) return 0
  if (v >= 1) return 1
  return v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055
}

export function clamp01(v: number): number {
  return v < 0 ? 0 : v > 1 ? 1 : v
}

/**
 * Soft highlight shoulder in linear light. Values below the knee pass
 * unchanged; values above approach 1 smoothly instead of clipping hard.
 */
export function shoulder(v: number, knee = 0.8): number {
  if (v <= knee) return v
  const room = 1 - knee
  return knee + room * (1 - Math.exp(-(v - knee) / room))
}

/** Rec. 709 luminance from linear RGB. */
export function luminance(r: number, g: number, b: number): number {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

const ENCODE_STEPS = 4096
/** srgbEncode sampled on sqrt(v), which spreads table entries into the shadows. */
const ENCODE_TABLE: Float32Array = (() => {
  const t = new Float32Array(ENCODE_STEPS + 2)
  for (let i = 0; i <= ENCODE_STEPS + 1; i++) {
    const s = Math.min(1, i / ENCODE_STEPS)
    t[i] = srgbEncode(s * s)
  }
  return t
})()

/** Table version of srgbEncode for the pixel loop (error < 0.1 of an 8-bit code). */
export function srgbEncodeFast(v: number): number {
  if (v <= 0) return 0
  if (v >= 1) return 1
  const f = Math.sqrt(v) * ENCODE_STEPS
  const i = f | 0
  const t = f - i
  return ENCODE_TABLE[i] + (ENCODE_TABLE[i + 1] - ENCODE_TABLE[i]) * t
}
