// Scroll motion for the home and Versions pages (#169). Calm: short moves, each plays once, and it points at what
// matters (the demo, the steps, the winning score). Rules that keep it safe:
//   - Nothing is hidden by the HTML or CSS alone. Only this script marks things to rise in, and only things below the
//     first screen, so a slow or blocked script never leaves a blank page and nothing on screen jumps at load.
//   - With Reduce Motion (or no IntersectionObserver) nothing moves or plays by itself: bars are drawn full, numbers
//     show their real value, the theme sample waits for its Play button.
//   - Screen readers get the real numbers, never the counting ones.
// Pure helpers are exported for scripts/check-site.mjs; the page wiring runs only in a browser.
import { THEMES, LETTERING } from './seal-data.js'

// Bar length for each score, 0 to 1: against `scale` when the table gives one (chrF is out of 100), else against
// the biggest score in the table.
export function barFractions(values, scale = null) {
  const top = scale || Math.max(...values)
  return values.map((v) => (top > 0 ? Math.min(1, Math.max(0, v / top)) : 0))
}

// Which scores in a row win: the lowest error rate, or the highest translation score. Ties all win. A row with one
// score has no contest, so no winner.
export function winners(values, better = 'higher') {
  if (values.length < 2) return values.map(() => false)
  const best = better === 'lower' ? Math.min(...values) : Math.max(...values)
  return values.map((v) => v === best)
}

// The text a counting number shows at progress t (0 to 1), keeping the real text's unit and decimals ("0.25 s",
// "40%"). Eases out, and lands exactly on the real text at t = 1.
export function countFrame(real, t) {
  const m = real.match(/\d+(\.\d+)?/)
  if (!m || t >= 1) return real
  const decimals = (m[1] || '').length - (m[1] ? 1 : 0)
  const eased = 1 - (1 - Math.max(0, t)) ** 3
  return real.replace(m[0], (parseFloat(m[0]) * eased).toFixed(decimals))
}

// The theme sample's steps: theme i with lettering i, so six steps show all six of each.
export const SAMPLE_STEPS = THEMES.map((t, i) => ({ theme: t, lettering: LETTERING[i % LETTERING.length] }))

function onceInView(el, fn, { threshold = 0, margin = '0px 0px -8% 0px' } = {}) {
  const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) { io.disconnect(); fn() } }, { threshold, rootMargin: margin })
  io.observe(el)
}

function tween(ms, frame, done) {
  const t0 = performance.now()
  const step = (now) => {
    const t = Math.min(1, (now - t0) / ms)
    frame(t)
    if (t < 1) requestAnimationFrame(step); else done?.()
  }
  requestAnimationFrame(step)
}

// ── sections rise in ──────────────────────────────────────────────────────────────────────────────────────────────
const RISE = ['main section.band h2', 'main section.band .intro', 'main .card', 'main ul.ticks li', 'main .faq h3', 'main .faq p',
  'main .prose p', 'main figure.chart', 'main .tablewrap', 'main .stats', 'main .sample-wrap', 'main .story p', 'main .story-seal'].join(',')

function riseIn() {
  const all = [...document.querySelectorAll(RISE)]
  const chosen = new Set(all.filter((el) => {
    if (el.closest('.phone')) return false
    const laidOut = el.getClientRects().length > 0 // a hidden version has no layout yet: it rises in when shown
    return !laidOut || el.getBoundingClientRect().top > innerHeight * 0.92
  }))
  // One level only: a card rises, the paragraphs inside it come with it.
  for (const el of chosen) for (let up = el.parentElement; up; up = up.parentElement) if (chosen.has(up)) { chosen.delete(el); break }
  const io = new IntersectionObserver((es) => {
    for (const e of es) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target) }
  }, { rootMargin: '0px 0px -8% 0px' })
  for (const el of chosen) {
    const siblings = [...el.parentElement.children].filter((c) => chosen.has(c))
    el.style.setProperty('--i', Math.min(siblings.indexOf(el), 5))
    el.dataset.reveal = ''
    io.observe(el)
  }
  addEventListener('beforeprint', () => { for (const el of chosen) el.classList.add('in') })
}

// ── home: a line fills down the 1-2-3 steps as you scroll ─────────────────────────────────────────────────────────
function steps(grid) {
  const nums = [...grid.querySelectorAll('.step-n')]
  if (nums.length < 2) return
  grid.classList.add('has-line')
  const line = document.createElement('span')
  line.className = 'steps-line'
  line.setAttribute('aria-hidden', 'true')
  line.append(document.createElement('i'))
  grid.append(line)
  let fill = 0
  let at = []
  let across = true
  const centre = (el) => { const r = el.getBoundingClientRect(), g = grid.getBoundingClientRect(); return { x: r.left - g.left + r.width / 2, y: r.top - g.top + r.height / 2 } }
  const place = () => {
    const c = nums.map(centre), a = c[0], z = c[c.length - 1]
    across = Math.abs(z.x - a.x) > Math.abs(z.y - a.y)
    grid.dataset.dir = across ? 'across' : 'down'
    Object.assign(line.style, across
      ? { left: a.x + 'px', top: a.y - 2 + 'px', width: z.x - a.x + 'px', height: '4px' }
      : { left: a.x - 2 + 'px', top: a.y + 'px', width: '4px', height: z.y - a.y + 'px' })
    at = c.map((p) => (across ? (p.x - a.x) / (z.x - a.x) : (p.y - a.y) / (z.y - a.y)))
  }
  const update = () => {
    const g = grid.getBoundingClientRect(), first = g.top + parseFloat(line.style.top)
    // Down: the tip follows a line 60% down the screen. Across: it fills while the row climbs to the middle.
    const p = across ? (innerHeight * 0.85 - first) / (innerHeight * 0.35) : (innerHeight * 0.6 - first) / parseFloat(line.style.height)
    fill = Math.max(fill, Math.min(1, Math.max(0, p)))
    grid.style.setProperty('--fill', fill.toFixed(3))
    nums.forEach((n, i) => { if (fill >= at[i] - 0.001) n.classList.add('lit') })
    if (fill >= 1) removeEventListener('scroll', onScroll)
  }
  let queued = false
  const onScroll = () => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; update() }) } }
  place()
  update()
  addEventListener('scroll', onScroll, { passive: true })
  addEventListener('resize', () => { place(); update() })
}

// ── home: one caption in each theme and lettering ─────────────────────────────────────────────────────────────────
function sample(box, still) {
  const name = document.querySelector('[data-sample-name]')
  const play = document.querySelector('[data-sample-play]')
  const text = box.querySelector('.sample-text')
  let i = 0
  let timer = null
  let wanted = !still // play by itself unless Reduce Motion is on
  const show = (k) => {
    const { theme, lettering } = SAMPLE_STEPS[k]
    box.style.setProperty('--s-bg', theme.bg)
    box.style.setProperty('--s-text', theme.text)
    box.style.setProperty('--s-spk', theme.speakers[0])
    text.style.fontFamily = lettering.css
    name.textContent = `${theme.name} · ${lettering.name}`
  }
  const label = () => { play.textContent = timer ? 'Pause' : 'Play' }
  const halt = () => { clearInterval(timer); timer = null; label() }
  const run = () => {
    if (timer) return
    timer = setInterval(() => {
      i = (i + 1) % SAMPLE_STEPS.length
      show(i)
      if (i === 0) { wanted = false; halt() } // one full turn, back where it started
    }, 1500)
    label()
  }
  play.hidden = false
  play.addEventListener('click', () => { if (timer) { wanted = false; halt() } else { wanted = true; run() } })
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(([e]) => {
      if (e.isIntersecting && wanted) run()
      if (!e.isIntersecting && timer) halt() // keeps `wanted`, so it carries on once it is back in view
    }, { threshold: 0.6 }).observe(box)
  }
  show(0)
  label()
}

// ── Versions: scores grow as bars; the winner fills last and glows once ───────────────────────────────────────────
function bars(table, still) {
  const head = [...table.tHead.rows[0].cells]
  const cols = head.map((c, i) => (c.hasAttribute('data-bar-col') ? i : -1)).filter((i) => i >= 0)
  const rows = [...table.tBodies[0].rows]
  const cells = rows.flatMap((r) => cols.map((i) => r.cells[i]))
  const scale = parseFloat(table.dataset.bars) || null
  const fr = barFractions(cells.map((c) => parseFloat(c.textContent)), scale)
  cells.forEach((c, k) => {
    c.dataset.bar = fr[k].toFixed(4)
    const track = document.createElement('span')
    track.className = 'bar-track'
    track.setAttribute('aria-hidden', 'true')
    const fill = document.createElement('span')
    fill.className = 'bar-fill'
    fill.style.width = (fr[k] * 100).toFixed(2) + '%'
    track.append(fill)
    c.append(track)
  })
  rows.forEach((r, n) => {
    const own = cols.map((i) => r.cells[i])
    winners(own.map((c) => parseFloat(c.textContent)), table.dataset.better).forEach((w, k) => own[k].classList.toggle('win', w))
    r.style.setProperty('--r', Math.min(n, 8))
  })
  if (!still) onceInView(table, () => table.classList.add('grown'), { margin: '0px 0px -15% 0px' })
}

function chartBars(figure) {
  onceInView(figure, () => figure.classList.add('grown'), { margin: '0px 0px -15% 0px' })
}

// ── Versions: headline numbers count up ───────────────────────────────────────────────────────────────────────────
function counts(el, still) {
  const real = el.dataset.count
  const sr = document.createElement('span')
  sr.className = 'sr-only'
  sr.textContent = real
  el.before(sr)
  el.setAttribute('aria-hidden', 'true')
  if (still) return
  el.textContent = countFrame(real, 0)
  onceInView(el, () => tween(1100, (t) => { el.textContent = countFrame(real, t) }, () => { el.textContent = real }), { margin: '0px 0px -10% 0px' })
}

// ── Versions: the highlight slides between 1.0 and 1.1; the version fades in ──────────────────────────────────────
function switcher(nav) {
  const pill = document.createElement('span')
  pill.className = 'pill'
  pill.setAttribute('aria-hidden', 'true')
  nav.prepend(pill)
  nav.classList.add('has-pill')
  const place = () => {
    const a = nav.querySelector('a[aria-current]')
    if (!a) return
    pill.style.transform = `translate(${a.offsetLeft}px, ${a.offsetTop}px)`
    pill.style.width = a.offsetWidth + 'px'
    pill.style.height = a.offsetHeight + 'px'
  }
  place()
  requestAnimationFrame(() => requestAnimationFrame(() => pill.classList.add('ready')))
  new MutationObserver(place).observe(nav, { subtree: true, attributes: true, attributeFilter: ['aria-current'] })
  addEventListener('resize', place)
  for (const v of document.querySelectorAll('.version')) {
    new MutationObserver(() => {
      if (v.hidden) return
      v.classList.remove('enter')
      void v.offsetWidth // restart the fade
      v.classList.add('enter')
    }).observe(v, { attributes: true, attributeFilter: ['hidden'] })
  }
}

if (typeof document !== 'undefined') {
  const still = !!matchMedia?.('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)
  if (!still) document.documentElement.classList.add('motion')
  for (const t of document.querySelectorAll('table[data-bars]')) bars(t, still)
  for (const el of document.querySelectorAll('[data-count]')) counts(el, still)
  const box = document.querySelector('[data-sample]')
  if (box) sample(box, still)
  if (!still) {
    riseIn()
    const grid = document.querySelector('.steps')
    if (grid) steps(grid)
    for (const f of document.querySelectorAll('figure.chart')) if (f.querySelector('rect.bar')) chartBars(f)
    const nav = document.querySelector('.version-nav')
    if (nav) switcher(nav)
  }
}
