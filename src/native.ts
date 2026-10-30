/**
 * Client for the native RAW engine (ios/PocketFilmLab/Bridge/RawBridge.swift).
 * Only present inside the iOS app; in a browser `nativeRaw()` returns null and
 * the app keeps its JPEG/PNG-only path.
 */

export interface NativeLook {
  readonly id: string
  readonly label: string
}

export interface RawInfo {
  readonly name: string
  readonly width: number
  readonly height: number
  readonly wbTemp: number
  readonly wbTint: number
}

export interface RawSettings {
  readonly look: string
  readonly strength: number
  readonly exposure: number
  readonly grain: number
  readonly halation: number
  readonly wbTemp: number
  readonly wbTint: number
}

export type RenderResult = { readonly url: string; readonly ms: number } | { readonly stale: true }

interface Handler {
  postMessage(body: unknown): Promise<unknown>
}

export interface NativeRaw {
  looks(): Promise<readonly NativeLook[]>
  open(source: 'photos' | 'files'): Promise<RawInfo | null>
  render(settings: RawSettings, compare: boolean, maxEdge: number): Promise<RenderResult>
  exportFile(settings: RawSettings, format: 'heic' | 'jpeg'): Promise<{ readonly shared: boolean; readonly ms: number }>
}

function handler(): Handler | null {
  const w = window as unknown as { webkit?: { messageHandlers?: { raw?: Handler } } }
  return w.webkit?.messageHandlers?.raw ?? null
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
      const res = await call<RawInfo | { cancelled: true }>({ cmd: 'open', source })
      return 'cancelled' in res ? null : res
    },
    render: (settings, compare, maxEdge) => call<RenderResult>({ cmd: 'render', settings, compare, maxEdge }),
    exportFile: (settings, format) => call({ cmd: 'export', settings, format }),
  }
}
