import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { expect, test } from '@playwright/test'

/**
 * App Store guideline 5.2.1: the built app (dist/, bundled into the iOS app) carries no
 * film-stock trademarks except internal ids. Playwright's webServer builds dist/ first.
 */
const dist = fileURLToPath(new URL('../../dist', import.meta.url))
const TRADEMARKS = /kodak|portra(?!it)|vision ?3|\b250d\b|\b500t\b|2383|endura/i
const INTERNAL_IDS = ['vision3-250d-2383', 'vision3-500t-2383', 'portra400-2383', 'file:"portra"']
const TEXT = /\.(html|js|css|json|txt|svg|webmanifest)$/

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    return statSync(path).isDirectory() ? files(path) : [path]
  })
}

test('the built app shows no film-stock trademarks', ({ browserName }) => {
  test.skip(browserName !== 'chromium', 'file check; once is enough')
  const all = files(dist)
  expect(all.some((f) => f.endsWith('index.html'))).toBe(true)
  for (const file of all.filter((f) => TEXT.test(f))) {
    const text = INTERNAL_IDS.reduce((t, id) => t.split(id).join(''), readFileSync(file, 'utf8'))
    const hit = text.match(new RegExp(`.{0,40}(?:${TRADEMARKS.source}).{0,40}`, 'i'))
    expect(hit?.[0] ?? null, file).toBeNull()
  }
  // Stock-named LUT metadata stays out of the shipped app (tools/lut-meta instead).
  expect(all.filter((f) => f.endsWith('.json'))).toEqual([])
})
