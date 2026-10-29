import './style.css'
import { DEFAULT_RECIPE, type Recipe } from './engine/film'
import { decodePhoto, type DecodedPhoto } from './decode'
import { encodeJpeg, saveJpeg } from './export'
import { checkFile, exportName } from './files'
import { LOOKS, loadLutBuffer, type Look } from './looks'
import { CancelledError, Processor } from './processor'

type SliderKey = keyof Recipe

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T
const ui = {
  file: $<HTMLInputElement>('file'),
  empty: $('empty'),
  result: $<HTMLCanvasElement>('result'),
  original: $<HTMLCanvasElement>('original'),
  badge: $('badge'),
  status: $('status'),
  controls: $('controls'),
  looks: $('looks'),
  compare: $<HTMLButtonElement>('compare'),
  reset: $<HTMLButtonElement>('reset'),
  exportBtn: $<HTMLButtonElement>('export'),
  cancel: $<HTMLButtonElement>('cancel'),
  save: $<HTMLButtonElement>('save'),
}
const SLIDERS: readonly SliderKey[] = ['strength', 'exposure', 'grain', 'halo']

interface State {
  readonly photo: DecodedPhoto | null
  readonly recipe: Recipe
  readonly look: Look
  readonly exported: Blob | null
  readonly importToken: number
}

let state: State = { photo: null, recipe: DEFAULT_RECIPE, look: LOOKS[0], exported: null, importToken: 0 }
const previewer = new Processor()
const exporter = new Processor()
let previewQueued = false
let exportToken = 0

function setState(patch: Partial<State>): void {
  state = { ...state, ...patch }
}

function say(message: string, isError = false): void {
  ui.status.textContent = message
  ui.status.classList.toggle('error', isError)
}

function paint(canvas: HTMLCanvasElement, image: ImageData): void {
  canvas.width = image.width
  canvas.height = image.height
  canvas.getContext('2d')?.putImageData(image, 0, 0)
}

function formatValue(key: SliderKey, v: number): string {
  if (key === 'exposure') return `${v > 0 ? '+' : ''}${v.toFixed(2)} EV`
  return `${Math.round(v * 100)}%`
}

function syncControls(): void {
  for (const key of SLIDERS) {
    const input = $<HTMLInputElement>(key)
    input.value = String(state.recipe[key])
    $<HTMLOutputElement>(`${key}-v`).textContent = formatValue(key, state.recipe[key])
  }
  for (const btn of ui.looks.querySelectorAll('button')) {
    btn.setAttribute('aria-checked', String(btn.dataset.look === state.look.id))
  }
}

function cancelExport(): void {
  exportToken++ // also stops an export that is still loading its LUT
  exporter.cancel()
}

function invalidateExport(): void {
  cancelExport()
  setState({ exported: null })
  ui.save.hidden = true
  ui.exportBtn.hidden = false
  ui.cancel.hidden = true
}

/** Render the preview. While a render runs, later changes coalesce into one follow-up render. */
async function renderPreview(): Promise<void> {
  const photo = state.photo
  if (!photo) return
  if (previewer.busy) {
    previewQueued = true
    return
  }
  const token = state.importToken
  try {
    const lut = await loadLutBuffer(state.look)
    const { image, ms } = await previewer.render(photo.preview, state.recipe, lut, state.look.size)
    if (token !== state.importToken) return
    paint(ui.result, image)
    say(`${state.look.label} · preview ${image.width}×${image.height} in ${Math.round(ms)} ms`)
  } catch (error) {
    if (!(error instanceof CancelledError)) say(error instanceof Error ? error.message : String(error), true)
  }
  if (previewQueued && token === state.importToken) {
    previewQueued = false
    void renderPreview()
  }
}

async function onFile(file: File): Promise<void> {
  const check = checkFile(file.name, file.type, file.size)
  if (check.kind === 'rejected') {
    say(check.reason, true)
    return
  }
  const token = state.importToken + 1
  setState({ importToken: token })
  previewer.cancel()
  previewQueued = false
  invalidateExport()
  say(check.kind === 'heic' ? 'Reading HEIC (works only if this browser decodes HEIC)…' : 'Reading photo…')
  try {
    const photo = await decodePhoto(file, check)
    if (token !== state.importToken) return // a newer import replaced this one
    setState({ photo })
    paint(ui.original, photo.preview)
    ui.empty.hidden = true
    ui.result.hidden = false
    ui.controls.hidden = false
    await renderPreview()
  } catch (error) {
    if (token === state.importToken) say(error instanceof Error ? error.message : String(error), true)
  }
}

async function onExport(): Promise<void> {
  const photo = state.photo
  if (!photo) return
  const token = ++exportToken
  const stillWanted = () => {
    if (token !== exportToken) throw new CancelledError()
  }
  ui.exportBtn.hidden = true
  ui.cancel.hidden = false
  say(`Rendering ${photo.work.width}×${photo.work.height}…`)
  try {
    const lut = await loadLutBuffer(state.look)
    stillWanted()
    const { image, ms } = await exporter.render(photo.work, state.recipe, lut, state.look.size)
    stillWanted()
    const blob = await encodeJpeg(image)
    stillWanted()
    setState({ exported: blob })
    ui.cancel.hidden = true
    ui.save.hidden = false
    say(`Ready: ${image.width}×${image.height} JPEG, ${(blob.size / 1048576).toFixed(1)} MB, rendered in ${Math.round(ms)} ms. No metadata kept.`)
  } catch (error) {
    if (token !== exportToken && !(error instanceof CancelledError)) return // superseded
    ui.cancel.hidden = true
    ui.exportBtn.hidden = false
    say(error instanceof CancelledError ? 'Cancelled.' : error instanceof Error ? error.message : String(error), !(error instanceof CancelledError))
  }
}

async function onSave(): Promise<void> {
  if (!state.exported) return
  const outcome = await saveJpeg(state.exported, exportName(new Date()))
  say(outcome === 'shared' ? 'Shared.' : outcome === 'downloaded' ? 'Downloaded.' : 'Share sheet closed; nothing saved.')
}

function showOriginal(on: boolean): void {
  if (!state.photo) return
  ui.original.hidden = !on
  ui.result.hidden = on
  ui.badge.hidden = !on
  ui.compare.setAttribute('aria-pressed', String(on))
}

function buildLookButtons(): void {
  for (const look of LOOKS) {
    const btn = document.createElement('button')
    btn.type = 'button'
    btn.className = 'btn'
    btn.setAttribute('role', 'radio')
    btn.dataset.look = look.id
    btn.textContent = look.label
    btn.title = look.note
    btn.addEventListener('click', () => {
      setState({ look })
      syncControls()
      invalidateExport()
      void renderPreview()
    })
    ui.looks.append(btn)
  }
}

function wire(): void {
  ui.file.addEventListener('change', () => {
    const file = ui.file.files?.[0]
    ui.file.value = '' // allow picking the same file again
    if (file) void onFile(file)
  })
  for (const key of SLIDERS) {
    $<HTMLInputElement>(key).addEventListener('input', (event) => {
      const value = Number((event.target as HTMLInputElement).value)
      setState({ recipe: { ...state.recipe, [key]: value } })
      syncControls()
      invalidateExport()
      void renderPreview()
    })
  }
  ui.compare.addEventListener('pointerdown', () => showOriginal(true))
  for (const ev of ['pointerup', 'pointerleave', 'pointercancel'] as const) {
    ui.compare.addEventListener(ev, () => showOriginal(false))
  }
  ui.compare.addEventListener('keydown', (e) => e.key === ' ' && showOriginal(true))
  ui.compare.addEventListener('keyup', (e) => e.key === ' ' && showOriginal(false))
  ui.compare.addEventListener('contextmenu', (e) => e.preventDefault())
  ui.reset.addEventListener('click', () => {
    setState({ recipe: DEFAULT_RECIPE })
    syncControls()
    invalidateExport()
    void renderPreview()
  })
  ui.exportBtn.addEventListener('click', () => void onExport())
  ui.cancel.addEventListener('click', () => cancelExport())
  ui.save.addEventListener('click', () => void onSave())
}

buildLookButtons()
syncControls()
wire()
