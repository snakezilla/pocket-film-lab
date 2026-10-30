import type { Refs } from './dom'
import type { NativeLook, RawInfo } from './native'
import { formatTint, formatValue, type Adjustments, type SliderKey } from './settings'
import { WB_TEMP_LIMITS, WB_TEMP_RANGE, WB_TINT_LIMITS, WB_TINT_RANGE, rangeIncluding, type SliderRange } from './wb'

/**
 * The "Adjust" drop-down: look, strength, exposure, texture and (RAW only) white
 * balance. Closed by default. It only reports changes; the page owns the state.
 */

const TONE: readonly SliderKey[] = ['strength', 'exposure', 'grain', 'halation', 'softness', 'warmth']

export interface AdjustView {
  readonly adj: Adjustments
  readonly looks: readonly NativeLook[]
  /** As-shot white balance of the photo on screen (RAW), shown while WB is "as shot". */
  readonly asShot: RawInfo | null
  readonly count: number
  readonly hasRaw: boolean
}

export class AdjustPanel {
  private view: AdjustView | null = null

  constructor(
    private readonly refs: Refs,
    private readonly onChange: (adj: Adjustments, kind: 'look' | 'tone' | 'wb') => void,
    onReset: () => void,
  ) {
    for (const key of TONE) {
      refs.input(key).addEventListener('input', (e) => this.emit({ [key]: Number((e.target as HTMLInputElement).value) }, 'tone'))
    }
    for (const id of ['wbTemp', 'wbTint']) {
      refs.input(id).addEventListener('input', () =>
        // Moving either one fixes both: the batch leaves "as shot" together.
        this.emit({ wbTemp: Number(refs.input('wbTemp').value), wbTint: Number(refs.input('wbTint').value) }, 'wb'),
      )
    }
    refs.reset.addEventListener('click', () => onReset())
  }

  private emit(patch: Partial<Adjustments>, kind: 'look' | 'tone' | 'wb'): void {
    if (!this.view) return
    this.onChange({ ...this.view.adj, ...patch }, kind)
  }

  /** Brings every control in line with `view`. */
  sync(view: AdjustView): void {
    const lookChanged = this.view?.looks !== view.looks
    this.view = view
    if (lookChanged) this.buildLooks(view.looks)
    const { adj } = view
    for (const btn of this.refs.looks.querySelectorAll<HTMLButtonElement>('button')) {
      const on = btn.dataset.look === adj.look
      btn.setAttribute('aria-checked', String(on))
      btn.tabIndex = on ? 0 : -1
    }
    this.refs.adjustLook.textContent = view.looks.find((l) => l.id === adj.look)?.label ?? ''
    for (const key of TONE) {
      this.refs.input(key).value = String(adj[key])
      this.refs.output(key).textContent = formatValue(key, adj[key])
    }
    this.syncWb(view)
    this.refs.rawOnly.hidden = !view.hasRaw
    this.refs.adjustScope.hidden = view.count < 2
    this.refs.adjustScope.textContent = view.count === 2 ? 'Changes apply to both photos.' : `Changes apply to all ${view.count} photos.`
  }

  private syncWb({ adj, asShot }: AdjustView): void {
    const temp = adj.wbTemp ?? asShot?.wbTemp ?? 5500
    const tint = adj.wbTint ?? asShot?.wbTint ?? 0
    setRange(this.refs.input('wbTemp'), rangeIncluding(temp, WB_TEMP_RANGE, WB_TEMP_LIMITS))
    setRange(this.refs.input('wbTint'), rangeIncluding(tint, WB_TINT_RANGE, WB_TINT_LIMITS))
    this.refs.input('wbTemp').value = String(temp)
    this.refs.input('wbTint').value = String(tint)
    const asShotNote = adj.wbTemp === null ? 'As shot · ' : ''
    this.refs.output('wbTemp').textContent = `${asShotNote}${Math.round(temp)} K`
    this.refs.output('wbTint').textContent = formatTint(tint)
  }

  private buildLooks(looks: readonly NativeLook[]): void {
    const buttons = looks.map((look) => {
      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'segment'
      btn.setAttribute('role', 'radio')
      btn.dataset.look = look.id
      btn.textContent = look.label.replace(/ Print$/, '')
      btn.title = look.label
      btn.addEventListener('click', () => this.emit({ look: look.id }, 'look'))
      btn.addEventListener('keydown', (e) => this.arrowKeys(e, looks, look.id))
      return btn
    })
    this.refs.looks.replaceChildren(...buttons)
  }

  /** Radio-group arrow keys. */
  private arrowKeys(e: KeyboardEvent, looks: readonly NativeLook[], current: string): void {
    const step = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1 : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 0
    if (!step) return
    e.preventDefault()
    const i = looks.findIndex((l) => l.id === current)
    const next = looks[(i + step + looks.length) % looks.length]
    this.emit({ look: next.id }, 'look')
    this.refs.looks.querySelector<HTMLButtonElement>(`[data-look="${next.id}"]`)?.focus()
  }
}

function setRange(input: HTMLInputElement, range: SliderRange): void {
  input.min = String(range.min)
  input.max = String(range.max)
  input.step = String(range.step)
}
