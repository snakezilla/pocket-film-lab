import { type Lut3D, parseLut } from './engine/lut'

export interface Look {
  readonly id: string
  /** Shown to people. Generic names only: no film-stock trademarks in the UI. */
  readonly label: string
  /** The LUT file stem under public/luts (internal). */
  readonly file: string
  readonly size: number
}

/**
 * LUTs built offline by tools/make_lut.py from Spectral Film LUT (MIT).
 * lamplight: Vision3 500T 5219 negative printed on 2383. portrait: Portra 400 on Endura paper.
 */
export const LOOKS: readonly Look[] = [
  { id: 'lamplight', label: 'Lamplight', file: 'print', size: 33 },
  { id: 'portrait', label: 'Portrait', file: 'portra', size: 33 },
]

const cache = new Map<string, Promise<ArrayBuffer>>()

/** Fetch a LUT from this site only (same origin, no third parties). */
export function loadLutBuffer(look: Look): Promise<ArrayBuffer> {
  const hit = cache.get(look.id)
  if (hit) return hit
  const url = new URL(`luts/${look.file}.bin`, document.baseURI)
  const job = fetch(url).then((res) => {
    if (!res.ok) throw new Error(`The ${look.label} look didn’t load. Try again.`)
    return res.arrayBuffer()
  })
  cache.set(look.id, job)
  job.catch(() => cache.delete(look.id))
  return job
}

export function lutFromBuffer(buffer: ArrayBuffer, look: Look): Lut3D {
  return parseLut(buffer, look.size)
}
