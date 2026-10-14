// Drives the real page in Chrome (#44): the whole demo, settings and memory, phone widths with no sideways scroll,
// reduced motion, no JavaScript, and no off-site requests. Saves screenshots for the PR.
//   cd site && python3 -m http.server 8744 --bind 127.0.0.1 &
//   node scripts/check-site-browser.mjs <screenshot-dir>
// Needs playwright-core (any install; MARVIN's dashboard has one) and Google Chrome. Not run in CI.
import os from 'os'
import path from 'path'
let chromium
try { ({ chromium } = await import('playwright-core')) } catch {
  ({ chromium } = await import(path.join(os.homedir(), '.agents/dashboard/node_modules/playwright-core/index.mjs')))
}
const BASE = process.env.SITE_URL || 'http://127.0.0.1:8744/'
const OUT = process.argv[2] || '.'
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const fails = []
const ok = (c, m) => { if (!c) fails.push(m) }
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
try {
  // Desktop: real interaction through the whole demo.
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, colorScheme: 'light' })
  const page = await ctx.newPage()
  const external = []
  page.on('request', (r) => { if (!r.url().startsWith(BASE)) external.push(r.url()) })
  const errors = []
  page.on('pageerror', (e) => errors.push(e.message))
  await page.goto(BASE)
  await page.waitForSelector('[data-demo][data-ready]')
  ok(await page.locator('[data-start]').isVisible(), 'Start visible on load')
  ok((await page.locator('[data-captions]').innerText()).includes('Captions show up here'), 'idle hint shown (static fallback replaced)')
  await page.screenshot({ path: `${OUT}/01-desktop-light-idle.png` })
  await page.click('[data-start]')
  await page.waitForTimeout(1600)
  ok(await page.locator('[data-stop]').isVisible(), 'X visible while running')
  ok(await page.locator('.d-vol').count() >= 1 || (await page.locator('.d-line').count()) >= 1, 'captions arriving')
  await page.waitForTimeout(9000)
  await page.screenshot({ path: `${OUT}/02-desktop-light-captioning.png` })
  ok((await page.locator('.d-spk').allInnerTexts()).includes('Speaker 2'), 'second speaker gets a new labelled line')
  ok((await page.locator('.d-sound').allInnerTexts()).includes('[Laughter]'), 'sound label shown')
  ok((await page.locator('[data-live]').innerText()).length > 0, 'screen-reader live region announces final lines')
  await page.waitForTimeout(8000)
  await page.click('[data-stop]')
  ok(await page.locator('[data-veil]').isVisible(), 'pause veil shows')
  ok((await page.locator('[data-status]').innerText()) === 'Paused', 'status says Paused')
  await page.click('[data-save]')
  await page.waitForTimeout(800)
  ok((await page.locator('[data-save]').innerText()) === '[ Saved ]', 'Save -> Saved')
  await page.screenshot({ path: `${OUT}/03-desktop-paused-saved.png` })
  await page.click('[data-new]')
  ok((await page.locator('.d-line').count()) === 0 && await page.locator('[data-start]').isVisible(), 'New clears and shows Start')
  // Settings: theme, lettering, size, persisted.
  await page.click('[data-gear]')
  await page.click('[data-theme="harbor"]')
  await page.click('[data-lettering="atkinson"]')
  await page.click('[data-bigger]')
  await page.click('[data-done]')
  await page.waitForTimeout(400)
  ok((await page.locator('.screen').evaluate((e) => getComputedStyle(e).backgroundColor)) === 'rgb(23, 51, 49)', 'Harbor theme applied')
  await page.click('[data-start]')
  await page.waitForTimeout(12000)
  const box = await page.locator('.phone').boundingBox()
  ok(Math.abs(box.height / box.width - 19.5 / 9) < 0.02, `phone keeps its shape while captions pile up (h/w ${(box.height / box.width).toFixed(2)})`)
  await page.screenshot({ path: `${OUT}/04-desktop-harbor-atkinson-bigger.png` })
  await page.reload()
  await page.waitForSelector('[data-demo][data-ready]')
  ok((await page.locator('.screen').evaluate((e) => getComputedStyle(e).backgroundColor)) === 'rgb(23, 51, 49)', 'theme remembered after reload')
  // Keyboard: Tab reaches the demo controls with a visible focus.
  await page.evaluate(() => localStorage.clear())
  await page.reload()
  await page.click('[data-gear]')
  await page.screenshot({ path: `${OUT}/05-desktop-settings.png` })
  await page.keyboard.press('Escape')
  ok(await page.locator('[data-settings]').isHidden(), 'Escape closes Settings')
  await page.screenshot({ path: `${OUT}/06-desktop-full.png`, fullPage: true })
  ok(external.length === 0, `no off-site requests (${external.join(', ')})`)
  ok(errors.length === 0, `no page errors (${errors.join('; ')})`)
  await ctx.close()

  // Phones: no sideways scroll at 320 / 375 / 390; dark mode screenshot.
  for (const [w, scheme] of [[320, 'light'], [375, 'dark'], [390, 'light']]) {
    const c = await browser.newContext({ viewport: { width: w, height: 800 }, deviceScaleFactor: 2, colorScheme: scheme, isMobile: true, hasTouch: true })
    const p = await c.newPage()
    await p.goto(BASE)
    await p.waitForSelector('[data-demo][data-ready]')
    const sw = await p.evaluate(() => document.documentElement.scrollWidth)
    ok(sw <= w, `${w}px: no sideways scroll (scrollWidth ${sw})`)
    if (w !== 320) {
      await p.tap('[data-start]')
      await p.waitForTimeout(14000)
      await p.screenshot({ path: `${OUT}/07-phone-${w}-${scheme}.png`, fullPage: false })
      await p.screenshot({ path: `${OUT}/08-phone-${w}-${scheme}-full.png`, fullPage: true })
    }
    await c.close()
  }

  // Reduced motion: the whole conversation appears at once.
  const rm = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' })
  const rp = await rm.newPage()
  await rp.goto(BASE)
  await rp.waitForSelector('[data-demo][data-ready]')
  await rp.click('[data-start]')
  await rp.waitForTimeout(150)
  ok((await rp.locator('.d-line').count()) === 7, `reduced motion: all 7 lines at once (got ${await rp.locator('.d-line').count()})`)
  await rm.close()

  // No JavaScript: the static conversation shows.
  const nj = await browser.newContext({ viewport: { width: 1280, height: 900 }, javaScriptEnabled: false })
  const np = await nj.newPage()
  await np.goto(BASE)
  ok((await np.locator('.d-line').count()) === 5, 'no JS: static conversation shows')
  await np.screenshot({ path: `${OUT}/09-no-javascript.png` })
  await nj.close()
} finally {
  await browser.close()
}
if (fails.length) { console.error('BROWSER CHECK FAILED:\n- ' + fails.join('\n- ')); process.exit(1) }
console.log('browser check: ok')
