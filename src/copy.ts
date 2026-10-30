import { plural } from './plural'

/**
 * Every sentence the app shows people, in one place: plain, warm, short, no jargon.
 * Static labels (buttons, slider names, About) live in index.html.
 */

export const COPY = {
  oops: 'That one didn’t work. Try another photo.',
  appOnly: 'This kind of photo only opens in the Silver Hour app.',
  notAPhoto: 'That file isn’t a photo we can open.',
  empty: 'That file is empty.',
  tooBig: (mb: number, limit: number) => `That photo is too big (${mb} MB). Try one under ${limit} MB.`,
  browserCantOpen: 'This browser can’t open that photo. Try a different one.',
  tooBigForPhone: 'That photo is too big for this phone. Try a smaller one.',
  noLongerOpen: 'That photo isn’t open anymore. Choose it again.',
  developing: (n: number, total: number) => `Developing ${n} of ${total}…`,
  oneLook: (look: string) => `${look} look`,
  batchLook: (n: number, look: string) => `${plural(n, 'photo')}, ${look} look`,
  someFailed: (n: number) => `${n === 1 ? '1 didn’t' : `${n} didn’t`} work.`,
  keptFirst: (limit: number, left: number) => `We kept the first ${limit}. ${left} more ${left === 1 ? 'was' : 'were'} left out.`,
  skipped: (n: number) => `${plural(n, 'photo')} didn’t open.`,
  appliesToAll: (n: number) => (n === 2 ? 'Changes apply to both photos.' : `Changes apply to all ${n} photos.`),
  asTaken: 'As taken',
  saveOne: 'Save to Photos',
  saveMany: (n: number) => `Save ${n} to Photos`,
  saving: 'Saving…',
  savingN: (n: number, total: number) => `Saving ${n} of ${total}…`,
  stopping: 'Stopping…',
  savedButton: 'Saved to Photos',
  download: 'Download',
  downloadMany: (n: number) => `Download ${n}`,
  downloadedButton: 'Downloaded',
  savedOne: 'Saved to your Photos ✓',
  savedMany: (n: number) => `${n} photos saved to your Photos ✓`,
  savedSome: (n: number, total: number) => `${n} of ${total} saved.`,
  failedSome: (n: number) => (n === 1 ? 'One didn’t work, so try it again.' : `${n} didn’t work, so try those again.`),
  stopped: (n: number, total: number) => `Stopped. ${n} of ${total} saved.`,
  downloaded: (n: number) => `Downloaded ${plural(n, 'photo')}.`,
  downloadedSome: (n: number, total: number) => `Downloaded ${n} of ${total}.`,
  stoppedDownloads: (n: number, total: number) => `Stopped. Downloaded ${n} of ${total}.`,
  denied: 'Silver Hour needs your OK to add photos. Turn it on in Settings.',
  shared: 'Shared.',
  notSaved: 'Not saved.',
  gettingReady: 'Getting it ready…',
} as const

/** An error whose message is already written for people. */
export class FriendlyError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'FriendlyError'
  }
}

/** Messages the native side writes for people (RawBridge, PhotoSaver, FallbackImage). */
const NATIVE_FRIENDLY = new Set<string>([
  COPY.oops,
  COPY.noLongerOpen,
  'Those didn’t open. Try other photos.',
  'That photo was closed before it finished saving.',
  'Silver Hour needs your OK to add photos. Turn it on in Settings.',
  'Photos didn’t take that one. Try again.',
])

/** What to show for an error: its own words if they were written for people, else a friendly default. */
export function friendlyMessage(error: unknown): string {
  if (error instanceof FriendlyError) return error.message
  const message = error instanceof Error ? error.message : String(error)
  return NATIVE_FRIENDLY.has(message) ? message : COPY.oops
}
