import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { COPY } from '../../src/copy'
import { LOOKS } from '../../src/looks'

/**
 * App Store guideline 5.2.1: no film-stock trademarks anywhere a person can see them.
 * Internal ids, LUT file names, comments and docs may keep the stock names.
 * The built dist/ is checked by tests/e2e/store-names.spec.ts.
 */

const root = join(__dirname, '../..')
const read = (p: string) => readFileSync(join(root, p), 'utf8')

/** Trademarks and stock codes. "portrait" is a plain word, so it is allowed. */
export const TRADEMARKS = /kodak|portra(?!it)|vision ?3|\b250d\b|\b500t\b|2383|endura/i
/** Internal identifiers that never reach the screen. */
export const INTERNAL_IDS = ['vision3-250d-2383', 'vision3-500t-2383', 'portra400-2383', 'file:"portra"', "file: 'portra'"]
/** Words the owner wants out of the app's wording ("make it very non-technical"). */
const JARGON = /\b(raw|proraw|heic|jpe?g|png|scene-linear|white balance|tint|halation|decode|export|metadata|kelvin|EV)\b/i

const strip = (text: string) => INTERNAL_IDS.reduce((t, id) => t.split(id).join(''), text)

/** Visible text and accessible names in an HTML page (no tags, ids, classes or scripts). */
function visibleHtml(html: string): string {
  const attrs = [...html.matchAll(/\s(?:alt|title|aria-label|placeholder|content)="([^"]*)"/g)].map((m) => m[1])
  const body = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ')
  return [body, ...attrs].join('\n')
}

/** Every user-visible string in COPY, with sample numbers filled in. */
function copyStrings(): string[] {
  return Object.values(COPY).map((v) => (typeof v === 'function' ? (v as (...a: number[]) => string)(2, 5) : v))
}

/** Swift string literals, minus internal ids (look ids, file names, keys). */
function swiftStrings(): string[] {
  const dir = join(root, 'ios/PocketFilmLab')
  const files = readdirSync(dir, { recursive: true }).map(String).filter((f) => f.endsWith('.swift'))
  return files.flatMap((f) => [...readFileSync(join(dir, f), 'utf8').matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => strip(m[1])))
}

describe('no film-stock trademarks where people can see them', () => {
  it('look names (web and native)', () => {
    for (const look of LOOKS) expect(look.label).not.toMatch(TRADEMARKS)
    const lutDir = 'ios/PocketFilmLab/Resources/LUTs'
    const labels = readdirSync(join(root, lutDir))
      .filter((f) => f.endsWith('.json'))
      .map((f) => JSON.parse(read(`${lutDir}/${f}`)).label as string)
    expect(labels.sort()).toEqual(['Daylight', 'Lamplight', 'Portrait'])
    expect(LOOKS.map((l) => l.label)).toEqual(['Lamplight', 'Portrait'])
  })

  it('the page, the app’s messages and the Info.plist strings', () => {
    const texts = [visibleHtml(read('index.html')), ...copyStrings(), ...swiftStrings()]
    const info = read('ios/project.yml').split('\n').filter((l) => /INFOPLIST_KEY_(CFBundleDisplayName|NS\w+UsageDescription)/.test(l))
    for (const text of [...texts, ...info]) expect(text).not.toMatch(TRADEMARKS)
  })

  it('the app is called Silver Hour, not Film Lab', () => {
    expect(read('ios/project.yml')).toContain('INFOPLIST_KEY_CFBundleDisplayName: Silver Hour')
    expect(read('index.html')).toContain('<title>Silver Hour</title>')
    for (const text of [visibleHtml(read('index.html')), ...copyStrings(), ...swiftStrings()]) {
      expect(text).not.toMatch(/film lab/i)
    }
  })
})

describe('plain words', () => {
  it('no jargon on the page or in the app’s messages', () => {
    for (const text of [visibleHtml(read('index.html')).replace(/Spectral Film LUT/g, ''), ...copyStrings()]) {
      expect(text).not.toMatch(JARGON)
    }
  })
})
