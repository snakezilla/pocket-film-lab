import { FriendlyError } from './copy'
import { decodePhoto, decodePreview } from './decode'
import { encodeJpeg } from './export'
import { checkFile, type FileCheck } from './files'
import { loadLutBuffer } from './looks'
import { Processor } from './processor'
import { toRecipe, webLookFor, type Adjustments } from './settings'

/** JPEG/PNG/HEIC on the web engine (a worker). Previews and full-size exports. */

export interface WebPreview {
  /** A blob: URL of a JPEG; the caller revokes it when replaced. */
  readonly url: string
  readonly width: number
  readonly height: number
  /** The photo's own size. */
  readonly sourceWidth: number
  readonly sourceHeight: number
  readonly ms: number
}

const PREVIEW_QUALITY = 0.9

function checked(file: File): FileCheck {
  const check = checkFile(file.name, file.type, file.size)
  if (check.kind === 'rejected') throw new FriendlyError(check.reason)
  return check
}

async function toJpegUrl(image: ImageData): Promise<string> {
  const canvas = document.createElement('canvas')
  canvas.width = image.width
  canvas.height = image.height
  canvas.getContext('2d')?.putImageData(image, 0, 0)
  try {
    const blob = await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Could not encode the preview.'))), 'image/jpeg', PREVIEW_QUALITY),
    )
    return URL.createObjectURL(blob)
  } finally {
    canvas.width = 0
    canvas.height = 0
  }
}

export class WebEngine {
  private readonly previewer = new Processor()
  private readonly exporter = new Processor()
  /** The decoded preview of the last photo, so slider moves on it skip decoding. */
  private cache: { readonly file: File; readonly image: ImageData; readonly width: number; readonly height: number } | null = null

  async preview(file: File, adj: Adjustments): Promise<WebPreview> {
    const source = this.cache?.file === file ? this.cache : await this.decode(file)
    const look = webLookFor(adj.look)
    const lut = await loadLutBuffer(look)
    const { image: out, ms } = await this.previewer.render(source.image, toRecipe(adj), lut, look.size)
    const url = await toJpegUrl(out)
    return { url, width: out.width, height: out.height, sourceWidth: source.width, sourceHeight: source.height, ms }
  }

  /** Full working size (long edge ≤ 2400), metadata-free JPEG. */
  async full(file: File, adj: Adjustments): Promise<Blob> {
    const photo = await decodePhoto(file, checked(file))
    const look = webLookFor(adj.look)
    const lut = await loadLutBuffer(look)
    const { image } = await this.exporter.render(photo.work, toRecipe(adj), lut, look.size)
    return encodeJpeg(image)
  }

  private async decode(file: File) {
    const { preview, sourceWidth, sourceHeight } = await decodePreview(file, checked(file))
    this.cache = { file, image: preview, width: sourceWidth, height: sourceHeight }
    return this.cache
  }

  /** Stops work and forgets the cached photo (a new pick). */
  reset(): void {
    this.previewer.cancel()
    this.exporter.cancel()
    this.cache = null
  }
}
