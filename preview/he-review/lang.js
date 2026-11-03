// The language offer and switcher (#207). Never redirects: on a page in a language other than the visitor's, it
// offers the page in theirs ("This page in עברית?"), and remembers the answer. The switcher is plain links, so it
// works without this script; the script only remembers which one was picked. Nothing leaves the browser.
const KEY = 'seal-speak-language'
const primary = (tag) => String(tag || '').toLowerCase().split('-')[0]

// The language to offer, or null. A remembered choice wins over the browser's list; with none, the first language in
// the browser's list that this page has.
export function offerFor({ pageLang, available, stored, browser }) {
  const has = (code) => available.includes(code)
  const preferred = stored ? (has(stored) ? stored : null) : (browser || []).map(primary).find(has) || null
  return preferred && preferred !== pageLang ? preferred : null
}

const recall = (storage) => { try { return storage.getItem(KEY) } catch { return null } }
const remember = (storage, code) => { try { storage.setItem(KEY, code) } catch { /* private browsing: just don't remember */ } }

export function init(doc, storage, nav) {
  const pageLang = primary(doc.documentElement.lang)
  const hrefs = Object.fromEntries([...doc.querySelectorAll('link[rel="alternate"][hreflang]')]
    .map((l) => [l.getAttribute('hreflang'), l.getAttribute('href')]).filter(([code]) => code !== 'x-default'))
  for (const a of doc.querySelectorAll('[data-lang-choice]')) a.addEventListener('click', () => remember(storage, a.dataset.langChoice))
  const box = doc.querySelector('[data-lang-offer]')
  const code = offerFor({ pageLang, available: Object.keys(hrefs), stored: recall(storage), browser: nav.languages })
  if (!box || !code) return
  const words = JSON.parse(doc.querySelector('[data-lang-words]')?.textContent || '{}')
  const theirs = words[code] || {}, ours = words[pageLang] || {}
  const q = doc.createElement('span')
  q.textContent = theirs.question || code
  q.setAttribute('lang', code)
  if (theirs.dir) q.setAttribute('dir', theirs.dir)
  const yes = doc.createElement('a')
  yes.textContent = theirs.yes || code
  // The switcher's relative link, so a copy of the site (a preview, a staging host) stays on itself.
  const rel = [...doc.querySelectorAll('[data-lang-choice]')].find((a) => a.dataset.langChoice === code)?.getAttribute('href')
  yes.setAttribute('href', rel ?? hrefs[code])
  yes.setAttribute('hreflang', code)
  yes.setAttribute('lang', code)
  if (theirs.dir) yes.setAttribute('dir', theirs.dir)
  yes.addEventListener('click', () => remember(storage, code))
  const no = doc.createElement('button')
  no.setAttribute('type', 'button')
  no.textContent = ours.stay || '×'
  no.addEventListener('click', () => { remember(storage, pageLang); box.hidden = true })
  box.append(q, yes, no)
  box.hidden = false
}

if (typeof document !== 'undefined') {
  let storage = null
  try { storage = globalThis.localStorage } catch { /* blocked by the browser */ }
  init(document, storage, navigator)
}
