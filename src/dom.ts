/** Element references for index.html. */

const $ = <T extends HTMLElement>(id: string): T => {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id} in index.html`)
  return el as T
}

export function findRefs() {
  return {
    file: $<HTMLInputElement>('file'),
    repick: $<HTMLButtonElement>('repick'),
    welcome: $('welcome'),
    pick: $<HTMLButtonElement>('pick'),
    pickFiles: $<HTMLButtonElement>('pick-files'),
    pickNote: $('pick-note'),
    work: $('work'),
    stage: $('stage'),
    view: $<HTMLImageElement>('view'),
    badge: $('badge'),
    spinner: $('spinner'),
    compare: $<HTMLButtonElement>('compare'),
    strip: $('strip'),
    progress: $('progress'),
    status: $('status'),
    adjust: $<HTMLDetailsElement>('adjust'),
    adjustLook: $('adjust-look'),
    adjustScope: $('adjust-scope'),
    looks: $('looks'),
    rawOnly: $('raw-only'),
    reset: $<HTMLButtonElement>('reset'),
    save: $<HTMLButtonElement>('save'),
    saveLabel: $('save-label'),
    share: $<HTMLButtonElement>('share'),
    stop: $<HTMLButtonElement>('stop'),
    denied: $('denied'),
    openSettings: $<HTMLButtonElement>('open-settings'),
    input: (id: string) => $<HTMLInputElement>(id),
    output: (id: string) => $<HTMLOutputElement>(`${id}-v`),
  }
}

export type Refs = ReturnType<typeof findRefs>
