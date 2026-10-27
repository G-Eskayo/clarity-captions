// Checks for the website in site/ (#44), no dependencies: node scripts/check-site.mjs
// 1. Nothing phones home: every script, stylesheet, image, font and CSS url() is local (or a data: URL).
// 2. Honest claims (docs/design/honest-claims-2026-10-10.md): no "who is speaking", naming speakers, speed promises,
//    reading or hearing benefits, "free", or any price other than the real one ($4.99, once: ADR 0007) on the marketing page.
// 3. Contrast: every demo theme's caption text and speaker colours reach 7:1 (the app's rule); the page's own text,
//    muted text and links reach 4.5:1 on their backgrounds, in light and dark.
// 4. Links and anchors: local files exist; every #anchor has a target.
// 5. The demo's logic: chunks, blocks and the gummy lip colour behave like the app.
import { readFileSync, existsSync, readdirSync } from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import { THEMES, SCRIPT, LETTERING, SAVED_EXAMPLE } from '../site/seal-data.js'
import { chunksOf, blocksFor, lip, transcriptOf, previewOf, savedTitle, autoplay } from '../site/demo.js'
import { barFractions, winners, countFrame, SAMPLE_STEPS } from '../site/motion.js'

const SITE = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'site')
const failures = []
const check = (ok, msg) => { if (!ok) failures.push(msg) }

const pages = readdirSync(SITE).filter((f) => f.endsWith('.html'))
const read = (f) => readFileSync(path.join(SITE, f), 'utf-8')

// 1. local only
const isLocal = (u) => !/^(https?:)?\/\//i.test(u) || /^data:/i.test(u)
for (const f of pages) {
  const html = read(f)
  for (const m of html.matchAll(/<(script|img|source|link|iframe|video|audio)\b[^>]*?\s(src|srcset|href)="([^"]+)"/gi)) {
    const [, tag, attr, url] = m
    if (tag.toLowerCase() === 'link' && /rel="(alternate|canonical)"/.test(m[0])) continue
    for (const u of url.split(',').map((x) => x.trim().split(' ')[0])) check(isLocal(u), `${f}: <${tag} ${attr}> loads from off-site: ${u}`)
  }
  for (const m of html.matchAll(/url\(\s*['"]?([^'")]+)/gi)) check(isLocal(m[1]), `${f}: CSS url() loads from off-site: ${m[1]}`)
  check(!/<script(?![^>]*\bsrc=)[^>]*>[^<]*(gtag|analytics|plausible|fbq)\b/i.test(html), `${f}: looks like analytics`)
}
for (const js of ['demo.js', 'seal-data.js']) {
  const src = read(js)
  check(!/\b(fetch|XMLHttpRequest|sendBeacon|WebSocket|import\s*\(\s*['"]https?:)/.test(src), `${js}: makes network requests`)
  for (const m of src.matchAll(/from\s+['"]([^'"]+)['"]/g)) check(m[1].startsWith('./'), `${js}: imports from off-site: ${m[1]}`)
}

// 2. honest claims, on the visible text of the marketing page and the demo script
const visible = (html) => html.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<script[\s\S]*?<\/script>/g, ' ').replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ')
const BANNED = [
  [/(?<!(n't|not|never) )(shows|tells|see|knows?) who|(?<!(n't|not|never) .{0,20})who('s| is) (speaking|talking)/i, 'claims to know who is speaking'],
  [/name (each|the|a|your) (speaker|voice)|naming speakers|give .{0,20} a name/i, 'mentions naming speakers (removed in v1)'],
  [/within (a|one) second|instant(ly)? caption|real[- ]time accuracy|100 ?%|every word/i, 'promises speed or accuracy'],
  [/improves? (your )?reading|helps? (you )?(read|hear)|hearing loss|treat|cure|better hearing/i, 'makes a reading or hearing claim'],
  [/\bfree\b|\$\s?(?!4\.99\b)\d|\d+(\.\d+)? ?(usd|dollars)/i, 'mentions "free" or a price other than $4.99']
]
const pageText = visible(read('index.html')) + ' ' + SCRIPT.map((s) => s.text || s.sound).join(' ')
for (const [re, why] of BANNED) {
  const m = pageText.match(re)
  check(!m, `index.html ${why}: "${m?.[0]}"`)
}
check(/not a medical device/i.test(pageText), 'index.html must say Seal is not a medical device')
check(/can (contain|get|make) mistakes|can mix (people|up)/i.test(pageText), 'index.html must say captions can be wrong')
// The banned patterns must catch real claims and spare honest disclaimers.
check(BANNED[0][0].test('Seal shows who is speaking') && !BANNED[0][0].test("It doesn't know who anyone is"), 'BANNED[0] self-test')
check(BANNED[4][0].test('Free for everyone') && !BANNED[4][0].test('freedom'), 'BANNED[4] self-test')
check(BANNED[4][0].test('Only $2.99') && BANNED[4][0].test('$4.999') && !BANNED[4][0].test('$4.99 once'), 'BANNED[4] allows only the real price')
check(!SCRIPT.some((s) => s.speaker !== undefined && s.speaker > 1), 'demo uses only Speaker 1 and 2')

// 3. contrast
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255)
const lin = (c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
const L = (h) => { const [r, g, b] = hex(h).map(lin); return 0.2126 * r + 0.7152 * g + 0.0722 * b }
export const ratio = (a, b) => { const [x, y] = [L(a), L(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05) }
for (const t of THEMES) {
  check(ratio(t.text, t.bg) >= 7, `theme ${t.id}: text ${ratio(t.text, t.bg).toFixed(2)}:1 < 7`)
  t.speakers.forEach((s, i) => check(ratio(s, t.bg) >= 7, `theme ${t.id}: speaker ${i + 1} ${ratio(s, t.bg).toFixed(2)}:1 < 7`))
  check(ratio(t.saved, t.bg) >= 4.5, `theme ${t.id}: saved green ${ratio(t.saved, t.bg).toFixed(2)}:1 < 4.5`)
  check(ratio(t.bg, t.text) >= 4.5, `theme ${t.id}: Start label on its button < 4.5`)
}
const html = read('index.html')
const vars = (block) => Object.fromEntries([...block.matchAll(/--([a-z]+):\s*(#[0-9a-fA-F]{6})/g)].map((m) => [m[1], m[2]]))
const light = vars(html.match(/:root \{([^}]*)\}/)[1])
const dark = { ...light, ...vars(html.match(/prefers-color-scheme: dark\) \{\s*:root \{([^}]*)\}/)[1]) }
for (const [mode, c] of [['light', light], ['dark', dark]]) {
  for (const [fg, bg, min] of [['text', 'bg', 7], ['muted', 'bg', 4.5], ['accent', 'bg', 4.5], ['text', 'card', 7], ['muted', 'card', 4.5], ['accent', 'card', 4.5]]) {
    check(ratio(c[fg], c[bg]) >= min, `page ${mode}: --${fg} on --${bg} ${ratio(c[fg], c[bg]).toFixed(2)}:1 < ${min}`)
  }
}

// 4. links and anchors
for (const f of pages) {
  const h = read(f)
  const ids = new Set([...h.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]))
  for (const m of h.matchAll(/\shref="([^"]+)"/g)) {
    const u = m[1]
    if (/^(https?:|mailto:|data:)/.test(u)) continue
    if (u.startsWith('#')) { check(ids.has(u.slice(1)), `${f}: anchor ${u} has no target`); continue }
    check(existsSync(path.join(SITE, u.split('#')[0])), `${f}: link to missing file ${u}`)
  }
  for (const m of h.matchAll(/\s(?:src|srcset)="([^"]+)"/g)) {
    for (const u of m[1].split(',').map((x) => x.trim().split(' ')[0])) if (isLocal(u) && !u.startsWith('data:')) check(existsSync(path.join(SITE, u)), `${f}: missing asset ${u}`)
  }
  for (const m of h.matchAll(/url\('?([^')]+)'?\)/g)) if (!m[1].startsWith('data:')) check(existsSync(path.join(SITE, m[1])), `${f}: missing CSS asset ${m[1]}`)
}

// 5. demo logic
check(JSON.stringify(chunksOf('one two three four five six seven')) === JSON.stringify(['one two three', 'one two three four five six', 'one two three four five six seven']), 'chunksOf: 3 words at a time, ending with the full line')
check(JSON.stringify(chunksOf('hi')) === JSON.stringify(['hi']), 'chunksOf: a short line is one chunk')
const b = blocksFor(SCRIPT, SCRIPT.length)
check(b[b.length - 1].final === false, 'blocksFor: the last, unfinished line stays still-changing')
check(b.slice(0, -1).every((x) => x.sound || x.final), 'blocksFor: earlier lines are final')
check(blocksFor(SCRIPT, 1, 'Hi. My')[1]?.text === 'Hi. My' && blocksFor(SCRIPT, 1, 'Hi. My')[1].final === false, 'blocksFor: a partial line is still-changing')
check(blocksFor(SCRIPT, 3, 'x').length === 3, 'blocksFor: no partial is drawn for a sound label')
check(LETTERING.length === 6 && LETTERING[0].id === 'opendyslexic', 'six letterings, OpenDyslexic first (the default)')
check(transcriptOf(SAVED_EXAMPLE).split('\n')[0] === 'Speaker 1: Did you two decide on the trip yet?' && transcriptOf(SAVED_EXAMPLE).includes('\n[Laughter]\n'), 'transcriptOf: "Speaker N: " lines, sound labels bare')
check(previewOf(SAVED_EXAMPLE).length === 71 && previewOf(SAVED_EXAMPLE).endsWith('…') && previewOf([{ speaker: 0, text: 'Hi.' }]) === 'Speaker 1: Hi.', 'previewOf: cut at 70 characters with an ellipsis')
const at = new Date(2026, 9, 20, 15, 5)
check(savedTitle(new Date(2026, 9, 20, 8, 56), at) === 'Today, 8:56 AM' && savedTitle(new Date(2026, 9, 19, 19, 12), at) === 'Yesterday, 7:12 PM' && savedTitle(new Date(2026, 9, 14, 9, 0), at) === 'Oct 14, 9:00 AM', `savedTitle: Today / Yesterday / date (got ${savedTitle(new Date(2026, 9, 14, 9, 0), at)})`)
check(lip('#141419') === '#565659', `lip: dark fill lightens 28% (got ${lip('#141419')})`)
check(lip('#E9E3D5') === '#a8a399', `lip: light fill darkens 28% (got ${lip('#E9E3D5')})`)

// 6. scroll motion (#169)
check(JSON.stringify(barFractions([56.8, 55, 53.2], 100)) === JSON.stringify([0.568, 0.55, 0.532]), 'barFractions: against a fixed scale')
check(JSON.stringify(barFractions([4, 2.8, 8])) === JSON.stringify([0.5, 0.35, 1]), 'barFractions: against the biggest score when no scale')
check(barFractions([120], 100)[0] === 1 && barFractions([0, 0])[0] === 0, 'barFractions: never past full, never divides by zero')
check(JSON.stringify(winners([4.0, 2.8], 'lower')) === '[false,true]', 'winners: lowest error rate wins')
check(JSON.stringify(winners([56.8, 55, 53.2], 'higher')) === '[true,false,false]', 'winners: highest translation score wins')
check(JSON.stringify(winners([13.8, 13.8, 17.2], 'lower')) === '[true,true,false]', 'winners: a tie gives two winners')
check(JSON.stringify(winners([60.9], 'higher')) === '[false]', 'winners: one score alone is not a contest')
check(countFrame('40%', 0) === '0%' && countFrame('0.25 s', 0) === '0.00 s' && countFrame('18 of 19', 0) === '0 of 19', `countFrame: starts at zero, keeps unit and decimals (got ${countFrame('0.25 s', 0)})`)
check(countFrame('40%', 1) === '40%' && countFrame('0.25 s', 1) === '0.25 s' && countFrame('70 ms', 2) === '70 ms', 'countFrame: lands exactly on the real text')
check(+countFrame('40%', 0.5).replace('%', '') > 20, 'countFrame: eases out (past halfway at half time)')
const steps = [0, 0.3, 0.6, 0.9, 1].map((t) => +countFrame('70 ms', t).split(' ')[0])
check(steps.every((v, i) => i === 0 || v >= steps[i - 1]), `countFrame: never counts backwards (${steps})`)
check(new Set(SAMPLE_STEPS.map((x) => x.theme.id)).size === 6 && new Set(SAMPLE_STEPS.map((x) => x.lettering.id)).size === 6, 'theme sample: all six themes and all six letterings')
// autoplay: a fake observer and timers, so it runs in Node.
{
  let fire = null
  const IO = class { constructor(cb) { fire = cb } observe() {} disconnect() { fire = null } }
  const listeners = {}
  const root = { addEventListener: (ev, fn) => { listeners[ev] = fn } }
  const calls = []
  const demo = { state: 'idle', step: 0, startCaptions() { calls.push('start'); this.state = 'running' }, pause(o) { calls.push('pause:' + JSON.stringify(o)); this.state = 'paused' } }
  const realSet = globalThis.setTimeout
  const queued = []
  globalThis.setTimeout = (fn) => { queued.push(fn); return queued.length }
  try {
    autoplay(root, demo, { IO })
    fire([{ isIntersecting: true }]); queued.shift()?.()
    check(calls.join() === 'start', `autoplay: starts once in view (${calls})`)
    fire([{ isIntersecting: false }])
    check(calls[1] === 'pause:{"focus":false}', `autoplay: pauses out of view without taking focus (${calls})`)
    fire([{ isIntersecting: true }]); queued.shift()?.()
    check(calls[2] === 'start', 'autoplay: carries on back in view')
    demo.step = SCRIPT.length; demo.state = 'paused'
    fire([{ isIntersecting: true }]); queued.shift()?.()
    check(calls.length === 3, 'autoplay: never replays a finished conversation by itself')
    demo.step = 0
    listeners.pointerdown()
    check(fire === null, 'autoplay: a touch hands the demo to the person for good')
  } finally { globalThis.setTimeout = realSet }
}

if (failures.length) {
  console.error(`site check: ${failures.length} problem(s)\n- ${failures.join('\n- ')}`)
  process.exit(1)
}
console.log(`site check: ok (${pages.length} pages, ${THEMES.length} themes)`)
