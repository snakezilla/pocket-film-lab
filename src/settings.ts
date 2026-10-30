import type { Recipe } from './engine/film'
import { LOOKS, type Look } from './looks'
import type { RawSettings } from './native'

/**
 * One set of adjustments for the whole batch. RAW photos go to the native engine,
 * JPEG/PNG/HEIC to the web engine; each gets the part it understands.
 */
export interface Adjustments {
  /** A native look id in the app, a web look id in a browser. */
  readonly look: string
  readonly strength: number
  readonly exposure: number
  readonly grain: number
  readonly halation: number
  readonly softness: number
  readonly warmth: number
  /** Null: each photo keeps its own as-shot white balance (RAW only). */
  readonly wbTemp: number | null
  readonly wbTint: number | null
}

export const DEFAULT_ADJUSTMENTS: Adjustments = {
  look: '',
  strength: 1,
  exposure: 0,
  grain: 0.35,
  halation: 0.3,
  softness: 0,
  warmth: 0,
  wbTemp: null,
  wbTint: null,
}

export type SliderKey = 'strength' | 'exposure' | 'grain' | 'halation' | 'softness' | 'warmth'

export function toRecipe(a: Adjustments): Recipe {
  return { strength: a.strength, exposure: Math.max(-2, Math.min(2, a.exposure)), grain: a.grain, halo: a.halation }
}

export function toRawSettings(a: Adjustments): RawSettings {
  const base = {
    look: a.look,
    strength: a.strength,
    exposure: a.exposure,
    grain: a.grain,
    halation: a.halation,
    softness: a.softness,
    warmth: a.warmth,
  }
  return a.wbTemp !== null && a.wbTint !== null ? { ...base, wbTemp: a.wbTemp, wbTint: a.wbTint } : base
}

/**
 * The web look for a look id. Native looks are negative stocks printed on 2383; the web
 * has two (a 500T cine print and Portra), so the portrait look maps to the web portrait
 * look and both Vision3 stocks to lamplight.
 */
const WEB_FOR_NATIVE: Readonly<Record<string, string>> = {
  'vision3-250d-2383': 'lamplight',
  'vision3-500t-2383': 'lamplight',
  'portra400-2383': 'portrait',
}

export function webLookFor(look: string): Look {
  const id = WEB_FOR_NATIVE[look] ?? look
  return LOOKS.find((l) => l.id === id) ?? LOOKS[0]
}

export function formatValue(key: SliderKey, v: number): string {
  if (key === 'exposure') return `${v > 0 ? '+' : v < 0 ? '−' : ''}${Math.abs(v).toFixed(1)}`
  return `${Math.round(v * 100)}%`
}

export function formatTint(v: number): string {
  return `${v > 0 ? '+' : v < 0 ? '−' : ''}${Math.abs(Math.round(v))}`
}
