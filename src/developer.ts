import { heroItem, nextToDevelop, type Batch, type BatchItem } from './batch'
import { CancelledError } from './processor'

/**
 * Develops previews one photo at a time: the photo on screen first, then the rest in
 * pick order. After a settings change the others wait until the sliders have been
 * still for `idleMs`, so dragging stays responsive on a big batch.
 */

export interface DevelopHost {
  snapshot(): { readonly batch: Batch | null; readonly version: number }
  /** Makes a preview. Null: the request went stale (a newer one replaced it). */
  develop(item: BatchItem, hero: boolean): Promise<Partial<BatchItem> | null>
  /** Applies a result. The host ignores results for an older epoch. */
  commit(epoch: number, key: string, patch: Partial<BatchItem>): void
}

export class Developer {
  private running = false
  private holdUntil = 0
  private timer: ReturnType<typeof setTimeout> | null = null
  /** Stale replies in a row for one photo; a guard against retrying forever. */
  private stale = { key: '', count: 0 }

  constructor(
    private readonly host: DevelopHost,
    private readonly idleMs = 600,
    private readonly now: () => number = () => performance.now(),
  ) {}

  get busy(): boolean {
    return this.running
  }

  /** Settings changed: the photo on screen now, the others after a pause. */
  touched(): void {
    this.holdUntil = this.now() + this.idleMs
    this.kick()
  }

  kick(): void {
    if (this.running) return
    this.running = true
    void this.loop().finally(() => {
      this.running = false
    })
  }

  private async loop(): Promise<void> {
    for (;;) {
      const { batch, version } = this.host.snapshot()
      if (!batch) return
      const background = this.now() >= this.holdUntil
      const item = nextToDevelop(batch, version, background)
      if (!item) {
        if (!background && nextToDevelop(batch, version, true)) this.wakeAt(this.holdUntil)
        return
      }
      await this.developOne(batch, item, version)
    }
  }

  private async developOne(batch: Batch, item: BatchItem, version: number): Promise<void> {
    if (item.state === 'waiting') this.host.commit(batch.epoch, item.key, { state: 'developing' })
    try {
      const patch = await this.host.develop(item, item === heroItem(batch))
      if (patch) {
        this.stale = { key: '', count: 0 }
        this.host.commit(batch.epoch, item.key, { ...patch, state: 'ready', developed: version })
        return
      }
      // Stale: a newer request for this photo replaced it; the next pass redoes it,
      // but never more than a few times in a row.
      this.stale = { key: item.key, count: this.stale.key === item.key ? this.stale.count + 1 : 1 }
      if (this.stale.count >= 3) this.host.commit(batch.epoch, item.key, { developed: version })
    } catch (error) {
      // Cancelled: a new pick reset the engines; the next pass sees the new batch.
      if (error instanceof CancelledError) return
      const message = error instanceof Error ? error.message : String(error)
      this.host.commit(batch.epoch, item.key, { state: 'failed', error: message, developed: version })
    }
  }

  private wakeAt(at: number): void {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.timer = null
      this.kick()
    }, Math.max(0, at - this.now()))
  }
}
