import { plural, type BatchItem } from './batch'

/**
 * Saving a batch: one photo at a time (a full-size render can peak at ~220 MB, so
 * never two at once), with progress, a stop between photos, and a report.
 */

export interface SaveTarget {
  /** Asks for permission once, before the first photo. */
  prepare(): Promise<'ok' | 'denied'>
  save(item: BatchItem, index: number, total: number): Promise<void>
}

/** Thrown by a target when the user dismissed something: stop without an error. */
export class SaveStopped extends Error {
  constructor() {
    super('Stopped')
    this.name = 'SaveStopped'
  }
}

export interface SaveFailure {
  readonly key: string
  readonly name: string
  readonly error: string
}

export interface SaveReport {
  readonly saved: readonly string[]
  readonly failed: readonly SaveFailure[]
  readonly stopped: boolean
  readonly denied: boolean
}

export async function saveAll(
  items: readonly BatchItem[],
  target: SaveTarget,
  onProgress: (done: number, total: number) => void,
  shouldStop: () => boolean,
): Promise<SaveReport> {
  const empty = { saved: [], failed: [], stopped: false }
  if ((await target.prepare()) === 'denied') return { ...empty, denied: true }
  const saved: string[] = []
  const failed: SaveFailure[] = []
  for (const [i, item] of items.entries()) {
    if (shouldStop()) return { saved, failed, stopped: true, denied: false }
    onProgress(i, items.length)
    try {
      await target.save(item, i, items.length)
      saved.push(item.key)
    } catch (error) {
      if (error instanceof SaveStopped) return { saved, failed, stopped: true, denied: false }
      failed.push({ key: item.key, name: item.name, error: error instanceof Error ? error.message : String(error) })
    }
  }
  onProgress(items.length, items.length)
  return { saved, failed, stopped: false, denied: false }
}

/** One line for the status after a save, e.g. verb "Saved", where " to Photos". */
export function saveSummary(report: SaveReport, total: number, verb: string, where = ''): string {
  if (report.denied) return 'Film Lab isn’t allowed to add photos. Allow “Add Photos Only” in Settings.'
  const n = report.saved.length
  const head = report.stopped
    ? `Stopped. ${verb} ${n} of ${total}${where}.`
    : report.failed.length
      ? `${verb} ${n} of ${total}${where}.`
      : `${verb} ${plural(n, 'photo')}${where}.`
  if (!report.failed.length) return head
  const first = report.failed[0]
  const more = report.failed.length > 1 ? ` (and ${report.failed.length - 1} more)` : ''
  return `${head} ${first.name} failed: ${first.error}${more}`
}
