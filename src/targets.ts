import type { BatchItem } from './batch'
import { downloadBlob, saveJpeg, type SaveOutcome } from './export'
import { exportName } from './files'
import { canSaveWith, type NativeRaw } from './native'
import { SaveStopped, type SaveTarget } from './save'
import { toRawSettings, type Adjustments } from './settings'
import type { Sources } from './sources'
import type { WebEngine } from './webengine'

/** Where "Save" puts photos: Photos in the iOS app, downloads (or a share) in a browser. */

const nameFor = (index: number, total: number) => exportName(new Date(), total > 1 ? index + 1 : undefined)

/** iOS app: RAW develops natively (HEIC); JPEG/PNG/HEIC develop here, then go to Photos as JPEG. */
export function photosTarget(bridge: NativeRaw, web: WebEngine, sources: Sources, adj: Adjustments): SaveTarget {
  return {
    prepare: async () => (canSaveWith(await bridge.saveAccess()) ? 'ok' : 'denied'),
    save: async (item, index, total) => {
      if (item.engine === 'raw') {
        if (!item.nativeId) throw new Error('This photo is no longer open.')
        await bridge.save(item.nativeId, toRawSettings(adj), 'heic')
        return
      }
      const blob = await web.full(await sources.file(item), adj)
      await bridge.saveData(nameFor(index, total), blob)
    },
  }
}

/** Browser: one photo goes to the share sheet when there is one, a batch downloads. */
export function downloadTarget(web: WebEngine, sources: Sources, adj: Adjustments, outcome: (o: SaveOutcome) => void): SaveTarget {
  return {
    prepare: async () => 'ok',
    save: async (item, index, total) => {
      const blob = await web.full(await sources.file(item), adj)
      if (total > 1) {
        downloadBlob(blob, nameFor(index, total))
        outcome('downloaded')
        return
      }
      const result = await saveJpeg(blob, nameFor(index, total))
      outcome(result)
      if (result === 'dismissed') throw new SaveStopped()
    },
  }
}

/** The share sheet for one photo (secondary to Save). Returns true if it was shared. */
export async function shareOne(item: BatchItem, bridge: NativeRaw | null, web: WebEngine, sources: Sources, adj: Adjustments): Promise<boolean> {
  if (item.engine === 'raw') {
    if (!bridge || !item.nativeId) throw new Error('This photo is no longer open.')
    return (await bridge.exportFile(item.nativeId, toRawSettings(adj), 'heic')).shared
  }
  const blob = await web.full(await sources.file(item), adj)
  return (await saveJpeg(blob, exportName(new Date()))) !== 'dismissed'
}
