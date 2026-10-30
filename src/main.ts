import './style.css'
import { AdjustPanel } from './adjust'
import { BATCH_LIMIT, heroItem, newItem, pickNote, saveable, updateItem, type BatchItem } from './batch'
import { Developer } from './developer'
import { findRefs } from './dom'
import type { SaveOutcome } from './export'
import { LOOKS } from './looks'
import { nativeRaw } from './native'
import { saveAll, saveSummary } from './save'
import { DEFAULT_ADJUSTMENTS, toRawSettings, type Adjustments } from './settings'
import { Sources } from './sources'
import { downloadTarget, photosTarget, shareOne } from './targets'
import { render, ThumbStrip, type ViewState } from './view'
import { WebEngine } from './webengine'

/**
 * One flow: choose photos → they develop with the default look → one button saves
 * them all. Adjustments sit in a closed "Adjust" drop-down and apply to every photo.
 */

const refs = findRefs()
const bridge = nativeRaw()
const web = new WebEngine()
const sources = new Sources(bridge)
const strip = new ThumbStrip(refs.strip)

let state: ViewState = {
  app: bridge !== null,
  batch: null,
  version: 0,
  adj: { ...DEFAULT_ADJUSTMENTS, look: bridge ? '' : LOOKS[0].id },
  looks: bridge ? [] : LOOKS.map(({ id, label }) => ({ id, label })),
  save: { phase: 'idle' },
  message: null,
  comparing: false,
  busyShare: false,
}
let epochs = 0
let keys = 0
let stopRequested = false
/** Plain-decode compare previews of RAW photos, by item + the settings they depend on. */
let originals = new Map<string, string>()

const panel = new AdjustPanel(refs, (adj, kind) => onAdjust(adj, kind), () => onAdjust(defaults(), 'wb'))

function setState(patch: Partial<ViewState>): void {
  state = { ...state, ...patch }
  paint()
}

function paint(): void {
  render(refs, state, strip)
  const batch = state.batch
  const hero = batch ? heroItem(batch) : undefined
  panel.sync({
    adj: state.adj,
    looks: state.looks,
    asShot: hero?.info ?? batch?.items.find((it) => it.info)?.info ?? null,
    count: batch?.items.length ?? 0,
    hasRaw: batch?.items.some((it) => it.engine === 'raw') ?? false,
  })
}

const say = (text: string, error = false) => setState({ message: text ? { text, error } : null })
const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e))
const defaults = (): Adjustments => ({ ...DEFAULT_ADJUSTMENTS, look: state.looks[0]?.id ?? '' })
const revoke = (url: string | undefined) => url?.startsWith('blob:') && URL.revokeObjectURL(url)

// ---- Developing previews

const developer = new Developer({
  snapshot: () => ({ batch: state.batch, version: state.version }),
  develop: developPreview,
  commit: (epoch, key, patch) => {
    if (state.batch?.epoch !== epoch) return revoke(patch.filmUrl)
    const old = state.batch.items.find((it) => it.key === key)?.filmUrl
    setState({ batch: updateItem(state.batch, key, patch) })
    if (patch.filmUrl && old !== patch.filmUrl) revoke(old)
  },
})

function previewEdge(): number {
  const css = Math.max(refs.stage.clientWidth, refs.stage.clientHeight, 640)
  return Math.min(2048, Math.round(css * (window.devicePixelRatio || 1)))
}

async function developPreview(item: BatchItem, hero: boolean): Promise<Partial<BatchItem> | null> {
  const adj = state.adj
  if (item.engine === 'raw') {
    if (!bridge || !item.nativeId) throw new Error('RAW photos need the iOS app.')
    const res = await bridge.render(item.nativeId, toRawSettings(adj), { compare: false, maxEdge: previewEdge(), hero })
    if ('stale' in res) return null
    return { filmUrl: res.url, info: res.info, width: res.info.width, height: res.info.height }
  }
  const out = await web.preview(await sources.file(item), adj)
  return { filmUrl: out.url, width: out.sourceWidth, height: out.sourceHeight }
}

// ---- Picking

async function ensureLooks(): Promise<void> {
  if (!bridge || state.looks.length) return
  const looks = await bridge.looks()
  setState({ looks, adj: state.adj.look ? state.adj : { ...state.adj, look: looks[0]?.id ?? '' } })
}

async function pickFrom(source: 'photos' | 'files'): Promise<void> {
  if (state.save.phase === 'saving') return
  if (!bridge) {
    refs.file.click()
    return
  }
  try {
    await ensureLooks()
    const res = await bridge.open(source)
    if (!res) return // cancelled: the current photos stay
    const items = res.items.map((it) => newItem(`k${++keys}`, it.name, it.kind === 'raw' ? 'raw' : 'web', { nativeId: it.id }))
    startBatch(items, pickNote(res.skipped, res.truncated))
  } catch (error) {
    if (state.batch) say(errorText(error), true)
    else refs.pickNote.textContent = errorText(error)
  }
}

function onFiles(files: readonly File[]): void {
  const kept = files.slice(0, BATCH_LIMIT)
  const items = kept.map((file) => newItem(`k${++keys}`, file.name, 'web', { file }))
  startBatch(items, pickNote(0, files.length - kept.length))
}

function startBatch(items: readonly BatchItem[], note: string): void {
  if (!items.length) return
  web.reset()
  sources.reset()
  for (const it of state.batch?.items ?? []) revoke(it.filmUrl)
  originals = new Map()
  refs.pickNote.textContent = ''
  setState({
    batch: { epoch: ++epochs, items, hero: 0 },
    save: { phase: 'idle' },
    message: note ? { text: note, error: false } : null,
    comparing: false,
  })
  developer.kick()
}

function selectHero(key: string): void {
  const batch = state.batch
  const index = batch?.items.findIndex((it) => it.key === key) ?? -1
  if (!batch || index < 0 || index === batch.hero) return
  setState({ batch: { ...batch, hero: index }, comparing: false, message: null })
  developer.kick()
}

// ---- Adjusting

function onAdjust(adj: Adjustments, kind: 'look' | 'tone' | 'wb'): void {
  if (kind !== 'look') originals = new Map() // exposure and white balance change the plain decode
  const save = state.save.phase === 'saving' ? state.save : { phase: 'idle' as const }
  setState({ adj, version: state.version + 1, message: null, save })
  developer.touched()
}

// ---- Hold to compare

let compareTimer: ReturnType<typeof setTimeout> | null = null
let compareToken = 0

async function originalUrl(item: BatchItem): Promise<string> {
  if (item.engine !== 'raw') return sources.url(item)
  const adj = state.adj
  const cacheKey = `${item.key}|${adj.exposure}|${adj.wbTemp}|${adj.wbTint}`
  const known = originals.get(cacheKey)
  if (known) return known
  if (!bridge || !item.nativeId) throw new Error('RAW photos need the iOS app.')
  const res = await bridge.render(item.nativeId, toRawSettings(adj), { compare: true, maxEdge: previewEdge(), hero: true })
  if ('stale' in res) throw new Error('stale')
  originals.set(cacheKey, res.url)
  return res.url
}

async function showOriginal(on: boolean): Promise<void> {
  const hero = state.batch ? heroItem(state.batch) : undefined
  if (on === state.comparing || !hero?.filmUrl) return
  const token = ++compareToken
  setState({ comparing: on })
  if (!on) return
  try {
    const url = await originalUrl(hero)
    if (token === compareToken && state.comparing) refs.view.src = url
  } catch {
    if (token === compareToken) setState({ comparing: false })
  }
}

function holdStart(): void {
  if (compareTimer) clearTimeout(compareTimer)
  // A short hold, so a scroll that starts on the photo does not flash the original.
  compareTimer = setTimeout(() => void showOriginal(true), 120)
}

function holdEnd(): void {
  if (compareTimer) clearTimeout(compareTimer)
  compareTimer = null
  void showOriginal(false)
}

// ---- Saving and sharing

async function onSave(): Promise<void> {
  const batch = state.batch
  if (!batch || state.save.phase === 'saving') return
  const items = saveable(batch)
  const { adj, version } = state
  let outcome: SaveOutcome = 'downloaded'
  const target = bridge ? photosTarget(bridge, web, sources, adj) : downloadTarget(web, sources, adj, (o) => (outcome = o))
  stopRequested = false
  setState({ save: { phase: 'saving', done: 0, total: items.length, stopping: false }, message: null })
  const report = await saveAll(
    items,
    target,
    (done, total) => state.batch?.epoch === batch.epoch && setState({ save: { phase: 'saving', done, total, stopping: stopRequested } }),
    () => stopRequested || state.batch?.epoch !== batch.epoch,
  )
  if (state.batch?.epoch !== batch.epoch) return
  const clean = report.saved.length > 0 && !report.failed.length && !report.stopped
  const text =
    !bridge && items.length === 1 && outcome !== 'downloaded'
      ? outcome === 'shared' ? 'Shared.' : 'Share sheet closed; nothing saved.'
      : saveSummary(report, items.length, bridge ? 'Saved' : 'Downloaded', bridge ? ' to Photos' : '')
  setState({
    save: report.denied ? { phase: 'denied' } : clean ? { phase: 'done', version, epoch: batch.epoch } : { phase: 'idle' },
    message: { text, error: report.failed.length > 0 || report.denied },
  })
}

async function onShare(): Promise<void> {
  const hero = state.batch ? heroItem(state.batch) : undefined
  if (!hero || state.busyShare) return
  setState({ busyShare: true, message: { text: 'Preparing full size…', error: false } })
  try {
    const shared = await shareOne(hero, bridge, web, sources, state.adj)
    setState({ busyShare: false, message: shared ? { text: 'Shared.', error: false } : null })
  } catch (error) {
    setState({ busyShare: false, message: { text: errorText(error), error: true } })
  }
}

// ---- Wiring

function wire(): void {
  refs.pick.addEventListener('click', () => void pickFrom('photos'))
  refs.repick.addEventListener('click', () => void pickFrom('photos'))
  refs.pickFiles.addEventListener('click', () => void pickFrom('files'))
  refs.file.addEventListener('change', () => {
    const files = Array.from(refs.file.files ?? [])
    refs.file.value = '' // allow picking the same files again
    if (files.length) onFiles(files)
  })
  refs.strip.addEventListener('click', (e) => {
    const key = (e.target as HTMLElement).closest<HTMLElement>('[data-key]')?.dataset.key
    if (key) selectHero(key)
  })
  refs.stage.addEventListener('pointerdown', holdStart)
  for (const ev of ['pointerup', 'pointerleave', 'pointercancel'] as const) refs.stage.addEventListener(ev, holdEnd)
  refs.stage.addEventListener('contextmenu', (e) => e.preventDefault())
  refs.compare.addEventListener('keydown', (e) => (e.key === ' ' || e.key === 'Enter') && (e.preventDefault(), void showOriginal(true)))
  refs.compare.addEventListener('keyup', (e) => (e.key === ' ' || e.key === 'Enter') && void showOriginal(false))
  refs.save.addEventListener('click', () => void onSave())
  refs.stop.addEventListener('click', () => {
    stopRequested = true
    if (state.save.phase === 'saving') setState({ save: { ...state.save, stopping: true } })
  })
  refs.share.addEventListener('click', () => void onShare())
  refs.openSettings.addEventListener('click', () => void bridge?.openSettings())
}

refs.pickFiles.hidden = !bridge
wire()
paint()
void ensureLooks().catch((error) => (refs.pickNote.textContent = errorText(error)))
