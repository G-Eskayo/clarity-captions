// Checks for the website in site/ (#44), no dependencies: node scripts/check-site.mjs
// 1. Nothing phones home: every script, stylesheet, image, font and CSS url() is local (or a data: URL).
// 2. Honest claims (docs/design/honest-claims-2026-10-10.md): no "who is speaking", naming speakers, speed promises,
//    reading or hearing benefits, "free", or any price other than the real one ($4.99, once: ADR 0007) on the marketing page.
// 3. Contrast: every demo theme's caption text and speaker colours reach 7:1 (the app's rule); the page's own text,
//    muted text and links reach 4.5:1 on their backgrounds, in light and dark.
// 4. Links and anchors: local files exist; every #anchor has a target.
// 5. The demo's logic: chunks, blocks and the gummy lip colour behave like the app.
// Every language (#207): each check runs on every built page in site/ and site/<code>/; each page says its lang and
// dir, lists its other languages with hreflang (never a draft language from English), and a draft says it's a draft.
import { readFileSync, existsSync, readdirSync } from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import { THEMES, SCRIPT, LETTERING, SAVED_EXAMPLE } from '../site/seal-data.js'
import { chunksOf, blocksFor, lip, transcriptOf, previewOf, savedTitle, autoplay } from '../site/demo.js'
import { barFractions, winners, countFrame, SAMPLE_STEPS } from '../site/motion.js'
import { DEVICES, deviceFor, lineFor, TABLE_TALK } from '../site/devices.js'
import { languages, outPath, urlOf, alternatesFor } from './build-site.mjs'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
// SITE_DIR checks a copy of site/ (used to prove the checks catch seeded faults).
const SITE = process.env.SITE_DIR || path.join(ROOT, 'site')
const failures = []
const check = (ok, msg) => { if (!ok) failures.push(msg) }

const LANGS = languages()
const built = LANGS.flatMap((lang) => lang.pages.map((page) => ({ lang, page, file: outPath(lang.code, page) })))
// Built pages in every language, plus any page made by hand (the gift page).
const pages = [...new Set([...built.map((b) => b.file), ...readdirSync(SITE).filter((f) => f.endsWith('.html'))])]
const read = (f) => readFileSync(path.join(SITE, f), 'utf-8')
const langOf = (f) => (f.includes('/') ? f.split('/')[0] : 'en')

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
for (const js of ['demo.js', 'seal-data.js', 'motion.js', 'devices.js', 'lang.js']) {
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
// The same rules in each language the site is written in. A language with no rules here fails, so a new translation
// can't skip them. MUST_SAY: captions can be wrong; and, while the app has no captions or screens in that language,
// that the app and its captions are in English (the site may only claim what the app ships in that language today).
export const BANNED_BY_LANG = {
  en: BANNED,
  he: [
    [/(?<!(לא|אינה|אינו) .{0,12})(יודע(ת)?|מזה(ה|ה)|מראה|מציג(ה)?) מי (מדבר|מדברת|מדברים)/, 'claims to know who is speaking'],
    [/(נותנת|נותן|לתת) שם (ל|לכל )?(דובר|קול)|שמות לדוברים/, 'mentions naming speakers (removed in v1)'],
    [/תוך שנייה|מייד(י|ית)|באופן מיידי|דיוק של 100|100 ?%|כל מילה ומילה/, 'promises speed or accuracy'],
    [/משפר(ת)? את (ה)?(קריאה|שמיעה)|עוזר(ת)? (לכם )?(לשמוע|לקרוא)|ירידה בשמיעה|אובדן שמיעה|מרפא|ריפוי|שמיעה טובה יותר/, 'makes a reading or hearing claim'],
    [/חינם|בחינם|ללא תשלום|\$\s?(?!4\.99\b)\d|\d+(\.\d+)? ?(דולר|ש"ח|ש״ח|₪)/, 'mentions "free" or a price other than $4.99']
  ]
}
export const MUST_SAY = {
  en: [[/can (contain|get|make) mistakes|can mix (people|up)/i, 'must say captions can be wrong']],
  he: [[/עלול(ות|ה)? (להכיל |ל)?(טעויות|לטעות)|יכול(ות|ה)? לטעות|לבלבל בין אנשים/, 'must say captions can be wrong'],
       [/האפליקציה והכתוביות באנגלית/, 'must say the app and its captions are in English (no Hebrew captions or screens yet)']]
}
// Hebrew captions or a Hebrew app may only be mentioned as not there yet.
export const NOT_YET = { he: /(?<!(אין|עדיין אין|עוד אין|לא|בלי) .{0,8})(כתוביות בעברית|אפליקציה בעברית|ממשק בעברית|תומכת בעברית)/ }
const homes = LANGS.filter((l) => l.pages.includes('index.html'))
for (const lang of homes) {
  const f = outPath(lang.code, 'index.html')
  // The demo plays the app's English script on every page, so only English pages are checked against it.
  const pageText = visible(read(f)) + (lang.code === 'en' ? ' ' + SCRIPT.map((s) => s.text || s.sound).join(' ') : '')
  check(BANNED_BY_LANG[lang.code] && MUST_SAY[lang.code], `${lang.code}: no honest-claims rules for this language in check-site.mjs`)
  for (const [re, why] of BANNED_BY_LANG[lang.code] || []) {
    const m = pageText.match(re)
    check(!m, `${f} ${why}: "${m?.[0]}"`)
  }
  // The home page no longer says "not a medical device" (owner, 2026-10-28: nobody reads it as one); it still makes no hearing claim.
  for (const [re, why] of MUST_SAY[lang.code] || []) check(re.test(pageText), `${f} ${why}`)
  if (NOT_YET[lang.code]) {
    for (const g of pages.filter((p) => langOf(p) === lang.code)) {
      const m = visible(read(g)).match(NOT_YET[lang.code])
      check(!m, `${g} claims the app works in ${lang.code} today: "${m?.[0]}"`)
    }
  }
}
// The Hebrew rules catch real claims and spare honest sentences.
check(BANNED_BY_LANG.he[0][0].test('האפליקציה מראה מי מדבר') && !BANNED_BY_LANG.he[0][0].test('היא לא יודעת מי האנשים'), 'BANNED he[0] self-test')
check(BANNED_BY_LANG.he[4][0].test('הורדה בחינם') && BANNED_BY_LANG.he[4][0].test('רק $2.99') && !BANNED_BY_LANG.he[4][0].test('$4.99 פעם אחת'), 'BANNED he[4] self-test')
check(BANNED_BY_LANG.he[3][0].test('משפרת את השמיעה') && !BANNED_BY_LANG.he[3][0].test('לאמא שלי, שכבדת שמיעה'), 'BANNED he[3] self-test')
check(NOT_YET.he.test('Seal מציגה כתוביות בעברית') && !NOT_YET.he.test('עדיין אין כתוביות בעברית'), 'NOT_YET he self-test')
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

// The language offer's button: page background on the accent.
for (const [mode, c] of [['light', light], ['dark', dark]]) check(ratio(c.bg, c.accent) >= 4.5, `lang.css ${mode}: offer button --bg on --accent ${ratio(c.bg, c.accent).toFixed(2)}:1 < 4.5`)

// 4. links and anchors, from each page's own folder
for (const f of pages) {
  const h = read(f)
  const dir = path.dirname(f)
  const ids = new Set([...h.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]))
  for (const m of h.matchAll(/\shref="([^"]+)"/g)) {
    const u = m[1]
    if (/^(https?:|mailto:|data:)/.test(u)) continue
    if (u.startsWith('#')) { check(ids.has(u.slice(1)), `${f}: anchor ${u} has no target`); continue }
    check(existsSync(path.join(SITE, dir, u.split('#')[0])), `${f}: link to missing file ${u}`)
  }
  for (const m of h.matchAll(/\s(?:src|srcset)="([^"]+)"/g)) {
    for (const u of m[1].split(',').map((x) => x.trim().split(' ')[0])) if (isLocal(u) && !u.startsWith('data:')) check(existsSync(path.join(SITE, dir, u)), `${f}: missing asset ${u}`)
  }
  for (const m of h.matchAll(/url\('?([^')]+)'?\)/g)) if (!m[1].startsWith('data:')) check(existsSync(path.join(SITE, dir, m[1])), `${f}: missing CSS asset ${m[1]}`)
}

// 4b. Every language (#207): lang and dir on every page; hreflang to each language the page has (and only to
// published ones from English); a draft is marked and not indexed; pictures of the app stay English.
for (const f of pages) {
  const m = read(f).match(/<html lang="([a-z-]+)" dir="(ltr|rtl)">/)
  const lang = LANGS.find((l) => l.code === langOf(f))
  check(m, `${f}: <html> needs lang and dir`)
  if (m && lang) check(m[1] === lang.code && m[2] === lang.dir, `${f}: lang/dir ${m[1]}/${m[2]}, expected ${lang.code}/${lang.dir}`)
}
for (const { lang, page, file } of built) {
  const h = read(file)
  const links = Object.fromEntries([...h.matchAll(/<link rel="alternate" hreflang="([^"]+)" href="([^"]+)">/g)].map((x) => [x[1], x[2]]))
  const want = alternatesFor(LANGS, lang, page)
  if (want.length > 1) {
    for (const l of want) check(links[l.code] === urlOf(l.code, page), `${file}: hreflang ${l.code} should be ${urlOf(l.code, page)} (is ${links[l.code]})`)
    check(links['x-default'] === urlOf('en', page), `${file}: hreflang x-default should be the English page`)
    check(/<nav class="lang-switch"/.test(h), `${file}: has other languages but no switcher`)
  } else check(!Object.keys(links).length && !/data-lang-choice/.test(h), `${file}: offers languages it shouldn't`)
  for (const code of Object.keys(links)) if (code !== 'x-default') check(LANGS.find((l) => l.code === code)?.pages.includes(page), `${file}: hreflang ${code} points at a page that isn't built`)
  if (lang.code === 'en') for (const l of LANGS.filter((x) => !x.published)) check(!h.includes(`hreflang="${l.code}"`), `${file}: links to the unpublished ${l.code} draft`)
  if (!lang.published) check(/<meta name="robots" content="noindex">/.test(h) && /class="draft-note"/.test(h), `${file}: a draft must say so and not be indexed`)
  if (lang.code !== 'en') check(!/\sdata-app(?! lang="en" dir="ltr")[\s>]/.test(h), `${file}: a picture of the app without lang="en" dir="ltr"`)
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

// 7 and 8, on the home page in every language (#207): the numbers are the same whatever the words around them.
const STATUS = { en: /(Planned|In testing)/, he: /(מתוכנן|בבדיקות)/ }
for (const home of homes) {
const f = outPath(home.code, 'index.html'), html = read(f)
check(STATUS[home.code], `${home.code}: no word for "Planned" / "In testing" in check-site.mjs`)
// 7. the home page's test results (#182) are the measured ones: each table cell matches its row in docs/perf
const tested = html.match(/<section[^>]*id="tested"[\s\S]*?<\/section>/)?.[0] || ''
check(tested, `${f} has the test results section (#tested)`)
const report = (f) => readFileSync(path.join(ROOT, 'docs', 'perf', f), 'utf-8')
const cell = (text, rowStart, col) => {
  const row = text.split('\n').find((l) => l.startsWith(rowStart))
  return row ? row.split('|')[col + 1].match(/\d+\.\d+/)?.[0] : undefined
}
const engines = report('engine-accuracy-comparison.md'), langs = report('language-accuracy-comparison.md')
const LANGS = ['Spanish', 'French', 'German']
const homeTables = [
  [cell(engines, '| apple-speechanalyzer |', 1), cell(engines, '| parakeet-fluidaudio (ultra-pal6) |', 1)],
  LANGS.flatMap((l) => [cell(langs, `| ${l} |`, 1), cell(langs, `| ${l} |`, 2)])
]
const shown = [...tested.matchAll(/<table class="data[^"]*"[^>]*data-bars[\s\S]*?<\/table>/g)]
  .map((t) => [...t[0].matchAll(/<td class="n">([^<]*)<\/td>/g)].map((m) => m[1]))
check(shown.length === homeTables.length, `${f} #tested: ${shown.length} bar tables, expected ${homeTables.length}`)
homeTables.forEach((want, i) => check(want.every(Boolean) && JSON.stringify(shown[i]) === JSON.stringify(want),
  `${f} #tested table ${i + 1} shows ${JSON.stringify(shown[i])}, the reports say ${JSON.stringify(want)}`))
const lat = (row) => engines.split('## Live latency')[1]?.split('\n').find((l) => l.startsWith(row))?.split('|')[3].trim()
for (const t of [lat('| parakeet-fluidaudio (ultra-pal6) |'), lat('| apple-speechanalyzer')]) check(t && visible(tested).includes(home.code === 'en' ? t : t.split(' ')[0]), `${f} #tested: latency ${t} missing`)

// 8. device tabs (#184)
const owner = (id) => ({ how: 'iphone', 'ipad-how': 'ipad', 'mac-how': 'mac' })[id] || null
check(deviceFor('', owner) === 'iphone' && deviceFor('#mac', owner) === 'mac' && deviceFor('#ipad', owner) === 'ipad', 'deviceFor: no hash is iPhone; a device name opens it')
check(deviceFor('#mac-how', owner) === 'mac' && deviceFor('#how', owner) === 'iphone', 'deviceFor: a link inside a device opens that device')
check(deviceFor('#faq', owner) === null, 'deviceFor: a shared part keeps the device you are on')
for (const d of DEVICES) check(new RegExp(`data-device="${d}"`).test(html) && new RegExp(`data-tab="${d}"`).test(html), `${f} has a tab and a part for ${d}`)
for (const l of TABLE_TALK) {
  const you = lineFor('you', l), them = lineFor('them', l)
  check(you.text === l.en && them.text === l.es, `lineFor: each half reads its own language ("${l.en}")`)
  check(you.translated === (l.side === 'them') && them.translated === (l.side === 'you'), `lineFor: only the other side's words are marked translated ("${l.en}")`)
}
// The iPad and Mac parts say where they are (Today, 1.0.1, Planned, In testing) before anything else.
for (const d of ['ipad', 'mac']) {
  const part = html.match(new RegExp(`<div data-device="${d}"[\\s\\S]*?<ol class="when"[\\s\\S]*?<\\/ol>`))?.[0] || ''
  check(/<li class="done">/.test(part) && STATUS[home.code]?.test(part), `${f} ${d}: the hero says where ${d} is`)
}
// The iPad's 19 translation scores are the measured ones, and each bar is as long as its score.
const langRows = readFileSync(path.join(ROOT, 'docs', 'perf', 'translation-languages-results.md'), 'utf-8').split('\n').filter((l) => /^\| [A-Z]/.test(l) && !l.startsWith('| Language'))
const measuredComet = langRows.map((l) => l.split('|')[5].trim()).sort()
const shownComet = [...html.matchAll(/<li(?: class="low")? style="--v:([\d.]+)">[\s\S]*?<span class="val">([\d.]+)<\/span><\/li>/g)]
check(JSON.stringify(shownComet.map((m) => m[2]).sort()) === JSON.stringify(measuredComet), `${f} iPad: translation scores ${shownComet.map((m) => m[2])} are not the report's ${measuredComet}`)
for (const [, v, c] of shownComet) check(Math.abs(+v - (+c - 0.75) / 0.2) < 0.001, `${f} iPad: the bar for ${c} is ${v} long`)
check(shownComet.filter(([, , c]) => +c >= 0.86).length === 18, `${f} iPad: "18 of 19" matches the scores`)

// The iPad's translation table: written rows from the comparison report, caption-style rows from its full results.
const trSum = report('translation-comparison.md'), trAll = report('translation-comparison-results.md')
const captionStyle = (pair, engine) => trAll.split(`## ${pair}`)[1]?.split('caption-style')[1]?.split('\n').find((l) => l.startsWith(`| ${engine} |`))?.split('|')[3].trim().split(' ')[0]
const ipadWant = ['en-es', 'en-fr', 'en-de'].flatMap((pr) => [
  ...[2, 3, 5].map((c) => cell(trSum, `| ${pr} | FLORES |`, c)),
  ...['apple', 'opus-mt', 'mlkit'].map((e) => captionStyle(pr, e))])
const ipadPart = html.match(/<section class="band" id="ipad-tested"[\s\S]*?<\/section>/)?.[0] || ''
const ipadShown = [...ipadPart.matchAll(/<td class="n">([^<]*)<\/td>/g)].map((m) => m[1])
check(ipadWant.every(Boolean) && JSON.stringify(ipadShown) === JSON.stringify(ipadWant), `${f} iPad translation table shows ${JSON.stringify(ipadShown)}, the reports say ${JSON.stringify(ipadWant)}`)
// Each device has its own questions, and only the iPhone part has the general sections.
for (const d of ['iphone', 'ipad', 'mac']) {
  const part = html.match(new RegExp(`<div data-device="${d}"[\\s\\S]*?(?=<div data-device=|<\\/main>)`))?.[0] || ''
  check((part.match(/data-faq/g) || []).length === 1, `${f} ${d}: has its own questions, once`)
  for (const id of ['story', 'private', 'easy', 'why', 'tested']) check((d === 'iphone') === part.includes(`id="${id}"`), `${f}: #${id} belongs to the iPhone part only (${d})`)
}
}

// 9. The CSS mirrors itself (#207): logical properties, so dir="rtl" flips a page. Physical left/right stays only where
// it is direction-neutral (centring with left: 50% and translateX(-50%)), inside a [dir="rtl"] override, or where a
// script places the element by physical coordinates; that last kind has a "physical:" comment on the line above.
const PHYSICAL = /(?:^|[\s;{])(?:(?:margin|padding|border)-(?:left|right)(?:-[a-z]+)?|left|right)\s*:|text-align:\s*(?:left|right)|float:\s*(?:left|right)/
export const physicalRules = (css) => css.split('\n').flatMap((line, i, all) => {
  const code = line.replace(/\/\*[\s\S]*?\*\//g, '')
  if (!PHYSICAL.test(code) || /\[dir=/.test(code) || /left:\s*50%[^}]*translateX\(-50%\)/.test(code) || /physical:/.test(all[i - 1] || '')) return []
  return [`${i + 1}: ${line.trim().slice(0, 90)}`]
})
check(physicalRules('a { margin-left: 1px }').length === 1 && physicalRules('a { margin-inline-start: 1px; text-align: start }').length === 0, 'physicalRules self-test')
check(physicalRules('a { left: 50%; transform: translateX(-50%) }').length === 0 && physicalRules('.x { text-align: right }').length === 1, 'physicalRules self-test: centring allowed, text-align caught')
check(physicalRules('/* physical: placed by offsetLeft */\n.p { left: 0 }').length === 0 && physicalRules('.p { inset-inline-start: 0; border-right: 0 }').length === 1, 'physicalRules self-test: a marked line is allowed')
const styleOf = (f) => f.endsWith('.css') ? read(f) : [...read(f).matchAll(/<style>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join('\n')
for (const f of [...pages, ...readdirSync(SITE).filter((p) => p.endsWith('.css'))]) {
  for (const r of physicalRules(styleOf(f))) check(false, `${f}: physical left/right, use a logical property: ${r}`)
}

if (failures.length) {
  console.error(`site check: ${failures.length} problem(s)\n- ${failures.join('\n- ')}`)
  process.exit(1)
}
console.log(`site check: ok (${pages.length} pages in ${LANGS.length} languages, ${THEMES.length} themes)`)
