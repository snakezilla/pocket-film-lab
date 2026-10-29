import { release } from './decode'
import { stripJpegMetadata } from './jpeg'

export const JPEG_QUALITY = 0.92

/**
 * Encode pixels as JPEG. A canvas has no source EXIF/GPS; some encoders
 * (WebKit) still add generic EXIF/IPTC, so those segments are removed too.
 */
export async function encodeJpeg(image: ImageData): Promise<Blob> {
  const canvas = document.createElement('canvas')
  canvas.width = image.width
  canvas.height = image.height
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('This device ran out of canvas memory while saving.')
  ctx.putImageData(image, 0, 0)
  try {
    const encoded = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('The browser could not encode the JPEG.'))), 'image/jpeg', JPEG_QUALITY)
    })
    const clean = stripJpegMetadata(new Uint8Array(await encoded.arrayBuffer()))
    return new Blob([clean as BlobPart], { type: 'image/jpeg' })
  } finally {
    release(canvas)
  }
}

export type SaveOutcome = 'shared' | 'downloaded' | 'dismissed'

/** Share sheet when the browser supports file sharing (iPhone: Save Image), else a download. */
export async function saveJpeg(blob: Blob, name: string): Promise<SaveOutcome> {
  const file = new File([blob], name, { type: 'image/jpeg' })
  if (typeof navigator.canShare === 'function' && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file] })
      return 'shared'
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return 'dismissed'
      // NotAllowedError etc.: fall through to a plain download.
    }
  }
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  document.body.append(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 30_000)
  return 'downloaded'
}
