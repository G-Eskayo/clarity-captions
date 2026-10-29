// Builds the website's pages from one source per page (#207): site-src/pages/<page>.html holds the markup with {{key}}
// where the words go, and site-src/lang/<code>.json holds each language's words. English is written to site/, every
// other language to site/<code>/. A new language is a translation file and a line in site-src/lang/languages.json.
// The sources live outside site/ so they aren't published with it.
//   node scripts/build-site.mjs           write the pages
//   node scripts/build-site.mjs --check   exit 1 if a page on disk isn't what the sources build (CI runs this)
//   node scripts/build-site.mjs --accept he   record that he.json matches today's English (after a translator's check)
// No dependencies. The output is plain static HTML, so the site is published the same way as before.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs'
import { createHash } from 'crypto'
import path from 'path'
import { fileURLToPath } from 'url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
export const SITE = path.join(ROOT, 'site')
export const SRC = path.join(ROOT, 'site-src')
export const ORIGIN = 'https://seal-speak.gileskayo.me/'
const readJSON = (f) => JSON.parse(readFileSync(path.join(SRC, f), 'utf-8'))

export const languages = () => readJSON('lang/languages.json')
export const strings = (code) => readJSON(`lang/${code}.json`)
export const hashOf = (text) => createHash('sha256').update(text).digest('hex').slice(0, 10)

// Where a page of a language lives, relative to site/, and its public address.
export const outPath = (code, page) => (code === 'en' ? page : `${code}/${page}`)
export const urlOf = (code, page) => ORIGIN + outPath(code, page).replace(/(^|\/)index\.html$/, '$1')

// The languages a visitor can be sent to from a page: English always; others once published. A draft language's own
// pages also list themselves, so the draft can be reviewed as it will be.
export const alternatesFor = (langs, lang, page) =>
  langs.filter((l) => l.pages.includes(page) && (l.published || l.code === lang.code))

const KEYS = /\{\{([^{}]+)\}\}/g
export const keysOf = (template) => [...template.matchAll(KEYS)].map((m) => m[1]).filter((k) => !k.startsWith('@'))

// Relative links from a page in site/<code>/: a page that exists in this language stays in it, anything else
// (English-only pages, scripts, styles, pictures) is one folder up.
export const relink = (html, lang) => {
  if (lang.code === 'en') return html
  const fix = (u) => (/^([a-z]+:|#|\/|\.\.\/)/i.test(u) || lang.pages.includes(u.split('#')[0]) ? u : '../' + u)
  // A link to a page this language doesn't have goes to the English one, and says so.
  html = html.replace(/<a(\s[^>]*?)?\shref="([^"]+\.html(?:#[^"]*)?)"/g, (m, pre, u) =>
    (/^([a-z]+:|\/|\.\.\/)/i.test(u) || lang.pages.includes(u.split('#')[0]) || /\shreflang=/.test(m) ? m : m + ' hreflang="en"'))
  return html
    .replace(/(\s(?:href|src)=")([^"]+)(")/g, (m, a, u, b) => a + fix(u) + b)
    .replace(/(<meta\s[^>]*?\scontent=")((?:assets|images)\/[^"]+)(")/g, (m, a, u, b) => a + fix(u) + b)
    .replace(/(\ssrcset=")([^"]+)(")/g, (m, a, v, b) => a + v.split(',').map((s) => s.trim().replace(/^\S+/, fix)).join(', ') + b)
    .replace(/url\((['"]?)([^'")]+)\1\)/g, (m, q, u) => `url(${q}${/^data:/.test(u) ? u : fix(u)}${q})`)
}

const hreflangLinks = (langs, lang, page) => {
  const alts = alternatesFor(langs, lang, page)
  if (alts.length < 2) return ''
  return [...alts.map((l) => `<link rel="alternate" hreflang="${l.code}" href="${urlOf(l.code, page)}">`),
    `<link rel="alternate" hreflang="x-default" href="${urlOf('en', page)}">`].join('\n') + '\n'
}

export function buildPage(langs, lang, page, words = strings(lang.code), english = strings('en')) {
  const template = readFileSync(path.join(SRC, 'pages', page), 'utf-8')
  const missing = []
  const special = {
    '@lang': lang.code,
    '@dir': lang.dir,
    '@alternates': hreflangLinks(langs, lang, page),
    '@robots': lang.published ? '' : '<meta name="robots" content="noindex">\n',
    // Until the owner publishes a language, its pages say they are a draft, aren't indexed, and nothing links to them.
    '@draft': lang.published ? '' : `<p class="draft-note" style="margin:0;padding:.6rem 1rem;background:#FBE8C1;color:#141419;text-align:center;font-weight:700">${words._draft || 'Draft'}</p>\n`
  }
  let html = template.replace(KEYS, (m, k) => {
    if (k in special) return special[k]
    if (typeof words[k] === 'string') return words[k]
    missing.push(k)
    return english[k] ?? m
  })
  if (lang.code !== 'en') html = html.replace(/\sdata-app(?=[\s>])/g, ' data-app lang="en" dir="ltr"')
  html = html.replace(/^<!doctype html>\n/i, (d) => `${d}<!-- Built by scripts/build-site.mjs from site-src/pages/${page} and site-src/lang/${lang.code}.json: edit those, not this. -->\n`)
  return { html: relink(html, lang), missing }
}

// A translation is stale when the English it was made from has changed since (recorded by --accept).
export const staleKeys = (code, english = strings('en')) => {
  if (code === 'en') return []
  const recorded = strings(code)._source || {}
  return Object.keys(english).filter((k) => k in strings(code) && recorded[k] !== hashOf(english[k]))
}

export function buildAll() {
  const langs = languages(), out = [], problems = []
  for (const lang of langs) {
    for (const page of lang.pages) {
      const { html, missing } = buildPage(langs, lang, page)
      if (missing.length) problems.push(`${lang.code}/${page}: no ${lang.code} text for ${missing.length} key(s): ${missing.slice(0, 5).join(', ')}`)
      out.push([outPath(lang.code, page), html])
    }
  }
  return { out, problems }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2)
  if (args[0] === '--accept') {
    const code = args[1], file = path.join(SRC, 'lang', `${code}.json`), en = strings('en'), tr = strings(code)
    tr._source = Object.fromEntries(Object.keys(en).filter((k) => k in tr).map((k) => [k, hashOf(en[k])]))
    writeFileSync(file, JSON.stringify(tr, null, 2) + '\n')
    console.log(`${code}: ${Object.keys(tr._source).length} translations recorded as matching today's English`)
    process.exit(0)
  }
  const { out, problems } = buildAll()
  if (problems.length) { console.error(problems.join('\n')); process.exit(1) }
  if (args[0] === '--check') {
    const stale = out.filter(([f, html]) => !existsSync(path.join(SITE, f)) || readFileSync(path.join(SITE, f), 'utf-8') !== html).map(([f]) => f)
    if (stale.length) { console.error(`site build: out of date, run node scripts/build-site.mjs: ${stale.join(', ')}`); process.exit(1) }
    console.log(`site build: ok (${out.length} pages)`)
  } else {
    for (const [f, html] of out) { mkdirSync(path.dirname(path.join(SITE, f)), { recursive: true }); writeFileSync(path.join(SITE, f), html) }
    console.log(`site build: wrote ${out.length} pages`)
  }
}
