// Tests for scripts/build-site.mjs (#207): node --test scripts/build-site.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'fs'
import path from 'path'
import { relink, keysOf, alternatesFor, outPath, urlOf, buildAll, languages, strings, SITE, SRC } from './build-site.mjs'

const he = { code: 'he', dir: 'rtl', published: false, pages: ['index.html', 'privacy.html'] }
const en = { code: 'en', dir: 'ltr', published: true, pages: ['index.html', 'privacy.html', 'versions.html'] }

test('relink: a page this language has stays in its folder; everything else is one folder up', () => {
  const html = '<a href="privacy.html#x">p</a><a href="versions.html">v</a><img src="assets/seal.svg"><script src="demo.js"></script>'
  assert.equal(relink(html, he), '<a href="privacy.html#x">p</a><a href="../versions.html" hreflang="en">v</a><img src="../assets/seal.svg"><script src="../demo.js"></script>')
})

test('relink: leaves addresses that are already absolute, anchors, mail and data alone', () => {
  const html = '<a href="#faq">a</a><a href="https://apps.apple.com/x">b</a><a href="mailto:a@b.c">c</a><a href="/top">d</a><a href="../x.html">e</a>'
  assert.equal(relink(html, he), html)
  assert.equal(relink("<div style=\"background:url('data:image/png;base64,AA')\">", he), "<div style=\"background:url('data:image/png;base64,AA')\">")
})

test('relink: srcset and CSS url() too', () => {
  assert.equal(relink('<img srcset="a.png 1x, b.png 2x">', he), '<img srcset="../a.png 1x, ../b.png 2x">')
  assert.equal(relink("<i style=\"background:url('assets/f.woff2')\">", he), "<i style=\"background:url('../assets/f.woff2')\">")
})

test('relink: a picture named in a meta tag, and links to English-only pages say they are English', () => {
  assert.equal(relink('<meta property="og:image" content="assets/seal.png">', he), '<meta property="og:image" content="../assets/seal.png">')
  assert.equal(relink('<a class="x" href="versions.html#engine">v</a><a href="privacy.html">p</a>', he), '<a class="x" href="../versions.html#engine" hreflang="en">v</a><a href="privacy.html">p</a>')
})

test('relink: English pages are untouched', () => {
  assert.equal(relink('<img src="assets/seal.svg">', en), '<img src="assets/seal.svg">')
})

test('keysOf: words, not the page hooks', () => {
  assert.deepEqual(keysOf('<html lang="{{@lang}}"><p>{{a.b}}</p><i title="{{c}}"></i>'), ['a.b', 'c'])
})

test('outPath and urlOf: English at the top, others in their folder; index is the folder itself', () => {
  assert.equal(outPath('en', 'index.html'), 'index.html')
  assert.equal(outPath('he', 'privacy.html'), 'he/privacy.html')
  assert.equal(urlOf('en', 'index.html'), 'https://seal-speak.gileskayo.me/')
  assert.equal(urlOf('he', 'index.html'), 'https://seal-speak.gileskayo.me/he/')
  assert.equal(urlOf('he', 'privacy.html'), 'https://seal-speak.gileskayo.me/he/privacy.html')
})

test('alternatesFor: a draft language is offered only from its own pages', () => {
  const langs = [en, he]
  assert.deepEqual(alternatesFor(langs, en, 'index.html').map((l) => l.code), ['en'])
  assert.deepEqual(alternatesFor(langs, he, 'index.html').map((l) => l.code), ['en', 'he'])
  assert.deepEqual(alternatesFor([en, { ...he, published: true }], en, 'index.html').map((l) => l.code), ['en', 'he'])
  assert.deepEqual(alternatesFor([en, { ...he, published: true }], en, 'versions.html').map((l) => l.code), ['en'], 'no Hebrew versions page, so none offered')
})

test('every language builds with no missing words, and every English word is used by a page', () => {
  const { problems, out } = buildAll()
  assert.deepEqual(problems, [])
  const used = new Set(languages()[0].pages.flatMap((p) => keysOf(readFileSync(path.join(SRC, 'pages', p), 'utf-8'))))
  assert.deepEqual(Object.keys(strings('en')).filter((k) => !k.startsWith('_') && !used.has(k)), [])
  assert.ok(out.length >= 4)
})

test('every built page says its language and direction', () => {
  for (const [f, html] of buildAll().out) {
    const lang = f.includes('/') ? f.split('/')[0] : 'en'
    const dir = languages().find((l) => l.code === lang).dir
    assert.match(html, new RegExp(`<html lang="${lang}" dir="${dir}">`), f)
  }
})

test('pictures of the app stay English on other languages\' pages', () => {
  const tpl = readFileSync(path.join(SRC, 'pages', 'index.html'), 'utf-8')
  assert.ok((tpl.match(/\sdata-app[\s>]/g) || []).length >= 5)
  for (const [f, html] of buildAll().out.filter(([f]) => f.includes('/'))) {
    assert.ok(!/\sdata-app(?! lang="en" dir="ltr")[\s>]/.test(html), `${f}: a picture of the app without lang="en"`)
  }
  assert.ok(!/data-app lang=/.test(readFileSync(path.join(SITE, 'index.html'), 'utf-8')))
})

test('a language that isn\'t published is invisible from English: no link, no hreflang, no switcher entry', () => {
  for (const l of languages().filter((x) => !x.published)) {
    for (const [f, html] of buildAll().out.filter(([f]) => !f.includes('/'))) {
      assert.ok(!html.includes(`hreflang="${l.code}"`) && !html.includes(`href="${l.code}/`) && !html.includes('data-lang-choice'), `${f} mentions ${l.code}`)
    }
  }
})

test('every page in a second language has the switcher, the offer, and links back that work from its folder', () => {
  for (const [f, html] of buildAll().out.filter(([f]) => f.includes('/'))) {
    assert.match(html, /<nav class="lang-switch"/, f)
    assert.match(html, /data-lang-offer[^>]*hidden/, `${f}: the offer starts hidden (no script, no offer)`)
    assert.match(html, /<script type="module" src="\.\.\/lang\.js">/, f)
    for (const m of html.matchAll(/data-lang-choice="en"/g)) assert.ok(m)
    assert.ok(!/href="\.\.\/\.\.\//.test(html), `${f}: a link went up two folders`)
  }
})
