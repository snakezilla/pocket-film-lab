// Headless QA of the work view: batch loaded, Adjust closed/open, light/dark, 320/390.
import { chromium, webkit } from '@playwright/test'
import { readFileSync, mkdirSync } from 'node:fs'
const [, , url, outDir, checksPath, fixtures] = process.argv
mkdirSync(outDir, { recursive: true })
const checks = readFileSync(checksPath, 'utf8')
const report = []
for (const [engineName, engine] of [['webkit', webkit]]) {
  const browser = await engine.launch({ headless: true })
  for (const scheme of ['dark', 'light']) for (const width of [320, 390]) for (const adjust of [false, true]) {
    const ctx = await browser.newContext({ viewport: { width, height: 844 }, deviceScaleFactor: 2, colorScheme: scheme, hasTouch: true, isMobile: true })
    const page = await ctx.newPage()
    const errors = []
    page.on('pageerror', (e) => errors.push(String(e)))
    await page.goto(url)
    await page.locator('#file').setInputFiles(['rotated.jpg', 'small.png', 'broken.jpg', 'rotated.jpg'].map((f) => `${fixtures}/${f}`))
    await page.waitForFunction(() => !document.getElementById('status').textContent.includes('Developing'), null, { timeout: 30000 })
    if (adjust) await page.evaluate(() => { document.getElementById('adjust').open = true })
    await page.waitForTimeout(300)
    const name = `web-${scheme}-${width}${adjust ? '-adjust' : ''}`
    await page.screenshot({ path: `${outDir}/${name}.png`, fullPage: true })
    const res = JSON.parse(await page.evaluate(checks))
    report.push({ name, errors, findings: (res.findings || []).filter((f) => !['meta', 'img-size'].includes(f.check)) })
    await ctx.close()
  }
  await browser.close()
}
console.log(JSON.stringify(report, null, 1))
