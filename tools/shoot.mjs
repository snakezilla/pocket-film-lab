// Headless screenshots of the built app (run while `vite preview --port 4318` is up).
import { chromium, webkit, devices } from '@playwright/test'
const fixture = process.argv[2]
const out = process.argv[3]
for (const [name, type] of [['chromium', chromium], ['webkit', webkit]]) {
  const browser = await type.launch({ headless: true })
  const page = await browser.newPage({ ...devices['iPhone 13'], ...(name === 'chromium' ? { isMobile: false, hasTouch: true } : {}) })
  await page.goto('http://127.0.0.1:4318/')
  await page.locator('#file').setInputFiles('tests/fixtures/small.heic')
  await page.waitForTimeout(1500)
  console.log(name, 'HEIC ->', await page.locator('#status').textContent())
  await page.locator('#file').setInputFiles(fixture)
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('preview'), null, { timeout: 30000 })
  console.log(name, '->', await page.locator('#status').textContent())
  await page.screenshot({ path: `${out}/ui-${name}.png`, fullPage: true })
  await browser.close()
}
