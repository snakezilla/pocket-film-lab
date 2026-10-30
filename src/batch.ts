import type { RawInfo } from './native'

/**
 * The picked photos and how far each one has got. Pure data plus pure helpers, so
 * the scheduling and labels are unit tested without a page.
 */

export type ItemState = 'waiting' | 'developing' | 'ready' | 'failed'

export interface BatchItem {
  readonly key: string
  readonly name: string
  /** `raw`: developed by the native engine. `web`: JPEG/PNG/HEIC on the web engine. */
  readonly engine: 'raw' | 'web'
  /** The native item id (app only). */
  readonly nativeId?: string
  /** The picked file (browser only). */
  readonly file?: File
  readonly state: ItemState
  readonly error?: string
  readonly filmUrl?: string
  /** The settings version `filmUrl` was made with; -1 before the first preview. */
  readonly developed: number
  readonly info?: RawInfo
  readonly width?: number
  readonly height?: number
}

export interface Batch {
  /** Bumped for every new pick; work for an older epoch is dropped. */
  readonly epoch: number
  readonly items: readonly BatchItem[]
  readonly hero: number
}

export function newItem(key: string, name: string, engine: 'raw' | 'web', extra: Partial<BatchItem> = {}): BatchItem {
  return { key, name, engine, state: 'waiting', developed: -1, ...extra }
}

export function updateItem(batch: Batch, key: string, patch: Partial<BatchItem>): Batch {
  return { ...batch, items: batch.items.map((it) => (it.key === key ? { ...it, ...patch } : it)) }
}

export function heroItem(batch: Batch): BatchItem | undefined {
  return batch.items[batch.hero]
}

const needsWork = (it: BatchItem, version: number) => it.state !== 'failed' && it.developed < version

/**
 * The next photo to develop: the one on screen first, then the others in pick order.
 * `background` false holds the others back (the user is still moving a slider).
 */
export function nextToDevelop(batch: Batch, version: number, background: boolean): BatchItem | null {
  const hero = heroItem(batch)
  if (hero && needsWork(hero, version)) return hero
  if (!background) return null
  // Photos never developed come before re-developing ones that already show something.
  return batch.items.find((it) => it.developed < 0 && needsWork(it, version)) ?? batch.items.find((it) => needsWork(it, version)) ?? null
}

export interface Progress {
  readonly total: number
  /** Developed at least once (or failed). */
  readonly done: number
  readonly failed: number
}

export function progress(batch: Batch): Progress {
  const failed = batch.items.filter((it) => it.state === 'failed').length
  const shown = batch.items.filter((it) => it.state !== 'failed' && it.developed >= 0).length
  return { total: batch.items.length, done: shown + failed, failed }
}

/** Photos a save will try: everything that has not failed. */
export function saveable(batch: Batch): readonly BatchItem[] {
  return batch.items.filter((it) => it.state !== 'failed')
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`
}

/** The status line under the photo. */
export function statusLine(batch: Batch, lookLabel: string): string {
  const p = progress(batch)
  if (p.done < p.total) return `Developing ${Math.min(p.done + 1, p.total)} of ${p.total}…`
  const hero = heroItem(batch)
  const failedNote = p.failed ? ` · ${p.failed} couldn’t be read` : ''
  if (p.total === 1 && hero) {
    const size = hero.width && hero.height ? ` · ${hero.width} × ${hero.height}` : ''
    return `${lookLabel}${hero.engine === 'raw' ? ' · RAW' : ''}${size}`
  }
  return `${plural(p.total - p.failed, 'photo')} · ${lookLabel}${failedNote}`
}

/** The most photos one pick keeps (RawBridge.maxBatch). */
export const BATCH_LIMIT = 50

/** Notes about a pick that did not open everything. */
export function pickNote(skipped: number, truncated: number): string {
  const parts: string[] = []
  if (truncated) parts.push(`Kept the first ${BATCH_LIMIT}; ${plural(truncated, 'photo was', 'photos were')} left out.`)
  if (skipped) parts.push(`${plural(skipped, 'photo', 'photos')} couldn’t be read.`)
  return parts.join(' ')
}
