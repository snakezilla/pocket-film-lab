import type { NativeLook, NativeRaw, RawInfo, RawSettings } from './native'

/**
 * RAW mode: the page is only the control surface, the native engine develops.
 * Previews come back as app://local/__raw/<n>.jpg URLs shown in an <img>.
 */
export interface RawUi {
  readonly view: HTMLImageElement
  readonly say: (message: string, isError?: boolean) => void
}

export const RAW_DEFAULTS = { strength: 1, exposure: 0, grain: 0.35, halation: 0.3 } as const

export class RawMode {
  private info: RawInfo | null = null
  private filmUrl = ''
  private compareUrl = ''
  private busy = false
  private queued = false
  private comparing = false

  constructor(
    private readonly bridge: NativeRaw,
    private readonly ui: RawUi,
  ) {}

  get active(): boolean {
    return this.info !== null
  }

  get file(): RawInfo | null {
    return this.info
  }

  looks(): Promise<readonly NativeLook[]> {
    return this.bridge.looks()
  }

  async open(source: 'photos' | 'files'): Promise<RawInfo | null> {
    const info = await this.bridge.open(source)
    if (!info) return null
    this.info = info
    this.compareUrl = ''
    return info
  }

  close(): void {
    this.info = null
  }

  private maxEdge(): number {
    const css = Math.max(this.ui.view.clientWidth, this.ui.view.clientHeight, 640)
    return Math.min(2048, Math.round(css * (window.devicePixelRatio || 1)))
  }

  /** Coalesces rapid changes: one render in flight, at most one queued. */
  async render(settings: () => RawSettings, label: string): Promise<void> {
    if (!this.info) return
    if (this.busy) {
      this.queued = true
      return
    }
    this.busy = true
    try {
      const t0 = performance.now()
      const res = await this.bridge.render(settings(), false, this.maxEdge())
      if ('url' in res) {
        this.filmUrl = res.url
        if (!this.comparing) this.ui.view.src = res.url
        const total = performance.now() - t0
        this.ui.say(`${label} · native ${Math.round(res.ms)} ms, round trip ${Math.round(total)} ms`)
      }
    } catch (error) {
      this.ui.say(error instanceof Error ? error.message : String(error), true)
    } finally {
      this.busy = false
    }
    if (this.queued) {
      this.queued = false
      await this.render(settings, label)
    }
  }

  async compare(on: boolean, settings: RawSettings): Promise<void> {
    this.comparing = on
    if (!on) {
      if (this.filmUrl) this.ui.view.src = this.filmUrl
      return
    }
    if (!this.compareUrl) {
      const res = await this.bridge.render(settings, true, this.maxEdge())
      if ('url' in res) this.compareUrl = res.url
    }
    if (this.comparing && this.compareUrl) this.ui.view.src = this.compareUrl
  }

  /** Clears the cached plain decode (white balance or exposure changed). */
  invalidateCompare(): void {
    this.compareUrl = ''
  }

  async exportFile(settings: RawSettings, format: 'heic' | 'jpeg'): Promise<void> {
    if (!this.info) return
    this.ui.say(`Developing ${this.info.width}×${this.info.height} ${format.toUpperCase()}…`)
    try {
      const res = await this.bridge.exportFile(settings, format)
      this.ui.say(res.shared ? `Shared. Developed in ${(res.ms / 1000).toFixed(1)} s, no location or camera data kept.` : 'Share sheet closed; nothing saved.')
    } catch (error) {
      this.ui.say(error instanceof Error ? error.message : String(error), true)
    }
  }
}
