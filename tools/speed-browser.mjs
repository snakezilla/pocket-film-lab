// Time preview + full-size export renders in headless browsers on this Mac.
// Needs the built app served at http://127.0.0.1:4318/ (vite preview).
// Real iPhone timing is not measured. (CDP CPU throttling does not reach Web Workers, so it is not used.)
import { writeFileSync } from 'node:fs'
import { chromium, webkit } from '@playwright/test'

const rows = []
async function run(name, type, throttle) {
  const browser = await type.launch({ headless: true })
  const page = await browser.newPage()
  if (throttle) {
    const cdp = await page.context().newCDPSession(page)
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle })
  }
  await page.goto('http://127.0.0.1:4318/')
  await page.locator('#file').setInputFiles('tests/fixtures/rotated.jpg')
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('preview'), null, { timeout: 120000 })
  const preview = await page.locator('#status').textContent()
  const exports = []
  for (let k = 0; k < 3; k++) {
    await page.locator('#export').click()
    await page.waitForFunction(() => document.getElementById('status').textContent.startsWith('Ready'), null, { timeout: 120000 })
    exports.push(Number((await page.locator('#status').textContent()).match(/rendered in (\d+) ms/)[1]))
    await page.locator('#reset').click() // invalidates the export so the button comes back
    await page.waitForFunction(() => !document.getElementById('export').hidden)
  }
  rows.push(`| ${name} | ${preview.match(/in (\d+) ms/)[1]} | ${exports.join(', ')} |`)
  await browser.close()
}
await run('Chromium (Mac)', chromium)
await run('Playwright WebKit (Mac)', webkit)
const text = ['# Render speed (headless browsers on this Mac)', '', `Generated ${new Date().toISOString()}. Input: 4032x3024 JPEG -> preview 960x1280, export 1800x2400. All effects at defaults. Times are the worker render only (not decode/encode).`, '', '| Browser | Preview ms | Export ms (3 runs) |', '|---|---|---|', ...rows, '', 'Not measured: physical iPhone Safari.', ''].join('\n')
writeFileSync('measurements/SPEED.md', text)
console.log(text)
