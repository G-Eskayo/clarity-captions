// Drives the Versions page's version switcher in Chrome (#165): default version, clicking each version, the address,
// the back button, old #engine-style links, a fresh load of a deep link, phone width with no sideways scroll, and no
// JavaScript (every version shows). Saves screenshots for the PR.
//   cd site && python3 -m http.server 8744 --bind 127.0.0.1 &
//   node scripts/check-site-versions.mjs <screenshot-dir>
// Needs playwright-core (any install; MARVIN's dashboard has one) and Google Chrome. Not run in CI.
import os from 'os'
import path from 'path'
let chromium
try { ({ chromium } = await import('playwright-core')) } catch {
  ({ chromium } = await import(path.join(os.homedir(), '.agents/dashboard/node_modules/playwright-core/index.mjs')))
}
const out = process.argv[2], base = 'http://127.0.0.1:8744/versions.html'
const fails = []; const check = (ok, m) => { if (!ok) fails.push(m) }
const browser = await chromium.launch({ channel: 'chrome' })
const visible = (page) => page.$$eval('.version', (vs) => vs.filter((v) => !v.hidden).map((v) => v.id))
const current = (page) => page.$$eval('.version-nav a[aria-current="page"]', (as) => as.map((a) => a.textContent))
for (const scheme of ['light', 'dark']) for (const width of [390, 1280]) {
  const page = await browser.newPage({ viewport: { width, height: 900 }, colorScheme: scheme })
  await page.goto(base)
  check(JSON.stringify(await visible(page)) === '["v1-0"]', `${scheme} ${width}: default shows only 1.0`)
  check(JSON.stringify(await current(page)) === '["1.0"]', `${scheme} ${width}: 1.0 marked current`)
  for (const v of ['1.1', '1.2', '1.3']) {
    await page.click(`.version-nav a:text-is("${v}")`)
    const id = 'v' + v.replace('.', '-')
    check(JSON.stringify(await visible(page)) === JSON.stringify([id]), `${scheme} ${width}: click ${v} shows only it`)
    check(page.url().endsWith('#' + id), `${scheme} ${width}: address is #${id}`)
    check(JSON.stringify(await current(page)) === JSON.stringify([v]), `${scheme} ${width}: ${v} marked current`)
    const sideways = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)
    check(!sideways, `${scheme} ${width}: ${v} scrolls sideways`)
    if (width === 390 || v === '1.3') await page.screenshot({ path: `${out}/versions-${v}-${scheme}-${width}.png`, fullPage: false })
  }
  await page.goBack()
  check(JSON.stringify(await visible(page)) === '["v1-2"]', `${scheme} ${width}: back button returns to 1.2`)
  await page.goto(base + '#v1-0'); await page.screenshot({ path: `${out}/versions-1.0-${scheme}-${width}.png` })
  await page.goto(base + '#engine'); await page.waitForTimeout(1500)
  check(JSON.stringify(await visible(page)) === '["v1-1"]', `${scheme} ${width}: old #engine link opens 1.1`)
  check(await page.evaluate(() => document.getElementById('engine').getBoundingClientRect().top < 200), `${scheme} ${width}: #engine scrolled into view`)
  await page.goto(base + '#translation'); await page.waitForTimeout(1500)
  const fresh = await browser.newPage({ viewport: { width, height: 900 }, colorScheme: scheme })
  await fresh.goto(base + '#languages'); await fresh.waitForTimeout(300)
  check(JSON.stringify(await visible(fresh)) === '["v1-2"]', `${scheme} ${width}: fresh load of #languages opens 1.2`)
  check(await fresh.evaluate(() => Math.abs(document.getElementById('languages').getBoundingClientRect().top) < 5 || scrollY >= document.documentElement.scrollHeight - innerHeight - 1), `${scheme} ${width}: fresh load jumps straight to #languages`)
  await fresh.close()
  check(JSON.stringify(await visible(page)) === '["v1-3"]', `${scheme} ${width}: #translation opens 1.3`)
  await page.close()
}
const nojs = await browser.newPage({ javaScriptEnabled: false })
await nojs.goto(base)
check((await visible(nojs)).length === 4, 'no JavaScript: all four versions show')
await browser.close()
console.log(fails.length ? "versions check: FAIL\n" + fails.join("\n") : "versions check: ok")
if (fails.length) process.exitCode = 1
