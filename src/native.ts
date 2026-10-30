/**
 * Client for the native engine (ios/PocketFilmLab/Bridge/RawBridge.swift).
 * Only present inside the iOS app; in a browser `nativeRaw()` returns null and
 * the app uses its own JPEG/PNG path for everything.
 */

export interface NativeLook {
  readonly id: string
  readonly label: string
}

/** What the native side reports about an opened RAW. */
export interface RawInfo {
  readonly width: number
  readonly height: number
  readonly wbTemp: number
  readonly wbTint: number
}

/** One picked photo. A `photo` is not RAW: the page develops it on its JPEG/PNG path. */
export interface PickedItem {
  readonly id: string
  readonly kind: 'raw' | 'photo'
  readonly name: string
}

export interface PickResult {
  readonly items: readonly PickedItem[]
  /** Picked but unreadable. */
  readonly skipped: number
  /** Over the batch limit, not opened. */
  readonly truncated: number
}

export interface RawSettings {
  readonly look: string
  readonly strength: number
  readonly exposure: number
  readonly grain: number
  readonly halation: number
  /** 0…1, off by default. Gentle scene-linear softening (native engine only). */
  readonly softness: number
  /** 0…1, off by default. Optional cream near-whites; 0 keeps greys neutral. */
  readonly warmth: number
  /** Both or neither. Neither means each photo's own as-shot white balance. */
  readonly wbTemp?: number
  readonly wbTint?: number
}

export interface RenderOptions {
  readonly compare: boolean
  readonly maxEdge: number
  /** The photo on screen: the native side keeps its decode cached. */
  readonly hero: boolean
}

export type RenderResult = { readonly url: string; readonly ms: number; readonly info: RawInfo } | { readonly stale: true }

export type PhotoAccess = 'authorized' | 'limited' | 'denied' | 'restricted' | 'notDetermined'

export const canSaveWith = (access: PhotoAccess): boolean => access === 'authorized' || access === 'limited'

interface Handler {
  postMessage(body: unknown): Promise<unknown>
}

export interface NativeRaw {
  looks(): Promise<readonly NativeLook[]>
  /** Shows the picker. Null when cancelled or replaced meanwhile. */
  open(source: 'photos' | 'files'): Promise<PickResult | null>
  /** A non-RAW photo as a JPEG/PNG URL for the web path. Null if the batch changed. */
  source(id: string): Promise<{ readonly url: string; readonly name: string } | null>
  render(id: string, settings: RawSettings, options: RenderOptions): Promise<RenderResult>
  /** Full size to the share sheet. */
  exportFile(id: string, settings: RawSettings, format: 'heic' | 'jpeg'): Promise<{ readonly shared: boolean; readonly ms: number }>
  saveAccess(): Promise<PhotoAccess>
  /** Full size into Photos. */
  save(id: string, settings: RawSettings, format: 'heic' | 'jpeg'): Promise<void>
  /** A JPEG the page developed, into Photos. */
  saveData(name: string, blob: Blob): Promise<void>
  openSettings(): Promise<void>
  /** Native side drops the batch, its temp copies and its previews. */
  clear(): Promise<void>
}

function handler(): Handler | null {
  const w = window as unknown as { webkit?: { messageHandlers?: { raw?: Handler } } }
  return w.webkit?.messageHandlers?.raw ?? null
}

export async function toBase64(blob: Blob): Promise<string> {
  const bytes = new Uint8Array(await blob.arrayBuffer())
  let s = ''
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return btoa(s)
}

export function nativeRaw(): NativeRaw | null {
  const h = handler()
  if (!h) return null
  const call = async <T>(body: Record<string, unknown>): Promise<T> => {
    try {
      return (await h.postMessage(body)) as T
    } catch (error) {
      throw new Error(error instanceof Error ? error.message : String(error))
    }
  }
  return {
    looks: async () => (await call<{ looks: NativeLook[] }>({ cmd: 'looks' })).looks,
    open: async (source) => {
      const res = await call<PickResult | { cancelled: true } | { stale: true }>({ cmd: 'open', source })
      return 'items' in res ? { items: res.items, skipped: res.skipped ?? 0, truncated: res.truncated ?? 0 } : null
    },
    source: async (id) => {
      const res = await call<{ url: string; name: string } | { stale: true }>({ cmd: 'source', id })
      return 'url' in res ? res : null
    },
    render: (id, settings, options) => call<RenderResult>({ cmd: 'render', id, settings, ...options }),
    exportFile: (id, settings, format) => call({ cmd: 'export', id, settings, format }),
    saveAccess: async () => (await call<{ access: PhotoAccess }>({ cmd: 'saveAccess' })).access,
    save: async (id, settings, format) => {
      await call({ cmd: 'save', id, settings, format })
    },
    saveData: async (name, blob) => {
      await call({ cmd: 'saveData', name, data: await toBase64(blob) })
    },
    openSettings: async () => {
      await call({ cmd: 'openSettings' })
    },
    clear: async () => {
      await call({ cmd: 'clear' })
    },
  }
}
