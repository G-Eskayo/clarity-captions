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
  .filter((e) => e.getClientRects().length && !e.closest('[hidden]') && !e.closest('.phone, .tablet')) // the demo phone has its own screens; the iPad's top half is upside down on purpose
  .filter((e) => { for (let n = e; n && n !== document.body; n = n.parentElement) { const s = getComputedStyle(n); if (+s.opacity < 0.99 || (s.transform !== 'none' && s.transform !== 'matrix(1, 0, 0, 1, 0, 0)' && !n.closest('.phone'))) return true } return false })
  .map((e) => e.tagName + ':' + (e.textContent || '').trim().slice(0, 40)))

// Every bar is full grown and matches its number; the winner in each row is the best number in it.
async function checkBars(p, tag, minBars, minRows) {
  const bars = await p.$$eval('[data-bar]', (cells) => cells.filter((c) => c.getClientRects().length).map((c) => {
    const bar = c.querySelector('.bar-fill'); if (!bar) return { text: c.textContent, err: 'no bar' }
    const want = +c.dataset.bar, got = bar.getBoundingClientRect().width / bar.parentElement.getBoundingClientRect().width
    return { text: c.textContent.trim(), want, got, win: c.classList.contains('win') }
  }))
  ok(bars.length >= minBars, `${tag}: every score has a bar (${bars.length})`)
  for (const b of bars) ok(!b.err && Math.abs(b.got - b.want) < 0.02, `${tag}: bar for "${b.text}" is ${b.got?.toFixed(3)}, should be ${b.want}`)
  // The winner in each row is the best number in it: the lowest error rate, the highest translation score.
  const rows = await p.$$eval('table[data-bars]', (ts) => ts.filter((t) => t.getClientRects().length).flatMap((t) => [...t.tBodies[0].rows].map((r) => {
    const cells = [...r.querySelectorAll('[data-bar]')]; if (cells.length < 2) return null
    const vals = cells.map((c) => parseFloat(c.textContent)); const lower = t.dataset.better === 'lower'
    const best = lower ? Math.min(...vals) : Math.max(...vals)
    return { row: r.cells[0].textContent, ok: cells.every((c, i) => c.classList.contains('win') === (vals[i] === best)) }
  })).filter(Boolean))
  for (const r of rows) ok(r.ok, `${tag}: winner marked wrong in "${r.row}"`)
  ok(rows.length >= minRows, `${tag}: comparison rows found (${rows.length})`)
}

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
    // Home: the test results (#182) grow as bars too, with the better engine marked in each row.
    await scrollThrough(p)
    await checkBars(p, `${tag} home`, 2 + 3 * 2, 4)
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
    await checkBars(p, `${tag} versions`, 3 * 2 + 6 * 3 + 19, 9)
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

  // ── Device tabs (#184): iPhone, iPad, Mac swap the top of the page; the address follows ──────────────────────
  for (const [w, scheme] of [[1280, 'light'], [390, 'dark']]) {
    const tag = `${w}-${scheme} devices`
    const dc = await browser.newContext({ viewport: { width: w, height: 844 }, colorScheme: scheme, isMobile: w < 500, hasTouch: w < 500 })
    const dp = await dc.newPage()
    const errors = []; dp.on('pageerror', (e) => errors.push(e.message))
    const shown = () => dp.$$eval('[data-device]', (ps) => ps.filter((x) => x.getClientRects().length).map((x) => x.dataset.device).join(','))
    const selected = () => dp.$$eval('[role="tab"][aria-selected="true"]', (ts) => ts.map((t) => t.dataset.tab).join(','))
    await dp.goto(BASE); await wait(dp, 300)
    ok((await shown()) === 'iphone' && (await selected()) === 'iphone', `${tag}: iPhone shows first (${await shown()})`)
    await dp.click('[role="tab"][data-tab="mac"]'); await wait(dp, 120)
    const pillOnTab = () => dp.evaluate(() => {
      const pill = document.querySelector('[data-devices] .pill'), t = document.querySelector('[data-devices] [aria-selected="true"]')
      if (!pill) return 'no pill'
      const r = pill.getBoundingClientRect(), s = t.getBoundingClientRect()
      return Math.abs(r.left - s.left) < 2 && Math.abs(r.width - s.width) < 2 ? 'ok' : `pill ${r.left},${r.width} vs ${s.left},${s.width}`
    })
    ok((await pillOnTab()) !== 'ok', `${tag}: the pill slides to Mac (is not there yet after 120 ms)`)
    await wait(dp, 600)
    ok((await pillOnTab()) === 'ok', `${tag}: the pill ends on Mac (${await pillOnTab()})`)
    ok((await shown()) === 'mac' && (await selected()) === 'mac', `${tag}: the Mac tab shows only the Mac part (${await shown()})`)
    ok(new URL(dp.url()).hash === '#mac', `${tag}: the address says #mac (${dp.url()})`)
    await dp.keyboard.press('ArrowLeft'); await wait(dp, 100)
    ok((await shown()) === 'ipad' && await dp.evaluate(() => document.activeElement?.dataset.tab) === 'ipad', `${tag}: ← moves to iPad and focuses it`)
    await dp.keyboard.press('ArrowRight'); await dp.keyboard.press('ArrowRight'); await wait(dp, 100)
    ok((await shown()) === 'iphone', `${tag}: → wraps round to iPhone (${await shown()})`)
    ok(!new URL(dp.url()).hash, `${tag}: iPhone has a plain address (${dp.url()})`)
    for (const dev of ['ipad', 'mac']) {
      await dp.goto(BASE + '#' + dev); await wait(dp, 300)
      ok((await shown()) === dev, `${tag}: a link to #${dev} opens ${dev} (${await shown()})`)
      ok(await dp.evaluate(() => scrollY) === 0, `${tag}: #${dev} opens at the top of the page, not scrolled`)
      const sw = await dp.evaluate(() => document.documentElement.scrollWidth)
      ok(sw <= w, `${tag}: ${dev} has no sideways scroll (scrollWidth ${sw})`)
    }
    await dp.goto(BASE + '#how'); await wait(dp, 300)
    ok((await shown()) === 'iphone', `${tag}: a link into the iPhone part (#how) opens iPhone`)
    await dp.goto(BASE + '#faq'); await wait(dp, 300)
    ok((await shown()) === 'iphone', `${tag}: a fresh load of a shared part (#faq) starts on iPhone`)
    // iPad: both halves fill line by line, each in its own language; the button turns the iPad round.
    await dp.goto(BASE + '#ipad'); await dp.locator('[data-tablet]').scrollIntoViewIfNeeded(); await wait(dp, 9000)
    const halves = await dp.$$eval('[data-half]', (hs) => hs.map((h) => ({ half: h.dataset.half, lines: [...h.querySelectorAll('.t-line')].map((l) => (l.classList.contains('tr') ? 'T:' : '') + l.textContent) })))
    const you = halves.find((h) => h.half === 'you').lines, them = halves.find((h) => h.half === 'them').lines
    ok(you.length === 4 && them.length === 4, `${tag}: the whole conversation plays on both halves (${you.length}, ${them.length})`)
    ok(you[0] === 'T:How was the drive?' && them[0] === '¿Qué tal el viaje?', `${tag}: their words come to you translated and marked (${you[0]} / ${them[0]})`)
    ok(you[1] === 'Long, but the kids slept the whole way.' && them[1].startsWith('T:Largo'), `${tag}: your words go to them translated and marked`)
    ok(await dp.getAttribute('[data-flip]', 'aria-pressed') === 'true', `${tag}: at the end it turns once to show their side`)
    await dp.click('[data-flip]'); await wait(dp, 1100)
    const t = await dp.$eval('.tablet', (e) => getComputedStyle(e).transform)
    ok(t === 'none' || t === 'matrix(1, 0, 0, 1, 0, 0)', `${tag}: "See your side" turns it back (${t})`)
    ok((await dp.textContent('[data-flip]')).includes('their side'), `${tag}: the button then offers their side`)
    await dp.goto(BASE + '#mac'); await dp.locator('[data-mac]').scrollIntoViewIfNeeded(); await wait(dp, 7500)
    const pop = await dp.$$eval('[data-pop-lines] .pop-line', (ls) => ls.map((l) => l.textContent))
    ok(pop.length === 3 && pop[2] === 'Speaker 2Hi Grandpa! We miss you.', `${tag}: the Mac window captions the call, newest three lines (${pop.join(' | ')})`)
    // Questions in the header stays on the device you're on and goes to its own questions.
    await dp.goto(BASE + '#mac'); await wait(dp, 300)
    if (w > 500) {
      await dp.click('header.top a[href="#faq"]'); await wait(dp, 1200)
      ok((await shown()) === 'mac', `${tag}: Questions keeps you on Mac (${await shown()})`)
      // At the top of the window, or as far as the page goes when they're at the very end.
      const [top, atEnd] = await dp.$eval('#mac-faq', (e) => [Math.round(e.getBoundingClientRect().top), Math.abs(innerHeight + scrollY - document.documentElement.scrollHeight) < 2])
      ok(Math.abs(top) < 5 || (atEnd && top > 0 && top < 844 / 2), `${tag}: Questions scrolls to the Mac questions (top ${top})`)
    }
    // The iPad's translation results grow as bars, the best translator marked in each row.
    await dp.goto(BASE + '#ipad'); await scrollThrough(dp); await wait(dp, 800)
    await checkBars(dp, `${tag} iPad`, 18, 6)
    ok(errors.length === 0, `${tag}: no page errors (${errors.join('; ')})`)
    await dc.close()
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
  await rp.goto(BASE + '#ipad'); await wait(rp, 300)
  ok(await rp.$$eval('[data-half="you"] .t-line', (l) => l.length) === 4, 'reduced motion: the iPad conversation shows whole at once')
  ok(await rp.$eval('.tablet', (e) => !e.hasAttribute('data-turned')), 'reduced motion: the iPad does not turn by itself')
  await rm.close()

  // ── No JavaScript: every word and number shows ───────────────────────────────
  const nj = await browser.newContext({ viewport: { width: 1280, height: 900 }, javaScriptEnabled: false })
  const np = await nj.newPage()
  for (const page of ['', 'versions.html']) {
    await np.goto(BASE + page)
    ok((await hiddenText(np)).length === 0, `no JavaScript: ${page || 'home'} text hidden: ${(await hiddenText(np)).slice(0, 4).join(' | ')}`)
  }
  await np.goto(BASE)
  ok(await np.$$eval('[data-device]', (ps) => ps.filter((x) => x.getClientRects().length).length) === 3, 'no JavaScript: iPhone, iPad and Mac all show, one after the other')
  await nj.close()
} finally {
  await browser.close()
}
if (fails.filter(Boolean).length) { console.error('MOTION CHECK FAILED:\n- ' + fails.filter(Boolean).join('\n- ')); process.exit(1) }
console.log('motion check: ok')
