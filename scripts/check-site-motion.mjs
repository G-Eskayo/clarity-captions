// Drives the scroll motion on the home and Versions pages in Chrome (#169): the demo starts by itself and stops when it
// scrolls away, sections rise in, the 1-2-3 steps light up, the theme sample plays and can be paused, test scores grow
// as bars that match their numbers, headline numbers count up to the real value, and the version switcher's highlight
// slides. Then the same pages with Reduce Motion and with no JavaScript, where nothing may stay hidden or move.
// Saves screenshots for the PR.
//   cd site && python3 -m http.server 8744 --bind 127.0.0.1 &
//   node scripts/check-site-motion.mjs <screenshot-dir>
// Needs playwright-core (any install; MARVIN's dashboard has one) and Google Chrome. Not run in CI.
import os from 'os'
import path from 'path'
let chromium
try { ({ chromium } = await import('playwright-core')) } catch {
  ({ chromium } = await import(path.join(os.homedir(), '.agents/dashboard/node_modules/playwright-core/index.mjs')))
}
const BASE = process.env.SITE_URL || 'http://127.0.0.1:8744/'
const OUT = process.argv[2] || '.'
const fails = []
const ok = (c, m) => { if (!c) fails.push(m) }
const browser = await chromium.launch({ channel: 'chrome' })
const wait = (p, ms) => p.waitForTimeout(ms)
const state = (p) => p.getAttribute('[data-demo]', 'data-state')

// Scroll the way a person does, a screen at a time, so every observer fires on the way down.
async function scrollThrough(p, step = 350, pause = 120) {
  const h = await p.evaluate(() => document.documentElement.scrollHeight)
  for (let y = 0; y <= h; y += step) { await p.evaluate((y) => scrollTo(0, y), y); await wait(p, pause) }
  await wait(p, 1200)
}
// Anything that is meant to be read but still invisible, or still moved off its place.
const hiddenText = (p) => p.evaluate(() => [...document.querySelectorAll('main h2, main h3, main p, main li, main .card, main td, main figure')]
  .filter((e) => e.getClientRects().length && !e.closest('[hidden]') && !e.closest('.phone')) // the demo phone has its own screens
  .filter((e) => { for (let n = e; n && n !== document.body; n = n.parentElement) { const s = getComputedStyle(n); if (+s.opacity < 0.99 || (s.transform !== 'none' && s.transform !== 'matrix(1, 0, 0, 1, 0, 0)' && !n.closest('.phone'))) return true } return false })
  .map((e) => e.tagName + ':' + (e.textContent || '').trim().slice(0, 40)))

try {
  for (const [w, h, scheme] of [[1280, 900, 'light'], [390, 800, 'dark']]) {
    const tag = `${w}-${scheme}`
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, colorScheme: scheme, deviceScaleFactor: 2, isMobile: w < 500, hasTouch: w < 500 })
    const p = await ctx.newPage()
    const errors = []
    p.on('pageerror', (e) => errors.push(e.message))

    // ── home: the demo starts by itself once it is in view ──────────────────────
    await p.goto(BASE)
    await p.waitForSelector('[data-demo][data-ready]')
    await p.locator('[data-demo]').scrollIntoViewIfNeeded()
    await wait(p, 3000)
    ok((await state(p)) === 'running', `${tag}: demo starts by itself in view (state ${await state(p)})`)
    ok((await p.locator('[data-captions] .d-line').count()) >= 1, `${tag}: captions arrive without a tap`)
    await p.screenshot({ path: `${OUT}/motion-home-demo-${tag}.png` })
    // It stops when it scrolls away, without pulling the page back to it.
    await p.evaluate(() => scrollTo(0, document.getElementById('faq').offsetTop))
    await wait(p, 800)
    const y = await p.evaluate(() => scrollY)
    ok((await state(p)) === 'paused', `${tag}: demo stops when scrolled away (state ${await state(p)})`)
    ok(Math.abs(y - await p.evaluate(() => document.getElementById('faq').offsetTop)) < 5, `${tag}: stopping did not scroll the page back to the demo`)
    await p.evaluate(() => scrollTo(0, 0))
    await p.locator('[data-demo]').scrollIntoViewIfNeeded()
    await wait(p, 2500)
    ok((await state(p)) === 'running', `${tag}: demo carries on when it comes back into view`)

    // ── sections rise in; steps light up; theme sample plays ────────────────────
    await p.evaluate(() => scrollTo(0, 0)); await wait(p, 300)
    ok(await p.locator('[data-reveal]').count() >= 10, `${tag}: sections below the first screen are set to rise in (${await p.locator('[data-reveal]').count()})`)
    await p.evaluate(() => document.getElementById('how').scrollIntoView({ block: 'start', behavior: 'instant' }))
    await wait(p, 900)
    await p.screenshot({ path: `${OUT}/motion-home-steps-start-${tag}.png` })
    await scrollThrough(p)
    ok((await hiddenText(p)).length === 0, `${tag}: home text still hidden or moved after scrolling: ${(await hiddenText(p)).slice(0, 4).join(' | ')}`)
    ok((await p.locator('.steps .step-n.lit').count()) === 3, `${tag}: all three steps lit after scrolling past (${await p.locator('.steps .step-n.lit').count()})`)
    const fill = await p.evaluate(() => +getComputedStyle(document.querySelector('.steps') || document.body).getPropertyValue('--fill'))
    ok(fill > 0.99, `${tag}: the steps line is full (--fill ${fill})`)
    await p.evaluate(() => document.getElementById('how').scrollIntoView({ block: 'start', behavior: 'instant' }))
    await wait(p, 600)
    await p.screenshot({ path: `${OUT}/motion-home-steps-lit-${tag}.png` })

    await p.evaluate(() => document.querySelector('[data-sample]').scrollIntoView({ block: 'center', behavior: 'instant' }))
    const seen = new Set(), fonts = new Set()
    for (let i = 0; i < 24; i++) {
      seen.add(await p.locator('[data-sample]').evaluate((e) => getComputedStyle(e).getPropertyValue('--s-bg').trim()))
      fonts.add(await p.locator('[data-sample] .sample-text').evaluate((e) => getComputedStyle(e).fontFamily))
      if (i === 6) await p.screenshot({ path: `${OUT}/motion-home-sample-${tag}.png` })
      await wait(p, 500)
    }
    ok(seen.size === 6, `${tag}: the sample shows all six themes (${seen.size})`)
    ok(fonts.size === 6, `${tag}: the sample shows all six letterings (${fonts.size})`)
    const label = await p.locator('[data-sample-name]').innerText()
    ok(label.includes('·'), `${tag}: the sample names its theme and lettering ("${label}")`)
    // It played one full turn and stopped; Play runs it again and Pause stops it.
    ok((await p.locator('[data-sample-play]').innerText()) === 'Play', `${tag}: after one turn the button offers Play ("${await p.locator('[data-sample-play]').innerText()}")`)
    await p.click('[data-sample-play]'); await wait(p, 200)
    ok((await p.locator('[data-sample-play]').innerText()) === 'Pause', `${tag}: while playing the button offers Pause`)
    await wait(p, 1700)
    await p.click('[data-sample-play]'); await wait(p, 100)
    const a = await p.locator('[data-sample]').evaluate((e) => getComputedStyle(e).getPropertyValue('--s-bg').trim()); await wait(p, 3500)
    ok(a === await p.locator('[data-sample]').evaluate((e) => getComputedStyle(e).getPropertyValue('--s-bg').trim()), `${tag}: Pause stops the sample`)
    const sw = await p.evaluate(() => document.documentElement.scrollWidth)
    ok(sw <= w, `${tag}: home has no sideways scroll (scrollWidth ${sw})`)

    // ── Versions: switcher slides, scores grow as bars, numbers count up ────────
    await p.goto(BASE + 'versions.html')
    await wait(p, 400)
    const pillOn = async (label) => p.evaluate((label) => {
      const pill = document.querySelector('.version-nav .pill'); const a = [...document.querySelectorAll('.version-nav a')].find((x) => x.textContent === label)
      if (!pill) return 'no pill'
      const r = pill.getBoundingClientRect(), s = a.getBoundingClientRect()
      return Math.abs(r.left - s.left) < 2 && Math.abs(r.width - s.width) < 2 ? 'ok' : `pill ${r.left},${r.width} vs ${s.left},${s.width}`
    }, label)
    ok((await pillOn('1.0')) === 'ok', `${tag}: highlight sits on 1.0 (${await pillOn('1.0')})`)
    await p.click('.version-nav a:text-is("1.1")')
    await wait(p, 120)
    ok((await pillOn('1.1')) !== 'ok', `${tag}: highlight slides (is not already on 1.1 after 120 ms)`)
    await wait(p, 700)
    ok((await pillOn('1.1')) === 'ok', `${tag}: highlight ends on 1.1 (${await pillOn('1.1')})`)
    await p.screenshot({ path: `${OUT}/motion-versions-switch-${tag}.png` })
    await scrollThrough(p)
    ok((await hiddenText(p)).length === 0, `${tag}: Versions text still hidden or moved after scrolling: ${(await hiddenText(p)).slice(0, 4).join(' | ')}`)
    // Every bar is full grown and as long as its number says.
    const bars = await p.$$eval('[data-bar]', (cells) => cells.map((c) => {
      const bar = c.querySelector('.bar-fill'); if (!bar) return { text: c.textContent, err: 'no bar' }
      const want = +c.dataset.bar, got = bar.getBoundingClientRect().width / bar.parentElement.getBoundingClientRect().width
      return { text: c.textContent.trim(), want, got, win: c.classList.contains('win') }
    }))
    ok(bars.length >= 3 * 2 + 6 * 3 + 19, `${tag}: every score has a bar (${bars.length})`)
    for (const b of bars) ok(!b.err && Math.abs(b.got - b.want) < 0.02, `${tag}: bar for "${b.text}" is ${b.got?.toFixed(3)}, should be ${b.want}`)
    // The winner in each row is the best number in it: the lowest error rate, the highest translation score.
    const rows = await p.$$eval('table[data-bars]', (ts) => ts.flatMap((t) => [...t.tBodies[0].rows].map((r) => {
      const cells = [...r.querySelectorAll('[data-bar]')]; if (cells.length < 2) return null
      const vals = cells.map((c) => parseFloat(c.textContent)); const lower = t.dataset.better === 'lower'
      const best = lower ? Math.min(...vals) : Math.max(...vals)
      return { row: r.cells[0].textContent, ok: cells.every((c, i) => c.classList.contains('win') === (vals[i] === best)) }
    })).filter(Boolean))
    for (const r of rows) ok(r.ok, `${tag}: winner marked wrong in "${r.row}"`)
    ok(rows.length >= 9, `${tag}: comparison rows found (${rows.length})`)
    const counts = await p.$$eval('[data-count]', (es) => es.map((e) => ({ shown: e.textContent, real: e.dataset.count, sr: e.previousElementSibling?.textContent })))
    ok(counts.length >= 4, `${tag}: headline numbers present (${counts.length})`)
    for (const c of counts) ok(c.shown === c.real && c.sr === c.real, `${tag}: number counted to "${c.shown}", should be "${c.real}" (screen reader "${c.sr}")`)
    await p.evaluate(() => document.getElementById('translation').scrollIntoView({ behavior: 'instant' }))
    await wait(p, 500)
    await p.screenshot({ path: `${OUT}/motion-versions-translation-${tag}.png` })
    await p.evaluate(() => document.getElementById('languages').scrollIntoView({ behavior: 'instant' }))
    await wait(p, 500)
    await p.screenshot({ path: `${OUT}/motion-versions-languages-${tag}.png` })
    const sw2 = await p.evaluate(() => document.documentElement.scrollWidth)
    ok(sw2 <= w, `${tag}: Versions has no sideways scroll (scrollWidth ${sw2})`)
    // Mid-motion screenshot: a fresh load of #engine, caught while the bars grow.
    await p.goto(BASE + 'versions.html#languages'); await wait(p, 350)
    await p.screenshot({ path: `${OUT}/motion-versions-bars-growing-${tag}.png` })
    ok(errors.length === 0, `${tag}: no page errors (${errors.join('; ')})`)
    await ctx.close()
  }

  // ── Reduce Motion: everything in place at once, nothing plays by itself ───────
  const rm = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' })
  const rp = await rm.newPage()
  await rp.goto(BASE); await rp.waitForSelector('[data-demo][data-ready]'); await wait(rp, 3000)
  ok((await state(rp)) === 'idle', `reduced motion: the demo waits for a tap (state ${await state(rp)})`)
  ok((await hiddenText(rp)).length === 0, `reduced motion: home text hidden or moved without scrolling: ${(await hiddenText(rp)).slice(0, 4).join(' | ')}`)
  ok(await rp.locator('[data-reveal]').count() === 0, 'reduced motion: nothing is set to rise in')
  const s0 = await rp.locator('[data-sample]').evaluate((e) => getComputedStyle(e).getPropertyValue('--s-bg').trim())
  await rp.evaluate(() => document.querySelector('[data-sample]').scrollIntoView({ behavior: 'instant' })); await wait(rp, 3000)
  ok(s0 === await rp.locator('[data-sample]').evaluate((e) => getComputedStyle(e).getPropertyValue('--s-bg').trim()), 'reduced motion: the sample does not play by itself')
  await rp.goto(BASE + 'versions.html#v1-1'); await wait(rp, 200)
  ok((await hiddenText(rp)).length === 0, `reduced motion: Versions text hidden or moved: ${(await hiddenText(rp)).slice(0, 4).join(' | ')}`)
  const grown = await rp.$$eval('[data-bar] .bar-fill', (bs) => bs.every((b) => getComputedStyle(b).transform === 'none' || getComputedStyle(b).transform === 'matrix(1, 0, 0, 1, 0, 0)'))
  ok(grown, 'reduced motion: bars are full at once')
  const counted = await rp.$$eval('[data-count]', (es) => es.every((e) => e.textContent === e.dataset.count))
  ok(counted, 'reduced motion: numbers show their real value at once')
  await rp.screenshot({ path: `${OUT}/motion-versions-reduced.png` })
  await rm.close()

  // ── No JavaScript: every word and number shows ───────────────────────────────
  const nj = await browser.newContext({ viewport: { width: 1280, height: 900 }, javaScriptEnabled: false })
  const np = await nj.newPage()
  for (const page of ['', 'versions.html']) {
    await np.goto(BASE + page)
    ok((await hiddenText(np)).length === 0, `no JavaScript: ${page || 'home'} text hidden: ${(await hiddenText(np)).slice(0, 4).join(' | ')}`)
  }
  await nj.close()
} finally {
  await browser.close()
}
if (fails.filter(Boolean).length) { console.error('MOTION CHECK FAILED:\n- ' + fails.filter(Boolean).join('\n- ')); process.exit(1) }
console.log('motion check: ok')
