import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { expect, test, type Page } from '@playwright/test'

const fixture = (name: string) => fileURLToPath(new URL(`../fixtures/${name}`, import.meta.url))

async function open(page: Page, ...names: string[]) {
  await page.locator('#file').setInputFiles(names.map(fixture))
}

/** Waits until every photo has a first preview (or failed). */
async function developed(page: Page) {
  await expect(page.locator('#status')).not.toContainText('Developing', { timeout: 30_000 })
}

interface Pixels {
  width: number
  height: number
  at: number[][]
}

/** Decodes an image URL and reads pixels at fractional positions. */
async function pixelsOf(page: Page, url: string, points: [number, number][]): Promise<Pixels> {
  return page.evaluate(
    async ({ url, points }) => {
      const img = new Image()
      img.src = url
      await img.decode()
      const c = document.createElement('canvas')
      c.width = img.naturalWidth
      c.height = img.naturalHeight
      const ctx = c.getContext('2d')!
      ctx.drawImage(img, 0, 0)
      const at = points.map(([fx, fy]) => Array.from(ctx.getImageData(Math.floor(fx * (c.width - 1)), Math.floor(fy * (c.height - 1)), 1, 1).data))
      return { width: c.width, height: c.height, at }
    },
    { url, points },
  )
}

/** Mean absolute RGB difference of two images, both drawn at `a`'s size. */
async function meanDiff(page: Page, a: string, b: string): Promise<number> {
  return page.evaluate(
    async ({ a, b }) => {
      const load = async (url: string) => {
        const img = new Image()
        img.src = url
        await img.decode()
        return img
      }
      const [ia, ib] = await Promise.all([load(a), load(b)])
      const w = ia.naturalWidth
      const h = ia.naturalHeight
      const read = (img: HTMLImageElement) => {
        const c = document.createElement('canvas')
        c.width = w
        c.height = h
        const ctx = c.getContext('2d')!
        ctx.imageSmoothingQuality = 'high'
        ctx.drawImage(img, 0, 0, w, h)
        return ctx.getImageData(0, 0, w, h).data
      }
      const da = read(ia)
      const db = read(ib)
      let sum = 0
      for (let i = 0; i < da.length; i++) if (i % 4 !== 3) sum += Math.abs(da[i] - db[i])
      return sum / ((da.length / 4) * 3)
    },
    { a, b },
  )
}

const viewSrc = (page: Page) => page.locator('#view').evaluate((el) => (el as HTMLImageElement).src)

/** Holds the photo, returns the URL shown while held (the original), then lets go. */
async function originalUrl(page: Page): Promise<string> {
  const film = await viewSrc(page)
  await page.locator('#stage').dispatchEvent('pointerdown')
  await expect(page.locator('#badge')).toBeVisible()
  await expect.poll(() => viewSrc(page)).not.toBe(film)
  const url = await viewSrc(page)
  await page.locator('#stage').dispatchEvent('pointerup')
  await expect(page.locator('#badge')).toBeHidden()
  await expect.poll(() => viewSrc(page)).toBe(film)
  return url
}

async function setSlider(page: Page, id: string, value: number) {
  await page.locator(`#${id}`).evaluate((el, v) => {
    const input = el as HTMLInputElement
    input.value = String(v)
    input.dispatchEvent(new Event('input', { bubbles: true }))
  }, value)
}

test.beforeEach(async ({ page }) => {
  // Force the download path; the share path is covered by its own test.
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'canShare', { value: undefined, configurable: true })
  })
})

test('first screen is one action: choose photos', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('#pick')).toBeVisible()
  await expect(page.locator('#pick')).toHaveText('Choose Photos')
  await expect(page.locator('#work')).toBeHidden()
  await expect(page.locator('#pick-files')).toBeHidden() // a Files option only exists in the iOS app
  const box = await page.locator('#pick').boundingBox()
  expect(box!.height).toBeGreaterThanOrEqual(44)
})

test('one rotated JPEG develops automatically, compares, and downloads a clean JPEG', async ({ page, baseURL }) => {
  const requests: string[] = []
  page.on('request', (r) => requests.push(r.url()))
  await page.goto('/')
  await open(page, 'rotated.jpg')
  await developed(page)
  await expect(page.locator('#status')).toHaveText('Cine print · 3024 × 4032') // upright size
  await expect(page.locator('#strip')).toBeHidden()
  // Adjustments are tucked away by default.
  await expect(page.locator('#adjust')).not.toHaveAttribute('open', '')
  await expect(page.locator('#strength')).toBeHidden()

  // EXIF orientation 6: stored 4032x3024 landscape displays as a 1280-high portrait.
  const film = await viewSrc(page)
  const px = await pixelsOf(page, film, [[0.05, 0.05], [0.95, 0.05]])
  expect([px.width, px.height]).toEqual([960, 1280])
  const [topLeft, topRight] = px.at
  expect(topRight[0]).toBeGreaterThan(150) // red block, stored top-left, shows top-right
  expect(topRight[2]).toBeLessThan(100)
  expect(topLeft[0]).toBeLessThan(160)

  // Hold to compare: the original, which differs from the film look.
  const original = await originalUrl(page)
  expect(await meanDiff(page, film, original)).toBeGreaterThan(3)

  // All controls off: the film preview matches the original (within JPEG preview error).
  await page.locator('#adjust summary').click()
  await expect(page.locator('#strength')).toBeVisible()
  await expect(page.locator('#adjust-scope')).toBeHidden() // one photo: no "applies to all"
  for (const id of ['strength', 'grain', 'halation', 'exposure']) await setSlider(page, id, 0)
  await expect.poll(async () => meanDiff(page, await viewSrc(page), original), { timeout: 20_000 }).toBeLessThan(2.5)

  // Reset brings the look back, then one button downloads the full-size JPEG.
  await page.locator('#reset').click()
  await expect.poll(async () => meanDiff(page, await viewSrc(page), original), { timeout: 20_000 }).toBeGreaterThan(3)
  await expect(page.locator('#save')).toHaveText('Download')
  const downloadPromise = page.waitForEvent('download')
  await page.locator('#save').click()
  const download = await downloadPromise
  const path = test.info().outputPath('export.jpg')
  await download.saveAs(path)
  expect(download.suggestedFilename()).toMatch(/^film-\d{8}-\d{6}\.jpg$/)
  await expect(page.locator('#status')).toHaveText('Downloaded 1 photo.')
  await expect(page.locator('#save')).toBeDisabled()

  const bytes = readFileSync(path)
  expect([bytes[0], bytes[1]]).toEqual([0xff, 0xd8])
  const tags = JSON.parse(execFileSync('exiftool', ['-j', '-G', path]).toString())[0]
  expect(tags['File:ImageWidth']).toBe(1800)
  expect(tags['File:ImageHeight']).toBe(2400)
  for (const key of Object.keys(tags)) expect(key).not.toMatch(/^(EXIF|GPS|MakerNotes|XMP|IPTC|Photoshop):/)
  expect(JSON.stringify(tags)).not.toContain('TestCam')
  const out = JSON.parse(
    execFileSync('python3', ['-I', '-c', `import json,sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB');w,h=im.size
print(json.dumps([im.getpixel((int(w*.95),int(h*.05)))]))`, path]).toString(),
  )
  expect(out[0][0]).toBeGreaterThan(150)
  expect(out[0][2]).toBeLessThan(100)

  // A change re-enables saving.
  await page.locator('#looks [data-look="portra"]').click()
  await expect(page.locator('#save')).toBeEnabled()

  // Privacy: every request stayed on this origin.
  const origin = new URL(baseURL!).origin
  for (const url of requests) expect(url.startsWith(origin) || url.startsWith('blob:') || url.startsWith('data:')).toBe(true)
})

test('a batch develops in a strip, adjusts together, and downloads every photo', async ({ page }) => {
  await page.goto('/')
  await open(page, 'rotated.jpg', 'small.png', 'broken.jpg')
  await expect(page.locator('#strip .thumb')).toHaveCount(3)
  await developed(page)
  await expect(page.locator('#status')).toHaveText('2 photos · Cine print · 1 couldn’t be read')
  await expect(page.locator('#strip .thumb[data-state="failed"]')).toHaveCount(1)
  await expect(page.locator('#save')).toHaveText('Download 2')

  // Tapping a thumbnail shows that photo.
  await page.locator('#strip .thumb').nth(1).click()
  await expect(page.locator('#strip .thumb').nth(1)).toHaveAttribute('aria-current', 'true')
  await expect.poll(async () => (await pixelsOf(page, await viewSrc(page), [])).width).toBe(640)

  // One look change re-develops every photo.
  await page.locator('#adjust summary').click()
  await expect(page.locator('#adjust-scope')).toHaveText('Changes apply to all 3 photos.')
  const before = await page.locator('#strip .thumb img').first().getAttribute('src')
  await page.locator('#looks [data-look="portra"]').click()
  await expect.poll(() => page.locator('#strip .thumb img').first().getAttribute('src'), { timeout: 20_000 }).not.toBe(before)
  await expect(page.locator('#adjust-look')).toHaveText('Portra')

  const names: string[] = []
  page.on('download', (d) => names.push(d.suggestedFilename()))
  await page.locator('#save').click()
  await expect(page.locator('#status')).toHaveText('Downloaded 2 photos.', { timeout: 60_000 })
  expect(names).toHaveLength(2)
  expect(names[0]).toMatch(/^film-\d{8}-\d{6}-01\.jpg$/)
  expect(names[1]).toMatch(/^film-\d{8}-\d{6}-02\.jpg$/)
})

test('saving a batch can be stopped', async ({ page }) => {
  await page.goto('/')
  await open(page, 'rotated.jpg', 'small.png', 'rotated.jpg')
  await developed(page)
  await page.evaluate(() => {
    ;(document.getElementById('save') as HTMLButtonElement).click()
    ;(document.getElementById('stop') as HTMLButtonElement).click()
  })
  await expect(page.locator('#status')).toHaveText('Stopped. Downloaded 0 of 3.', { timeout: 30_000 })
  await expect(page.locator('#save')).toBeEnabled()
  await expect(page.locator('#stop')).toBeHidden()
})

test('choosing again replaces the photos', async ({ page }) => {
  await page.goto('/')
  await open(page, 'small.png')
  await developed(page)
  await open(page, 'rotated.jpg', 'small.png')
  await expect(page.locator('#strip .thumb')).toHaveCount(2)
  await developed(page)
  await open(page, 'small.png')
  await expect(page.locator('#strip')).toBeHidden()
  await developed(page)
  await expect.poll(async () => (await pixelsOf(page, await viewSrc(page), [])).width).toBe(640)
})

test('RAW, broken and unsupported files fail with clear errors', async ({ page }) => {
  await page.goto('/')
  await open(page, 'camera.dng')
  await expect(page.locator('#status')).toContainText('RAW files need the Film Lab iOS app')
  await expect(page.locator('#status')).toHaveClass(/error/)
  await expect(page.locator('#save')).toBeDisabled()
  await open(page, 'notes.txt')
  await expect(page.locator('#status')).toContainText('Unsupported file type')
  await open(page, 'broken.jpg')
  await expect(page.locator('#status')).toContainText('Could not read this image', { timeout: 15_000 })
})

test('HEIC: develops or fails with a HEIC-specific message', async ({ page, browserName }) => {
  await page.goto('/')
  await open(page, 'small.heic')
  const status = page.locator('#status')
  await expect(status).toContainText(/Cine print|could not decode this HEIC/, { timeout: 20_000 })
  test.info().annotations.push({ type: 'heic', description: `${browserName}: ${await status.textContent()}` })
})

test('one photo goes to the share sheet when the browser has one', async ({ page }) => {
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
  await developed(page)
  await page.locator('#save').click()
  await expect(page.locator('#status')).toHaveText('Shared.')
  const shared = await page.evaluate(() => (window as unknown as { __shared: unknown[] }).__shared)
  expect(shared).toEqual([expect.objectContaining({ type: 'image/jpeg' })])
})
