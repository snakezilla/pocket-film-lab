import { COPY, FriendlyError } from './copy'
import type { BatchItem } from './batch'
import type { NativeRaw } from './native'

/**
 * The original pixels of a web-engine photo: the picked File in a browser, or the
 * JPEG/PNG the native side serves in the app. Keeps only the last File in memory.
 */
export class Sources {
  private last: { readonly key: string; readonly file: File } | null = null
  /** App: served URL per item. Browser: object URL per item (revoked on reset). */
  private urls = new Map<string, string>()

  constructor(private readonly bridge: NativeRaw | null) {}

  async file(item: BatchItem): Promise<File> {
    if (item.file) return item.file
    if (this.last?.key === item.key) return this.last.file
    const url = await this.url(item)
    const res = await fetch(url)
    if (!res.ok) throw new FriendlyError(COPY.oops)
    const blob = await res.blob()
    const file = new File([blob], this.nameFor(item, url), { type: blob.type })
    this.last = { key: item.key, file }
    return file
  }

  /** A URL that shows the photo as picked (for hold-to-compare). */
  async url(item: BatchItem): Promise<string> {
    const known = this.urls.get(item.key)
    if (known) return known
    let url: string
    if (item.file) {
      url = URL.createObjectURL(item.file)
    } else {
      const served = item.nativeId && this.bridge ? await this.bridge.source(item.nativeId) : null
      if (!served) throw new FriendlyError(COPY.noLongerOpen)
      url = served.url
    }
    this.urls.set(item.key, url)
    return url
  }

  reset(): void {
    for (const url of this.urls.values()) if (url.startsWith('blob:')) URL.revokeObjectURL(url)
    this.urls = new Map()
    this.last = null
  }

  /** The served file is always JPEG or PNG; keep the picked name's stem. */
  private nameFor(item: BatchItem, url: string): string {
    const ext = url.endsWith('.png') ? 'png' : 'jpg'
    return `${item.name.replace(/\.[^.]+$/, '') || 'photo'}.${ext}`
  }
}
