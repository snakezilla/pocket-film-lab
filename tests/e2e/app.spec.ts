import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { expect, test, type Page } from '@playwright/test'

const fixture = (name: string) => fileURLToPath(new URL(`../fixtures/${name}`, import.meta.url))

interface CanvasInfo {
  width: number
  height: number
  hidden: boolean
  at: (number[])[]
  meanAbsDiff?: number
}

/** Read real pixels from a canvas at fractional positions. */
async function canvasInfo(page: Page, id: string, points: [number, number][]): Promise<CanvasInfo> {
  return page.evaluate(
    ({ id, points }) => {
      const c = document.getElementById(id) as HTMLCanvasElement
      const ctx = c.getContext('2d')!
      const at = points.map(([fx, fy]) => Array.from(ctx.getImageData(Math.floor(fx * (c.width - 1)), Math.floor(fy * (c.height - 1)), 1, 1).data))
      return { width: c.width, height: c.height, hidden: c.hidden, at }
    },
    { id, points },
  )
}

async function meanDiff(page: Page): Promise<number> {
  return page.evaluate(() => {
    const read = (id: string) => {
      const c = document.getElementById(id) as HTMLCanvasElement
      return c.getContext('2d')!.getImageData(0, 0, c.width, c.height).data
    }
    const a = read('result')
    const b = read('original')
    let sum = 0
    for (let i = 0; i < a.length; i++) if (i % 4 !== 3) sum += Math.abs(a[i] - b[i])
    return sum / ((a.length / 4) * 3)
  })
}

async function setSlider(page: Page, id: string, value: number) {
  await page.locator(`#${id}`).evaluate((el, v) => {
    const input = el as HTMLInputElement
    input.value = String(v)
    input.dispatchEvent(new Event('input', { bubbles: true }))
  }, value)
}

async function open(page: Page, name: string) {
  await page.locator('#file').setInputFiles(fixture(name))
}

test.beforeEach(async ({ page }) => {
  // Force the download path; the share path is covered by its own test.
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'canShare', { value: undefined, configurable: true })
  })
})

test('opens a rotated JPEG, renders film pixels, compares, exports a clean JPEG', async ({ page, baseURL }) => {
  const requests: string[] = []
  page.on('request', (r) => requests.push(r.url()))
  await page.goto('/')
  await open(page, 'rotated.jpg')
  await expect(page.locator('#status')).toContainText('preview', { timeout: 30_000 })

  // EXIF orientation 6: stored 4032x3024 landscape displays as 1280-high portrait.
  const original = await canvasInfo(page, 'original', [[0.05, 0.05], [0.95, 0.05]])
  expect([original.width, original.height]).toEqual([960, 1280])
  // The red block (stored top-left) must appear top-right after rotation.
  const [topLeft, topRight] = original.at
  expect(topRight[0]).toBeGreaterThan(180)
  expect(topRight[2]).toBeLessThan(80)
  expect(topLeft[0]).toBeLessThan(140)

  const filmDiff = await meanDiff(page)
  expect(filmDiff).toBeGreaterThan(3)

  // Hold-to-compare shows the original canvas.
  await page.locator('#compare').dispatchEvent('pointerdown')
  expect((await canvasInfo(page, 'original', [])).hidden).toBe(false)
  expect((await canvasInfo(page, 'result', [])).hidden).toBe(true)
  await page.locator('#compare').dispatchEvent('pointerup')
  expect((await canvasInfo(page, 'result', [])).hidden).toBe(false)

  // All controls off -> result equals original pixels.
  for (const id of ['strength', 'grain', 'halo', 'exposure']) await setSlider(page, id, 0)
  await expect.poll(() => meanDiff(page), { timeout: 20_000 }).toBeLessThan(0.01)

  // Back to a look and export at full working size.
  await page.locator('#reset').click()
  await expect.poll(() => meanDiff(page), { timeout: 20_000 }).toBeGreaterThan(3)
  await page.locator('#export').click()
  await expect(page.locator('#status')).toContainText('Ready', { timeout: 60_000 })
  const downloadPromise = page.waitForEvent('download')
  await page.locator('#save').click()
  const download = await downloadPromise
  const path = test.info().outputPath('export.jpg')
  await download.saveAs(path)
  expect(download.suggestedFilename()).toMatch(/^film-\d{8}-\d{6}\.jpg$/)

  const bytes = readFileSync(path)
  expect(bytes[0]).toBe(0xff)
  expect(bytes[1]).toBe(0xd8)
  const tags = JSON.parse(execFileSync('exiftool', ['-j', '-G', path]).toString())[0]
  expect(tags['File:ImageWidth']).toBe(1800)
  expect(tags['File:ImageHeight']).toBe(2400)
  for (const key of Object.keys(tags)) expect(key).not.toMatch(/^(EXIF|GPS|MakerNotes|XMP|IPTC|Photoshop):/)
  expect(JSON.stringify(tags)).not.toContain('TestCam')

  // Export pixels: rotated orientation preserved (red top-right) and film colour applied.
  const px = JSON.parse(
    execFileSync('python3', ['-I', '-c', `import json,sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB');w,h=im.size
print(json.dumps([im.getpixel((int(w*.95),int(h*.05))),im.getpixel((int(w*.05),int(h*.05)))]))`, path]).toString(),
  )
  expect(px[0][0]).toBeGreaterThan(150)
  expect(px[0][2]).toBeLessThan(100)

  // Privacy: every request stayed on this origin.
  const origin = new URL(baseURL!).origin
  for (const url of requests) expect(url.startsWith(origin) || url.startsWith('blob:') || url.startsWith('data:')).toBe(true)
})

test('re-importing the same file works and replaces the photo', async ({ page }) => {
  await page.goto('/')
  await open(page, 'small.png')
  await expect(page.locator('#status')).toContainText('preview', { timeout: 30_000 })
  await open(page, 'rotated.jpg')
  await expect.poll(async () => (await canvasInfo(page, 'original', [])).height, { timeout: 30_000 }).toBe(1280)
  await open(page, 'rotated.jpg')
  await expect(page.locator('#status')).toContainText('preview', { timeout: 30_000 })
  await open(page, 'small.png')
  await expect.poll(async () => (await canvasInfo(page, 'original', [])).width, { timeout: 30_000 }).toBe(640)
})

test('export can be cancelled', async ({ page }) => {
  await page.goto('/')
  await open(page, 'rotated.jpg')
  await expect(page.locator('#status')).toContainText('preview', { timeout: 30_000 })
  // Cancel in the same task as the click, so it lands while the export is starting.
  await page.evaluate(() => {
    ;(document.getElementById('export') as HTMLButtonElement).click()
    ;(document.getElementById('cancel') as HTMLButtonElement).click()
  })
  await expect(page.locator('#status')).toHaveText('Cancelled.')
  await expect(page.locator('#export')).toBeVisible()
  await expect(page.locator('#save')).toBeHidden()
})

test('rejects RAW, broken and unsupported files with clear errors', async ({ page }) => {
  await page.goto('/')
  await open(page, 'camera.dng')
  await expect(page.locator('#status')).toContainText('RAW files are not supported')
  await open(page, 'notes.txt')
  await expect(page.locator('#status')).toContainText('Unsupported file type')
  await open(page, 'broken.jpg')
  await expect(page.locator('#status')).toContainText('Could not read this image', { timeout: 15_000 })
  await expect(page.locator('#status')).toHaveClass(/error/)
})

test('HEIC: decodes or fails with a HEIC-specific message', async ({ page, browserName }) => {
  await page.goto('/')
  await open(page, 'small.heic')
  const status = page.locator('#status')
  await expect(status).toContainText(/preview|could not decode this HEIC/, { timeout: 20_000 })
  test.info().annotations.push({ type: 'heic', description: `${browserName}: ${await status.textContent()}` })
})

test('share path hands a JPEG file to navigator.share', async ({ page }) => {
  await page.addInitScript(() => {
    const shared: { name: string; type: string; size: number }[] = []
    ;(window as unknown as { __shared: typeof shared }).__shared = shared
    Object.defineProperty(navigator, 'canShare', { value: () => true, configurable: true })
    Object.defineProperty(navigator, 'share', {
      value: async (data: { files: File[] }) => {
        for (const f of data.files) shared.push({ name: f.name, type: f.type, size: f.size })
      },
      configurable: true,
    })
  })
  await page.goto('/')
  await open(page, 'small.png')
  await expect(page.locator('#status')).toContainText('preview', { timeout: 30_000 })
  await page.locator('#export').click()
  await expect(page.locator('#status')).toContainText('Ready', { timeout: 30_000 })
  await page.locator('#save').click()
  await expect(page.locator('#status')).toHaveText('Shared.')
  const shared = await page.evaluate(() => (window as unknown as { __shared: unknown[] }).__shared)
  expect(shared).toEqual([expect.objectContaining({ type: 'image/jpeg' })])
})
