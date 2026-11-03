// Checks for the website in site/ (#44), no dependencies: node scripts/check-site.mjs
// 1. Nothing phones home: every script, stylesheet, image, font and CSS url() is local (or a data: URL).
// 2. Honest claims (docs/design/honest-claims-2026-10-10.md): no "who is speaking", naming speakers, speed promises,
//    reading or hearing benefits or "free" on the marketing page; and, on every page, no price but the real ones (PRICES).
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
import { FEATURES, OLD_TABS, featureFor, duoFrame, duoBlocks, duoChunks, DUO_TALK, DUO_CAPTIONS } from '../site/devices.js'
import { languages, outPath, urlOf, alternatesFor } from './build-site.mjs'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
// SITE_DIR checks a copy of site/ (used to prove the checks catch seeded faults).
const SITE = process.env.SITE_DIR || path.join(ROOT, 'site')
const failures = []
const check = (ok, msg) => { if (!ok) failures.push(msg) }
export const RELEASE_11_ONLY = ['ipad-full-screen', 'duo', 'parakeet', 'caption-languages', 'live-translation', 'face-to-face', 'in-your-ear']
// New caption languages ship as a batch (owner, 2026-11-03), so an upcoming release names no single language: it says
// "more caption languages". The measurements below the release cards may still name the language they measured.
export const SINGLE_LANGUAGE = /\b(Hebrew|Arabic|Spanish|French|German|Italian|Portuguese|Japanese|Korean|Chinese|Hindi|Russian)\b/

const LANGS = languages()
const built = LANGS.flatMap((lang) => lang.pages.map((page) => ({ lang, page, file: outPath(lang.code, page) })))
// Built pages in every language, plus any page made by hand (the gift page).
const pages = [...new Set([...built.map((b) => b.file), ...readdirSync(SITE).filter((f) => f.endsWith('.html'))])]
const read = (f) => readFileSync(path.join(SITE, f), 'utf-8')
const langOf = (f) => (f.includes('/') ? f.split('/')[0] : 'en')

// Every Hebrew string is in Hebrew (#235, owner 2026-11-03: translate, then review). The Hebrew pages are live, and an
// English string there is an untranslated placeholder. Only these stay in Latin script: product and engine names,
// numbers, a citation title, and a system version.
export const HE_LATIN_OK = new Set(['index.seal-speak', 'index.aa', 'index.psychophysics-of-reading-xi', 'index.apple', 'index.parakeet',
  'index.wer', 'index.parakeet-ultra-6-bit', 'index.parakeet-v2', 'index.sherpa-onnx', 'index.apple-speechanalyzer-1-0', 'index.iphone-12',
  'index.70-ms', 'index.opus-mt', 'index.google-ml-kit', 'index.facetime', 'index.zoom', 'index.teams', 'index.google-meet', 'index.whatsapp',
  'index.github', 'index.f-dev-iphone', 'index.f-dev-ipad', 'index.f-dev-duo', 'index.f-dev-mac', 'index.f-t-need-duo'])
{
  const he = JSON.parse(readFileSync(path.join(ROOT, 'site-src', 'lang', 'he.json'), 'utf-8'))
  const strings = (o, pre = '') => Object.entries(o).flatMap(([k, v]) => (typeof v === 'string' ? [[pre + k, v]] : v && typeof v === 'object' ? strings(v, `${pre}${k}.`) : []))
  for (const [k, v] of strings(he)) {
    if (HE_LATIN_OK.has(k) || k.startsWith('_prices.')) continue   // prices are checked with the pages below
    check(/[֐-׿]/.test(v), `he.json ${k}: no Hebrew in it ("${v.slice(0, 60)}"); translate it, or add it to HE_LATIN_OK if it's a name or a number`)
  }
  for (const k of HE_LATIN_OK) check(k in he && !/[֐-׿]/.test(he[k]), `HE_LATIN_OK ${k}: gone or now Hebrew; take it off the list`)
}

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
// The real prices (owner, 2026-10-30, #228). The app is $4.99 once (ADR 0007). Live Translation is $4.99 on iPhone, iPad
// and iPhone Duo, and $1.99 on the Mac, which is its own app (ADR 0028). Pages name no other price, and $1.99 only for
// the Mac. The StoreKit file and the app's debug fake store use the iOS price (section 10).
export const PRICES = { app: '4.99', translationIOS: '4.99', translationMac: '1.99' }
// Each storefront shows its own prices (owner, 2026-11-03): the English pages in dollars, the Hebrew pages in shekels,
// from one _prices table per language file (Israel: ₪14.90 is Seal Speak's live App Store price, the $4.99 point;
// ₪4.90 is the $1.99 point on all 59 sampled apps). Every amount on a page is one of its language's prices, in its currency.
export const CURRENCY = { en: "$", he: "\u20aa" }
export const ANY_AMOUNT = /(?:\$|\u20aa|US\$)\s?\d[\d.,]*|\d[\d.,]*\s?(?:\u20aa|ש"ח|ש״ח|דולר|שקל|usd|dollars|ils|nis)(?![A-Za-z])/gi
export const pricesOf = (code) => JSON.parse(readFileSync(path.join(ROOT, "site-src", "lang", `${code}.json`), "utf-8"))._prices || {}
export const amountsIn = (text) => [...text.matchAll(ANY_AMOUNT)].map((m) => m[0].replace(/[.,]+$/, ""))
// Each $1.99 must be said of the Mac: the devices named in its clause are all the Mac, or, when its clause names none,
// the first device after it in its sentence (else the last one before it) is. Returns the sentences that break this.
const DEVICE_WORDS = /\b(iPhone|iPad|Duo|Mac)\b/g
export function macPriceProblems(text, macPrice = "$1.99") {
  const MAC = new RegExp(macPrice.replace(/[$.]/g, (c) => "\\" + c) + "(?![\\d])", "g")
  const bad = []
  for (const sentence of text.split(/(?<=[.!?])\s+/)) {
    let at = 0
    for (const clause of sentence.split(/(?<=[,;:])\s+/)) {
      at = sentence.indexOf(clause, at)
      for (const m of clause.matchAll(MAC)) {
        const named = [...clause.matchAll(DEVICE_WORDS)].map((d) => d[1])
        const i = at + m.index
        const device = named.length ? (named.every((d) => d === 'Mac') ? 'Mac' : 'other')
          : [...sentence.slice(i).matchAll(DEVICE_WORDS)][0]?.[1] ?? [...sentence.slice(0, i).matchAll(DEVICE_WORDS)].at(-1)?.[1]
        if (device !== 'Mac') bad.push(sentence.trim())
      }
    }
  }
  return bad
}
const BANNED = [
  [/(?<!(n't|not|never) )(shows|tells|see|knows?) who|(?<!(n't|not|never) .{0,20})who('s| is) (speaking|talking)/i, 'claims to know who is speaking'],
  [/name (each|the|a|your) (speaker|voice)|naming speakers|give .{0,20} a name/i, 'mentions naming speakers (removed in v1)'],
  [/within (a|one) second|instant(ly)? caption|real[- ]time accuracy|100 ?%|every word/i, 'promises speed or accuracy'],
  [/improves? (your )?reading|helps? (you )?(read|hear)|hearing loss|treat|cure|better hearing/i, 'makes a reading or hearing claim'],
  [/\bfree\b/i, 'mentions "free"']
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
    [/חינם|בחינם|ללא תשלום/, 'mentions "free"']
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
check(BANNED_BY_LANG.he[4][0].test('הורדה בחינם') && !BANNED_BY_LANG.he[4][0].test('$4.99 פעם אחת'), 'BANNED he[4] self-test')
check(BANNED_BY_LANG.he[3][0].test('משפרת את השמיעה') && !BANNED_BY_LANG.he[3][0].test('לאמא שלי, שכבדת שמיעה'), 'BANNED he[3] self-test')
check(NOT_YET.he.test('Seal מציגה כתוביות בעברית') && !NOT_YET.he.test('עדיין אין כתוביות בעברית'), 'NOT_YET he self-test')
// A Hebrew string is Hebrew throughout (#264): no English sentence glued to a Hebrew one, as index.f-cap-for once was
// ("For iPhone 12 or newer, … Full-screen iPad and iPhone Duo: האפליקציה…"). Product names and code are fine; an English
// function word inside a string that also has Hebrew is the tell. Citations keep their English titles.
export const MIXED_ENGLISH = /(^|[^A-Za-z])(and|the|or|for|on|in|of|to|with|is|it|are|you|your|from|at|no|once|runs|newer|later)(?=[^A-Za-z]|$)/i
const HEBREW = /[֐-׿]/
for (const lang of LANGS.filter((l) => l.code === 'he')) {
  const strings = JSON.parse(readFileSync(path.join(ROOT, 'site-src', 'lang', 'he.json'), 'utf-8'))
  for (const [k, v] of Object.entries(strings)) {
    if (typeof v !== 'string' || k.startsWith('index.source-') || !HEBREW.test(v)) continue
    // The app's own English labels, marked <bdi lang="en">, are quoted on purpose (the app is in English).
    const m = v.replace(/<bdi lang="en">[\s\S]*?<\/bdi>/g, ' ').replace(/<[^>]+>|&[a-z]+;/g, ' ').match(MIXED_ENGLISH)
    check(!m, `he.json ${k}: mixes an English sentence into the Hebrew ("${m?.[2]}"); translate it`)
  }
  // The "Coming in 1.1" pills on the Hebrew page are Hebrew too.
  for (const k of ['index.f-in-11', 'index.f-in-11-lower']) check(HEBREW.test(strings[k] || ''), `he.json ${k}: the 1.1 pill isn't in Hebrew`)
}
check(MIXED_ENGLISH.test('For iPhone 12 or newer. האפליקציה') && !MIXED_ENGLISH.test('iPhone 12 ומעלה עם iOS 26 ואילך') && !MIXED_ENGLISH.test('ב-iPad במסך מלא ו-iPhone Duo'), 'MIXED_ENGLISH self-test')
// The banned patterns must catch real claims and spare honest disclaimers.
check(BANNED[0][0].test('Seal shows who is speaking') && !BANNED[0][0].test("It doesn't know who anyone is"), 'BANNED[0] self-test')
check(BANNED[4][0].test('Free for everyone') && !BANNED[4][0].test('freedom'), 'BANNED[4] self-test')
// Prices, on every page in every language (#228): only $4.99 and $1.99, and $1.99 only for the Mac.
check(JSON.stringify(amountsIn('Only $2.99, or $4.999. רק 5 דולר, 14.90 ₪ או ₪14.90.')) === JSON.stringify(['$2.99', '$4.999', '5 דולר', '14.90 ₪', '₪14.90']), 'amountsIn finds every amount, either currency, either side')
check(macPriceProblems('ו-₪4.90 ב-Mac.', '₪4.90').length === 0 && macPriceProblems('₪4.90 ב-iPhone.', '₪4.90').length === 1, 'macPriceProblems works in shekels')
check(macPriceProblems('An optional add-on: $4.99 on iPhone, iPad and iPhone Duo, and $1.99 on the Mac.').length === 0, 'macPriceProblems: $1.99 on the Mac is fine')
check(macPriceProblems('On the Mac it is $1.99, on the iPhone $4.99.').length === 0 && macPriceProblems('$1.99, once, in the Mac app.').length === 0, 'macPriceProblems: the Mac before or after, in another clause')
check(macPriceProblems('Live translation, right on your phone. An add-on: $1.99, once, on your iPhone.').length === 1, 'macPriceProblems: $1.99 for the iPhone is caught')
check(macPriceProblems('It is an optional add-on: $1.99, once.').length === 1 && macPriceProblems('$1.99 on iPad and Mac.').length === 1, 'macPriceProblems: no device, or not only the Mac, is caught')
for (const f of pages) {
  const text = visible(read(f)), code = langOf(f), table = pricesOf(code), allowed = Object.values(table)
  for (const a of amountsIn(text)) {
    check(a.startsWith(CURRENCY[code]), `${f} shows "${a}"; ${code} pages show prices in ${CURRENCY[code]}`)
    check(allowed.includes(a), `${f} names "${a}", not one of ${code}.json's _prices (${allowed.join(', ')})`)
  }
  for (const s of macPriceProblems(text, table.translationMac)) check(false, `${f} says ${table.translationMac} for something other than the Mac: "${s}"`)
  if (f === pages[0]) {
    // The US table is the StoreKit price (section 10); every language has a whole table in its own currency.
    const us = pricesOf('en')
    check(us.app === `$${PRICES.app}` && us.translationIOS === `$${PRICES.translationIOS}` && us.translationMac === `$${PRICES.translationMac}` && us.macApp === `$${PRICES.app}`, `en.json _prices don't match PRICES (${JSON.stringify(us)})`)
    for (const l of LANGS) {
      const t = pricesOf(l.code)
      check(['app', 'translationIOS', 'translationMac', 'macApp'].every((k) => (t[k] || '').startsWith(CURRENCY[l.code] || '?')), `${l.code}.json _prices: needs app, translationIOS, translationMac and macApp, all in ${CURRENCY[l.code]}`)
    }
  }
}
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

// 8. feature tabs (#235, were device tabs in #184): the pills are features; old device addresses still land
const owner = (id) => ({ how: 'captions', 'translation-languages': 'translation', 'mac-ring': 'calls' })[id] || null
check(featureFor('', owner) === 'captions' && featureFor('#calls', owner) === 'calls' && featureFor('#translation', owner) === 'translation', 'featureFor: no hash is captions; a feature name opens it')
check(featureFor('#mac-ring', owner) === 'calls' && featureFor('#how', owner) === 'captions', 'featureFor: a link inside a feature opens that feature')
check(featureFor('#iphone', owner) === 'captions' && featureFor('#ipad', owner) === 'translation' && featureFor('#mac', owner) === 'calls', 'featureFor: the old device tabs open a feature')
check(featureFor('#faq', owner) === null, 'featureFor: a shared part keeps the feature you are on')
for (const d of FEATURES) check(new RegExp(`data-feature="${d}"`).test(html) && new RegExp(`data-tab="${d}"`).test(html), `${f} has a tab and a part for ${d}`)
check(Object.values(OLD_TABS).every((t) => FEATURES.includes(t)), 'OLD_TABS: every old device tab lands on a feature')
// The iPhone Duo scroll (#258): folded at the top, open, then split at the end, the same frames backwards, and one
// step's words showing at a time at each end.
{
  const at = (p) => duoFrame(p)
  const ps0 = () => [...Array(101).keys()].map((i) => i / 100)
  check(at(0).state === 'folded' && at(0).fold === 1 && at(0).split === 0, 'duoFrame: starts folded, not split')
  check(at(0.25).state === 'opening' && Math.abs(at(0.25).fold - 0.5) < 0.01 && at(0.25).land === 0 && at(0.25).lit === 0, `duoFrame: halfway open at 0.25, inner screen still dark (fold ${at(0.25).fold})`)
  check(at(0.45).state === 'open' && at(0.45).land === 1 && at(0.45).turn === 0, 'duoFrame: open flat in landscape, Face to face offered, as the simulator showed')
  check(at(0.48).press === 1 && at(0.48).state === 'open', 'duoFrame: the touch on Face to face comes while it is still landscape')
  check(at(0.7).state === 'choosing' && at(0.7).turn === 1 && at(0.7).lit === 1 && at(0.7).split === 0, 'duoFrame: upright, each half picking its language, before the split')
  check(ps0().every((p) => (duoFrame(p).lit === 0 && duoFrame(p).land === 0) || duoFrame(p).fold === 0), 'duoFrame: the inner screen only lights once the Duo is open')
  check(at(1).state === 'split' && at(1).fold === 0 && at(1).split === 1, 'duoFrame: ends open and split')
  check(at(0).steps.join() === '1,0,0' && at(1).steps.join() === '0,0,1' && at(0.45).steps[1] === 1, 'duoFrame: one step at a time')
  const ps = [...Array(101).keys()].map((i) => i / 100), folds = ps.map((p) => at(p).fold), splits = ps.map((p) => at(p).split)
  check(folds.every((v, i) => i === 0 || v <= folds[i - 1]) && splits.every((v, i) => i === 0 || v >= splits[i - 1]), 'duoFrame: unfolds and splits steadily, never back and forth')
  check(ps.every((p) => at(p).split === 0 || at(p).fold === 0), 'duoFrame: the split only shows on the opened Duo, as in the app')
  check(at(0.69).pickYou === 0 && at(0.72).pickYou === 1 && at(0.72).pickThem === 0 && at(0.8).pickThem === 1, 'duoFrame: your half picks English, then theirs picks Español, before the split')
}
check(/data-duo-stills/.test(html) && /class="duo-fold-still"/.test(html) && /class="duo-open-still"/.test(html), `${f}: the Duo has its two still pictures for Reduce Motion`)
// Reduce Motion's two stills are the simulator's own screenshots; the moving Duo's screens are live, like the other demos.
for (const img of ['outer-captions.jpg', 'inner-split.jpg']) check(html.includes(`assets/duo/${img}`), `${f}: the Duo's still shows the app's screenshot ${img}`)
for (const dx of ['outer', 'land', 'port']) check(html.includes(`data-dx="${dx}"`), `${f}: the Duo has its live ${dx} screen`)
// The live Duo plays the app's own demo lines: what each half shows follows the app's rules.
{
  const you = duoBlocks(DUO_TALK, 3, { i: 3, text: 'Do I buy' }, 'you'), them = duoBlocks(DUO_TALK, 3, { i: 3, text: 'Do I buy' }, 'them')
  check(you[0].tr && !you[1].tr && you[2].tr && you[3].vol, 'duoBlocks: your half shows your own words as said and theirs translated')
  check(!them[0].tr && them[1].tr && !them[2].tr && them[3].vol && them[3].said === 'Do I buy', 'duoBlocks: their half mirrors it; a line still being said stays as said')
  const one = duoBlocks(DUO_CAPTIONS, DUO_CAPTIONS.length, null)
  check(one.at(-1).vol && one.at(-1).said.startsWith('Bueno') && one[0].tr === 'Is it on? Say something so we can see.', 'duoBlocks: one-way, finished lines are translated; the unfinished one stays as said')
  check(JSON.stringify(duoChunks('one two three four five six seven')) === JSON.stringify(chunksOf('one two three four five six seven')), 'duoChunks: the same 3 words at a time as the demo')
}
check(!/class="ds[ "-]/.test(html), `${f}: no drawn app screens in the Duo`)
// Gil, 2026-11-03: Seal Speak's dividing line sits exactly in the middle of the Duo's 951 pt inner screen, and the
// device art draws no line of its own at the hinge (the real inner screen is one piece).
{
  const css = readFileSync(path.join(SITE, 'devices.css'), 'utf-8')
  const mid = css.match(/\.dx-mid \{ top: ([\d.]+)px;[^}]*height: ([\d.]+)px/)
  check(mid && +mid[1] + +mid[2] / 2 === 951 / 2, `devices.css: the face-to-face line is centred on the Duo's inner screen (${mid?.[1]} + ${mid?.[2]}/2 vs 475.5)`)
  for (const sel of ['.duo-base', '.duo-face']) check(!new RegExp(`\\${sel} \\{[^}]*inset 0 0 0`).test(css), `devices.css: ${sel} draws no ring, so nothing shows at the hinge`)
  check(/class="duo-whole"/.test(html), `${f}: the open Duo shows one whole screen, not two halves with a seam`)
}
// Every old per-device section id (#184) is still an anchor on the page, so links into it keep working.
for (const id of ['ipad-screen', 'ipad-languages', 'ipad-tested', 'ipad-faq', 'mac-apps', 'mac-room', 'mac-ring', 'mac-tested', 'mac-faq', 'how', 'faq', 'private', 'easy', 'why', 'tested', 'story'])
  check(new RegExp(`\\sid="${id}"`).test(html), `${f}: the old anchor #${id} has no target`)
// The iPad's face to face is the app's own (#258 parity): its still is the simulator's screenshot, and the live screen
// plays the same split as the Duo.
check(html.includes('assets/ipad/face-to-face.jpg') && html.includes('data-dx="pad"'), `${f}: the iPad shows the app's face to face, still and live`)
// No status bars on any device (owner, 2026-11-03): no frozen 9:41, no app name, no carrier. The stills have theirs painted out.
for (const [name, text] of [[f, html], ['devices.js', read('devices.js')], ['devices.css', read('devices.css')]]) {
  check(!/9:41|dx-(time|clock|ring)\b|statusBar\(/.test(text.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, '')), `${name}: draws a status bar; devices on the site have none`)
}
// Each feature says which devices it works on, and the device list has a row for each feature.
for (const d of FEATURES) {
  const part = html.match(new RegExp(`<div data-feature="${d}"[\\s\\S]*?(?=<div data-feature=|<!-- shared -->)`))?.[0] || ''
  check(/<ul class="works-on"/.test(part), `${f} ${d}: says which devices it works on`)
}
const deviceList = html.match(/<section[^>]*id="devices"[\s\S]*?<\/section>/)?.[0] || ''
check((deviceList.match(/<tr data-row=/g) || []).length === FEATURES.length, `${f} #devices: one row per feature`)
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
// The caption sections live in the captions part; privacy, the device list and questions are shared, once.
const capPart = html.match(/<div data-feature="captions"[\s\S]*?(?=<div data-feature=)/)?.[0] || ''
for (const id of ['story', 'how', 'easy', 'why', 'tested']) check(capPart.includes(`id="${id}"`), `${f}: #${id} belongs to the captions part`)
const shared = html.split('<!-- shared -->')[1] || ''
for (const id of ['devices', 'private', 'faq']) check(shared.includes(`id="${id}"`) && !/data-feature=/.test(shared), `${f}: #${id} is shared, after the feature parts`)
check((html.match(/data-faq/g) || []).length === 1, `${f}: one set of questions`)
// "Coming in 1.1" (owner, 2026-11-03): the site went live while the App Store had 1.0, so everything 1.0 lacks wears
// the label. RELEASE_11_ONLY is what App Store build 1.0 (5), commit bc3b6623, does not have: it is iPhone-only
// (TARGETED_DEVICE_FAMILY 1), English captions from Apple's engine, no TranslationCenter, FaceToFaceView,
// CaptionLanguageCenter, EarCenter, Parakeet or StoreKit. Each label names one of these, and each one is labelled.
const labels = [...html.matchAll(/<[a-z]+[^>]*data-in="1\.1"[^>]*>/g)].map((m) => m[0])
for (const tag of labels) {
  const feat = tag.match(/data-feat="([^"]+)"/)?.[1]
  check(RELEASE_11_ONLY.includes(feat), `${f}: a "Coming in 1.1" label names ${feat || 'no feature'}, which isn't on the 1.1-only list`)
}
for (const feat of RELEASE_11_ONLY) check(labels.some((t) => t.includes(`data-feat="${feat}"`)), `${f}: ${feat} isn't in App Store 1.0 but has no "Coming in 1.1" label`)
}

// 10. The app's prices (#228): the StoreKit file sells Live Translation at the iOS price, not shared with family (the
// owner, 2026-10-30: each person buys their own); the debug fake store shows the same price; no other Swift or string
// file hard-codes a price, so the app shows StoreKit's.
{
  const storekit = JSON.parse(readFileSync(path.join(ROOT, 'Apps/Spike/StoreKit/SealSpeak.storekit'), 'utf-8'))
  const translation = storekit.products.find((p) => p.productID === 'com.gileskayo.captions.translation')
  check(translation?.displayPrice === PRICES.translationIOS, `SealSpeak.storekit: Live Translation is ${translation?.displayPrice}, not ${PRICES.translationIOS}`)
  check(translation?.familyShareable === false, 'SealSpeak.storekit: Live Translation must not be shared with family')
  const fake = `price = "$${PRICES.translationIOS}"`
  for (const f of readdirSync(path.join(ROOT, 'Apps'), { recursive: true }).filter((f) => /\.(swift|xcstrings|strings)$/.test(f))) {
    const lines = readFileSync(path.join(ROOT, 'Apps', f), 'utf-8').split('\n')
    if (f.endsWith('TranslationCenter.swift')) check(lines.some((l) => l.includes('DemoMode.fakeStore') && l.includes(fake)), `Apps/${f}: the fake store's price must be ${fake}`)
    for (const [i, l] of lines.entries()) {
      if (/"[^"]*(\$\s?\d+[.,]\d\d|\d[.,]\d\d\s?(\$|USD|€|£))[^"]*"/.test(l) && !(l.includes('DemoMode.fakeStore') && l.includes(fake))) check(false, `Apps/${f}:${i + 1} hard-codes a price; show StoreKit's displayPrice`)
    }
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

// Upcoming releases name no single caption language (see SINGLE_LANGUAGE).
for (const f of pages.filter((p) => p.endsWith('versions.html'))) {
  for (const [, id] of read(f).matchAll(/<div class="version" id="(v1-[2-9])"/g)) {
    const cards = read(f).split(`id="${id}"`)[1]?.split(/id="science"|<div class="version"/)[0] || ''
    const m = visible(cards).match(SINGLE_LANGUAGE)
    check(!m, `${f} ${id}: an upcoming release names one language ("${m?.[0]}"); say "more caption languages"`)
  }
}
check(SINGLE_LANGUAGE.test('Hebrew captions') && !SINGLE_LANGUAGE.test('More caption languages'), 'SINGLE_LANGUAGE self-test')

if (failures.length) {
  console.error(`site check: ${failures.length} problem(s)\n- ${failures.join('\n- ')}`)
  process.exit(1)
}
console.log(`site check: ok (${pages.length} pages in ${LANGS.length} languages, ${THEMES.length} themes)`)
