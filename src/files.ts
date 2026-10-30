/** File checks that run before any decoding. Pure, so they are unit tested. */
import { COPY } from './copy'

export const MAX_FILE_BYTES = 80 * 1024 * 1024
export const WORK_EDGE = 2400
export const PREVIEW_EDGE = 1280
/** Stay under iOS Safari's per-canvas limit (16,777,216 px). */
export const MAX_CANVAS_PIXELS = 16_000_000

const RAW_EXT = ['dng', 'cr2', 'cr3', 'crw', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'raf', 'orf', 'rw2', 'pef', 'srw', '3fr', 'iiq', 'erf', 'kdc', 'mos', 'mrw', 'x3f', 'raw', 'rwl']
const HEIC_EXT = ['heic', 'heif', 'hif']
const OK_EXT = ['jpg', 'jpeg', 'jfif', 'png']

export type FileCheck =
  | { readonly kind: 'ok' | 'heic' }
  | { readonly kind: 'rejected'; readonly reason: string }

export function checkFile(name: string, type: string, size: number): FileCheck {
  const ext = (name.split('.').pop() ?? '').toLowerCase()
  const mime = type.toLowerCase()
  if (RAW_EXT.includes(ext) || mime.includes('raw') || mime === 'image/x-adobe-dng' || mime === 'image/dng') {
    return { kind: 'rejected', reason: COPY.appOnly }
  }
  if (size === 0) return { kind: 'rejected', reason: COPY.empty }
  if (size > MAX_FILE_BYTES) {
    return { kind: 'rejected', reason: COPY.tooBig(Math.round(size / 1048576), MAX_FILE_BYTES / 1048576) }
  }
  if (HEIC_EXT.includes(ext) || mime === 'image/heic' || mime === 'image/heif') return { kind: 'heic' }
  if (OK_EXT.includes(ext) || mime === 'image/jpeg' || mime === 'image/png') return { kind: 'ok' }
  return { kind: 'rejected', reason: COPY.notAPhoto }
}

export interface Size {
  readonly width: number
  readonly height: number
}

/** Scale to fit maxEdge on the long side; never upscale; at least 1 px. */
export function fitSize(width: number, height: number, maxEdge: number): Size {
  if (!(width > 0 && height > 0)) throw new Error('Image has no pixels')
  const scale = Math.min(1, maxEdge / Math.max(width, height))
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) }
}

/**
 * Halving steps for a high quality downscale. Each step stays under the canvas
 * pixel limit. Returns the sizes to draw through, ending at the target.
 */
export function downscaleSteps(width: number, height: number, target: Size): Size[] {
  const steps: Size[] = []
  let w = width
  let h = height
  while (w > target.width * 2) {
    w = Math.round(w / 2)
    h = Math.round(h / 2)
    if (w * h > MAX_CANVAS_PIXELS) {
      const k = Math.sqrt(MAX_CANVAS_PIXELS / (w * h))
      w = Math.floor(w * k)
      h = Math.floor(h * k)
    }
    steps.push({ width: w, height: h })
  }
  steps.push(target)
  return steps
}

/** film-YYYYMMDD-HHMMSS.jpg; `index` (1-based) tells apart files saved in the same second. */
export function exportName(now: Date, index?: number): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`
  return `film-${stamp}${index === undefined ? '' : `-${pad(index)}`}.jpg`
}
