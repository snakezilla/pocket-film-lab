import { type Lut3D, parseLut } from './engine/lut'

export interface Look {
  readonly id: string
  readonly label: string
  readonly note: string
  readonly size: number
}

/** LUTs built offline by tools/make_lut.py from Spectral Film LUT (MIT). */
export const LOOKS: readonly Look[] = [
  { id: 'print', label: 'Cine print', note: 'Kodak Vision3 500T 5219 negative printed on Kodak 2383', size: 33 },
  { id: 'portra', label: 'Portra', note: 'Kodak Portra 400 negative printed on Portra Endura paper', size: 33 },
]

const cache = new Map<string, Promise<ArrayBuffer>>()

/** Fetch a LUT from this site only (same origin, no third parties). */
export function loadLutBuffer(look: Look): Promise<ArrayBuffer> {
  const hit = cache.get(look.id)
  if (hit) return hit
  const url = new URL(`luts/${look.id}.bin`, document.baseURI)
  const job = fetch(url).then((res) => {
    if (!res.ok) throw new Error(`Could not load the ${look.label} look (HTTP ${res.status})`)
    return res.arrayBuffer()
  })
  cache.set(look.id, job)
  job.catch(() => cache.delete(look.id))
  return job
}

export function lutFromBuffer(buffer: ArrayBuffer, look: Look): Lut3D {
  return parseLut(buffer, look.size)
}
