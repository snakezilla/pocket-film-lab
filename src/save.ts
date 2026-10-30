import type { BatchItem } from './batch'
import { COPY, friendlyMessage } from './copy'

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
      failed.push({ key: item.key, name: item.name, error: friendlyMessage(error) })
    }
  }
  onProgress(items.length, items.length)
  return { saved, failed, stopped: false, denied: false }
}

/** One line for the status after a save. `photos`: saved to Photos (app) or downloaded (browser). */
export function saveSummary(report: SaveReport, total: number, photos: boolean): string {
  if (report.denied) return COPY.denied
  const n = report.saved.length
  if (report.stopped) return photos ? COPY.stopped(n, total) : COPY.stoppedDownloads(n, total)
  if (report.failed.length) {
    const head = photos ? COPY.savedSome(n, total) : COPY.downloadedSome(n, total)
    // One failure keeps its own words when they say more than "didn't work"; several get one line.
    const why = report.failed.length === 1 && report.failed[0].error !== COPY.oops ? report.failed[0].error : COPY.failedSome(report.failed.length)
    return `${head} ${why}`
  }
  if (!photos) return COPY.downloaded(n)
  return n === 1 ? COPY.savedOne : COPY.savedMany(n)
}
