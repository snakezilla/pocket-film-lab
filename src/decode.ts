import { downscaleSteps, fitSize, WORK_EDGE, PREVIEW_EDGE, type FileCheck } from './files'

export interface DecodedPhoto {
  /** Up to WORK_EDGE on the long side; used for export. */
  readonly work: ImageData
  /** Up to PREVIEW_EDGE on the long side; used while editing. */
  readonly preview: ImageData
  readonly sourceWidth: number
  readonly sourceHeight: number
}

/**
 * Decode locally through an <img>. Browsers apply EXIF orientation when an
 * image element is drawn to a canvas (image-orientation: from-image), and the
 * canvas carries no metadata, so EXIF/GPS never reach the export.
 */
export async function decodePhoto(file: File, check: FileCheck): Promise<DecodedPhoto> {
  return withImage(file, check, (img, sw, sh) => {
    const work = drawScaled(img, sw, sh, fitSize(sw, sh, WORK_EDGE))
    const preview = drawScaled(work, work.width, work.height, fitSize(work.width, work.height, PREVIEW_EDGE))
    const result = { work: readPixels(work), preview: readPixels(preview), sourceWidth: sw, sourceHeight: sh }
    release(work)
    release(preview)
    return result
  })
}

/** Only the preview (PREVIEW_EDGE), for showing a photo; less memory than decodePhoto. */
export async function decodePreview(file: File, check: FileCheck): Promise<{ readonly preview: ImageData; readonly sourceWidth: number; readonly sourceHeight: number }> {
  return withImage(file, check, (img, sw, sh) => {
    const canvas = drawScaled(img, sw, sh, fitSize(sw, sh, PREVIEW_EDGE))
    const preview = readPixels(canvas)
    release(canvas)
    return { preview, sourceWidth: sw, sourceHeight: sh }
  })
}

async function withImage<T>(file: File, check: FileCheck, use: (img: HTMLImageElement, sw: number, sh: number) => T): Promise<T> {
  const url = URL.createObjectURL(file)
  try {
    const img = new Image()
    img.decoding = 'async'
    img.src = url
    try {
      await img.decode()
    } catch {
      throw new Error(
        check.kind === 'heic'
          ? 'This browser could not decode this HEIC file. On iPhone, pick it from Photos (the picker converts to JPEG) or export it as JPEG.'
          : 'Could not read this image. The file may be damaged or too large for this device.',
      )
    }
    return use(img, img.naturalWidth, img.naturalHeight)
  } finally {
    URL.revokeObjectURL(url)
  }
}

function drawScaled(src: CanvasImageSource, sw: number, sh: number, target: { width: number; height: number }): HTMLCanvasElement {
  let current: CanvasImageSource = src
  let cw = sw
  let ch = sh
  let previous: HTMLCanvasElement | null = null
  for (const step of downscaleSteps(sw, sh, target)) {
    const canvas = document.createElement('canvas')
    canvas.width = step.width
    canvas.height = step.height
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('This device ran out of canvas memory. Try a smaller photo.')
    ctx.imageSmoothingEnabled = true
    ctx.imageSmoothingQuality = 'high'
    ctx.drawImage(current, 0, 0, cw, ch, 0, 0, step.width, step.height)
    if (previous) release(previous)
    previous = canvas
    current = canvas
    cw = step.width
    ch = step.height
  }
  return previous as HTMLCanvasElement
}

function readPixels(canvas: HTMLCanvasElement): ImageData {
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('This device ran out of canvas memory. Try a smaller photo.')
  return ctx.getImageData(0, 0, canvas.width, canvas.height)
}

/** Free canvas backing memory early; iOS Safari has a low total canvas budget. */
export function release(canvas: HTMLCanvasElement): void {
  canvas.width = 0
  canvas.height = 0
}
