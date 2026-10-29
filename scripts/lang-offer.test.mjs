// Tests for the language offer and switcher (site/lang.js, #207): node --test scripts/lang-offer.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { offerFor, init } from '../site/lang.js'

const both = ['en', 'he']

test('offerFor: offers the browser\'s language when this page is in another one', () => {
  assert.equal(offerFor({ pageLang: 'en', available: both, stored: null, browser: ['he-IL', 'en-US'] }), 'he')
  assert.equal(offerFor({ pageLang: 'he', available: both, stored: null, browser: ['en-GB'] }), 'en')
})

test('offerFor: nothing when the page is already in the browser\'s language', () => {
  assert.equal(offerFor({ pageLang: 'he', available: both, stored: null, browser: ['he'] }), null)
  assert.equal(offerFor({ pageLang: 'en', available: both, stored: null, browser: ['en-US', 'he'] }), null)
})

test('offerFor: goes down the browser\'s list to the first language the page has', () => {
  assert.equal(offerFor({ pageLang: 'he', available: both, stored: null, browser: ['fr-FR', 'en'] }), 'en')
  assert.equal(offerFor({ pageLang: 'en', available: both, stored: null, browser: ['fr-FR', 'de'] }), null)
})

test('offerFor: a remembered choice wins over the browser, and is never asked again on its own pages', () => {
  assert.equal(offerFor({ pageLang: 'en', available: both, stored: 'en', browser: ['he'] }), null, 'said no to Hebrew')
  assert.equal(offerFor({ pageLang: 'en', available: both, stored: 'he', browser: ['en'] }), 'he', 'chose Hebrew, landed on English')
  assert.equal(offerFor({ pageLang: 'he', available: both, stored: 'he', browser: ['en'] }), null)
})

test('offerFor: a remembered language this page doesn\'t have offers nothing (no falling back to the browser)', () => {
  assert.equal(offerFor({ pageLang: 'en', available: both, stored: 'de', browser: ['he'] }), null)
})

test('offerFor: survives junk', () => {
  assert.equal(offerFor({ pageLang: 'en', available: ['en'], stored: null, browser: undefined }), null)
  assert.equal(offerFor({ pageLang: 'en', available: both, stored: '', browser: ['', null, 'HE'] }), 'he')
})

// A small fake page: enough DOM for init().
function fakePage({ lang, alternates, browser, stored, storageThrows }) {
  const listeners = []
  const el = (tag, attrs = {}) => ({
    tag, attrs: { ...attrs }, children: [], hidden: false, textContent: '', dataset: {},
    setAttribute(k, v) { this.attrs[k] = String(v) }, getAttribute(k) { return this.attrs[k] ?? null },
    append(...c) { this.children.push(...c) }, addEventListener(ev, fn) { listeners.push([this, ev, fn]) }
  })
  const offer = el('p'); offer.hidden = true
  const choices = alternates.filter(([code]) => code !== lang).map(([code, , rel]) => { const a = el('a', { hreflang: code, href: rel }); a.dataset.langChoice = code; return a })
  const links = alternates.map(([code, href]) => el('link', { hreflang: code, href }))
  const store = new Map(stored ? [['seal-speak-language', stored]] : [])
  const storage = {
    getItem: (k) => { if (storageThrows) throw new Error('blocked'); return store.get(k) ?? null },
    setItem: (k, v) => { if (storageThrows) throw new Error('blocked'); store.set(k, v) }
  }
  const words = { en: { dir: 'ltr', question: 'This page in English?', yes: 'Yes, English', stay: 'No, stay in English' }, he: { dir: 'rtl', question: 'העמוד הזה בעברית?', yes: 'כן, בעברית', stay: 'לא, להישאר בעברית' } }
  const doc = {
    documentElement: { lang },
    querySelector: (s) => (s === '[data-lang-offer]' ? offer : s === '[data-lang-words]' ? { textContent: JSON.stringify(words) } : null),
    querySelectorAll: (s) => (s === 'link[rel="alternate"][hreflang]' ? links : s === '[data-lang-choice]' ? choices : []),
    createElement: (t) => el(t)
  }
  const click = (target) => listeners.filter(([t, ev]) => t === target && ev === 'click').forEach(([, , fn]) => fn({}))
  return { doc, storage, nav: { languages: browser }, offer, choices, store, click }
}

test('init: shows the offer in the offered language, with a link to that page and a way to stay', () => {
  const p = fakePage({ lang: 'he', alternates: [['en', 'https://x/', '../'], ['he', 'https://x/he/', '']], browser: ['en-US'] })
  init(p.doc, p.storage, p.nav)
  assert.equal(p.offer.hidden, false)
  const [q, yes, no] = p.offer.children
  assert.equal(q.textContent, 'This page in English?')
  assert.equal(q.getAttribute('lang'), 'en')
  assert.equal(q.getAttribute('dir'), 'ltr', 'its own direction, so the question mark sits at its end')
  assert.equal(yes.getAttribute('dir'), 'ltr')
  assert.equal(yes.getAttribute('href'), '../', 'the same relative link as the switcher, so it stays on this copy of the site')
  assert.equal(yes.getAttribute('hreflang'), 'en')
  assert.equal(no.textContent, 'לא, להישאר בעברית')
  p.click(no)
  assert.equal(p.offer.hidden, true)
  assert.equal(p.store.get('seal-speak-language'), 'he', 'staying is remembered')
})

test('init: accepting remembers the choice; it never navigates by itself', () => {
  const p = fakePage({ lang: 'en', alternates: [['en', 'https://x/'], ['he', 'https://x/he/']], browser: ['he'] })
  init(p.doc, p.storage, p.nav)
  p.click(p.offer.children[1])
  assert.equal(p.store.get('seal-speak-language'), 'he')
})

test('init: the switcher remembers what was picked', () => {
  const p = fakePage({ lang: 'en', alternates: [['en', 'https://x/', ''], ['he', 'https://x/he/', 'he/']], browser: ['en'] })
  init(p.doc, p.storage, p.nav)
  assert.equal(p.offer.hidden, true)
  p.click(p.choices[0])
  assert.equal(p.store.get('seal-speak-language'), 'he')
})

test('init: blocked storage still offers, and nothing throws', () => {
  const p = fakePage({ lang: 'en', alternates: [['en', 'https://x/'], ['he', 'https://x/he/']], browser: ['he'], storageThrows: true })
  assert.doesNotThrow(() => init(p.doc, p.storage, p.nav))
  assert.equal(p.offer.hidden, false)
  assert.doesNotThrow(() => p.click(p.offer.children[2]))
})

test('init: a page in one language does nothing', () => {
  const p = fakePage({ lang: 'en', alternates: [], browser: ['he'] })
  init(p.doc, p.storage, p.nav)
  assert.equal(p.offer.hidden, true)
})
