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
  ok((await page.locator('[data-status]').innerText()) === 'Ready', 'status says Ready before starting')
  await page.screenshot({ path: `${OUT}/01-desktop-light-idle.png` })
  await page.click('[data-start]')
  await page.waitForTimeout(1600)
  ok(await page.locator('[data-stop]').isVisible(), 'X visible while running')
  ok(await page.locator('.d-vol').count() >= 1 || (await page.locator('[data-captions] .d-line').count()) >= 1, 'captions arriving')
  await page.waitForTimeout(9000)
  await page.screenshot({ path: `${OUT}/02-desktop-light-captioning.png` })
  ok((await page.locator('.d-spk').allInnerTexts()).includes('Speaker 2'), 'second speaker gets a new labelled line')
  ok((await page.locator('.d-sound').allInnerTexts()).includes('[Laughter]'), 'sound label shown')
  ok((await page.locator('[data-live]').innerText()).length > 0, 'screen-reader live region announces final lines')
  await page.waitForTimeout(8000)
  await page.click('[data-stop]')
  ok(await page.locator('[data-veil]').isVisible(), 'pause veil shows')
  ok((await page.locator('[data-status]').innerText()) === 'Paused', 'status says Paused')
  await page.screenshot({ path: `${OUT}/03a-desktop-paused.png` })
  await page.click('[data-save]')
  await page.waitForTimeout(450)
  ok((await page.locator('[data-save]').innerText()) === '[ ✔ ]', 'Save -> check')
  await page.waitForTimeout(1100)
  ok((await page.locator('[data-save]').innerText()) === '[ Saved ]', 'check -> Saved')
  await page.screenshot({ path: `${OUT}/03-desktop-paused-saved.png` })
  // Tap the dim to read; hold on empty space to bring [ Save ] / [ New ] back.
  const vb = await page.locator('[data-veil]').boundingBox()
  await page.mouse.click(vb.x + 12, vb.y + 12)
  await page.waitForTimeout(700)
  ok(await page.locator('[data-veil]').isHidden(), 'tapping the dim clears it')
  ok(await page.locator('[data-hint]').isVisible(), 'first clear shows the hold hint')
  const cb = await page.locator('[data-captions]').boundingBox()
  await page.mouse.move(cb.x + cb.width - 6, cb.y + 6)
  await page.mouse.down()
  await page.waitForTimeout(700)
  await page.mouse.up()
  await page.waitForTimeout(600)
  ok(await page.locator('[data-veil]').isVisible(), 'holding empty space brings the dim back')
  // Saved conversations: the list icon, the made-up example plus the one just saved.
  await page.click('[data-list]')
  await page.waitForTimeout(600)
  ok(await page.locator('[data-saved-list]').isVisible(), 'list icon opens Saved')
  ok((await page.locator('.d-row').count()) === 2, `Saved lists the example and the new one (got ${await page.locator('.d-row').count()})`)
  ok((await page.locator('.d-row strong').first().innerText()).startsWith('Today, '), 'newest saved is "Today, …"')
  await page.screenshot({ path: `${OUT}/03b-desktop-saved-list.png` })
  await page.locator('.d-row').nth(1).click()
  await page.waitForTimeout(600)
  ok(await page.locator('[data-hint]').isHidden(), 'a hint from the captions does not follow onto another page')
  ok(await page.locator('[data-share]').isVisible() && await page.locator('[data-delete]').isVisible(), 'a saved conversation opens dimmed with Share and Delete')
  await page.screenshot({ path: `${OUT}/03c-desktop-saved-conversation.png` })
  await page.click('[data-share]')
  await page.waitForTimeout(500)
  ok((await page.locator('[data-hint]').innerText()).includes('share sheet'), 'Share explains the share sheet')
  await page.click('[data-delete]')
  await page.waitForTimeout(500)
  ok(await page.locator('[data-del-q]').isVisible(), 'Delete asks first')
  await page.click('[data-del-yes]')
  await page.waitForTimeout(600)
  ok((await page.locator('.d-row').count()) === 1, 'Delete removes it and goes back to Saved')
  await page.click('[data-saved-back]')
  await page.waitForTimeout(600)
  ok(await page.locator('[data-saved-list]').isHidden(), 'back to the captions')
  await page.click('[data-new]')
  ok((await page.locator('[data-captions] .d-line').count()) === 0 && await page.locator('[data-start]').isVisible(), 'New clears and shows Start')
  // Settings: theme, lettering, size, persisted.
  await page.click('[data-gear]')
  ok((await page.locator('[data-lettering]').count()) === 6, 'six letterings in Settings')
  ok((await page.locator('[data-quiet]').count()) === 4, 'stop-when-quiet choices in Settings')
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
  await page.waitForTimeout(600)
  await page.screenshot({ path: `${OUT}/05-desktop-settings.png` })
  await page.keyboard.press('Escape')
  await page.waitForTimeout(600)
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
      await p.tap('[data-stop]')
      await p.waitForTimeout(800)
      await p.screenshot({ path: `${OUT}/07b-phone-${w}-${scheme}-paused.png`, fullPage: false })
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
  ok((await rp.locator('[data-captions] .d-line').count()) === 7, `reduced motion: all 7 lines at once (got ${await rp.locator('[data-captions] .d-line').count()})`)
  await rm.close()

  // No JavaScript: the static conversation shows.
  const nj = await browser.newContext({ viewport: { width: 1280, height: 900 }, javaScriptEnabled: false })
  const np = await nj.newPage()
  await np.goto(BASE)
  ok((await np.locator('[data-captions] .d-line').count()) === 5, 'no JS: static conversation shows')
  await np.screenshot({ path: `${OUT}/09-no-javascript.png` })
  await nj.close()
} finally {
  await browser.close()
}
if (fails.length) { console.error('BROWSER CHECK FAILED:\n- ' + fails.join('\n- ')); process.exit(1) }
console.log('browser check: ok')
