import { heroItem, progress, saveable, statusLine, type Batch, type BatchItem } from './batch'
import type { Refs } from './dom'
import type { NativeLook } from './native'
import type { Adjustments } from './settings'

/** Draws the page from state. No state of its own except the thumbnail elements. */

export type SavePhase =
  | { readonly phase: 'idle' }
  | { readonly phase: 'saving'; readonly done: number; readonly total: number; readonly stopping: boolean }
  | { readonly phase: 'done'; readonly version: number; readonly epoch: number }
  | { readonly phase: 'denied' }

export interface ViewState {
  readonly app: boolean
  readonly batch: Batch | null
  readonly version: number
  readonly adj: Adjustments
  readonly looks: readonly NativeLook[]
  readonly save: SavePhase
  readonly message: { readonly text: string; readonly error: boolean } | null
  readonly comparing: boolean
  readonly busyShare: boolean
}

export function render(refs: Refs, s: ViewState, strip: ThumbStrip): void {
  const batch = s.batch
  refs.welcome.hidden = batch !== null
  refs.work.hidden = batch === null
  const saving = s.save.phase === 'saving'
  refs.pick.disabled = saving
  refs.repick.hidden = batch === null
  refs.repick.disabled = saving
  if (!batch) return
  const hero = heroItem(batch)
  renderHero(refs, s, hero)
  strip.sync(batch)
  renderProgress(refs, batch)
  renderStatus(refs, s, batch, hero)
  renderActions(refs, s, batch)
}

function renderHero(refs: Refs, s: ViewState, hero: BatchItem | undefined): void {
  if (!s.comparing && hero?.filmUrl && refs.view.getAttribute('src') !== hero.filmUrl) refs.view.src = hero.filmUrl
  if (!hero?.filmUrl) refs.view.removeAttribute('src')
  refs.view.alt = hero ? `${hero.name}, developed` : ''
  refs.view.hidden = !hero?.filmUrl
  refs.spinner.hidden = !hero || hero.state === 'failed' || Boolean(hero.filmUrl)
  refs.badge.hidden = !s.comparing
  refs.compare.hidden = !hero?.filmUrl
  refs.compare.setAttribute('aria-pressed', String(s.comparing))
  refs.stage.classList.toggle('failed', hero?.state === 'failed')
}

function renderProgress(refs: Refs, batch: Batch): void {
  const p = progress(batch)
  const developing = p.done < p.total
  refs.progress.hidden = !developing || p.total < 2
  refs.progress.querySelector('span')?.style.setProperty('--p', String(p.total ? p.done / p.total : 0))
}

function renderStatus(refs: Refs, s: ViewState, batch: Batch, hero: BatchItem | undefined): void {
  const look = s.looks.find((l) => l.id === s.adj.look)?.label ?? ''
  const heroError = hero?.state === 'failed' ? `This photo couldn’t be developed. ${hero.error ?? ''}`.trim() : ''
  const text = s.message?.text || heroError || statusLine(batch, look)
  refs.status.textContent = text
  refs.status.classList.toggle('error', Boolean(s.message?.error || (!s.message && heroError)))
}

function renderActions(refs: Refs, s: ViewState, batch: Batch): void {
  const n = saveable(batch).length
  const save = s.save
  const done = save.phase === 'done' && save.version === s.version && save.epoch === batch.epoch
  const saving = save.phase === 'saving'
  refs.save.disabled = n === 0 || saving || done
  refs.save.classList.toggle('busy', saving)
  refs.save.classList.toggle('done', done)
  refs.save.setAttribute('aria-busy', String(saving))
  refs.saveLabel.textContent = saveLabel(s.app, n, save, done)
  const fill = refs.save.querySelector<HTMLElement>('.fill')
  fill?.style.setProperty('--p', saving ? String(save.total ? save.done / save.total : 0) : '0')
  refs.share.hidden = !s.app || saving
  refs.share.disabled = s.busyShare || !heroItem(batch)?.filmUrl
  refs.stop.hidden = !saving
  refs.stop.disabled = saving && save.stopping
  refs.denied.hidden = save.phase !== 'denied'
}

export function saveLabel(app: boolean, n: number, save: SavePhase, done: boolean): string {
  if (save.phase === 'saving') {
    if (save.stopping) return 'Stopping…'
    return save.total > 1 ? `Saving ${Math.min(save.done + 1, save.total)} of ${save.total}…` : 'Saving…'
  }
  if (done) return app ? 'Saved to Photos' : n > 1 ? 'Downloaded' : 'Saved'
  if (app) return n > 1 ? `Save ${n} to Photos` : 'Save to Photos'
  return n > 1 ? `Download ${n}` : 'Download'
}

/** The row of thumbnails under the photo (a batch only). */
export class ThumbStrip {
  private epoch = -1
  private buttons = new Map<string, HTMLButtonElement>()

  constructor(private readonly root: HTMLElement) {}

  sync(batch: Batch): void {
    this.root.hidden = batch.items.length < 2
    if (batch.epoch !== this.epoch) this.build(batch)
    batch.items.forEach((item, i) => {
      const btn = this.buttons.get(item.key)
      if (!btn) return
      const img = btn.querySelector('img')
      if (img && item.filmUrl && img.getAttribute('src') !== item.filmUrl) img.src = item.filmUrl
      btn.dataset.state = item.state
      const current = i === batch.hero
      btn.setAttribute('aria-current', String(current))
      btn.setAttribute('aria-label', `${item.name}, photo ${i + 1} of ${batch.items.length}${item.state === 'failed' ? ', couldn’t be developed' : ''}`)
      if (current && this.root.dataset.hero !== item.key) {
        this.root.dataset.hero = item.key
        btn.scrollIntoView?.({ block: 'nearest', inline: 'nearest' })
      }
    })
  }

  private build(batch: Batch): void {
    this.epoch = batch.epoch
    this.buttons = new Map()
    const els = batch.items.map((item) => {
      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'thumb'
      btn.dataset.key = item.key
      const img = document.createElement('img')
      img.alt = ''
      img.draggable = false
      btn.append(img)
      this.buttons.set(item.key, btn)
      return btn
    })
    this.root.replaceChildren(...els)
  }
}
