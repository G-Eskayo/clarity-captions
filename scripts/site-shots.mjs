// Full-page screenshots of every page of the site at phone width and desktop, light and dark (#207), for the
// before/after pictures on a PR and for each language's pages. Reduced motion, so the same page gives the same picture.
//   cd site && python3 -m http.server 8744 --bind 127.0.0.1 &
//   node scripts/site-shots.mjs <out-dir> [page ...]      (pages default to the English ones; e.g. he/index.html, index.html#mac)
// Needs playwright-core (any install; MARVIN's dashboard has one) and Google Chrome. Not run in CI.
import os from 'os'
import path from 'path'
import { mkdirSync } from 'fs'
let chromium
try { ({ chromium } = await import('playwright-core')) } catch {
  ({ chromium } = await import(path.join(os.homedir(), '.agents/dashboard/node_modules/playwright-core/index.mjs')))
}
const BASE = process.env.SITE_URL || 'http://127.0.0.1:8744/'
const OUT = process.argv[2] || '.'
const PAGES = process.argv.slice(3).length ? process.argv.slice(3) : ['index.html', 'index.html#ipad', 'index.html#mac', 'privacy.html', 'support.html', 'versions.html']
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const SIZES = [['phone', { width: 390, height: 844 }], ['desktop', { width: 1280, height: 900 }]]
mkdirSync(OUT, { recursive: true })
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
try {
  for (const [size, viewport] of SIZES) {
    for (const scheme of ['light', 'dark']) {
      const ctx = await browser.newContext({ viewport, deviceScaleFactor: 1, colorScheme: scheme, reducedMotion: 'reduce', locale: process.env.SHOT_LOCALE || 'en-US' })
      const page = await ctx.newPage()
      for (const p of PAGES) {
        await page.goto('about:blank')
        await page.goto(BASE + p)
        await page.waitForLoadState('networkidle')
        await page.evaluate(() => document.fonts.ready)
        await page.waitForTimeout(300)
        const name = `${p.replace('.html', '').replace(/[/#]/g, '-')}-${size}-${scheme}.png`
        await page.screenshot({ path: path.join(OUT, name), fullPage: true })
        console.log(name)
      }
      await ctx.close()
    }
  }
} finally { await browser.close() }
