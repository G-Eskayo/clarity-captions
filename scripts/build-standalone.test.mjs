// Tests for the single-file review copies (#265). Run after `node scripts/build-site.mjs`.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { rewriteLink, standalone } from './build-standalone.mjs'

test('sibling pages stay local, everything else goes to the live site', () => {
  assert.equal(rewriteLink('support.html', 'he'), 'seal-speak-he-support.html')
  assert.equal(rewriteLink('privacy.html#keep', 'he'), 'seal-speak-he-privacy.html#keep')
  assert.equal(rewriteLink('./', 'he'), 'seal-speak-he-home.html')
  assert.equal(rewriteLink('../', 'he'), 'https://seal-speak.gileskayo.me/')
  assert.equal(rewriteLink('../versions.html#engine', 'he'), 'https://seal-speak.gileskayo.me/versions.html#engine')
  assert.equal(rewriteLink('../support.html', 'he'), 'https://seal-speak.gileskayo.me/support.html')
  for (const keep of ['#faq', 'mailto:a@b.c', 'https://apps.apple.com/x']) assert.equal(rewriteLink(keep, 'he'), keep)
})

test('a built page has no relative refs, no external scripts and stays noindex', async (t) => {
  let esbuild
  for (const base of [process.cwd(), join(process.env.HOME, '.agents/dashboard')]) {
    try { esbuild = createRequire(join(base, 'package.json'))('esbuild'); break } catch { /* next */ }
  }
  if (!esbuild) return t.skip('esbuild not installed')
  for (const page of ['index', 'support', 'privacy']) {
    const html = await standalone('he', page, esbuild)
    assert.doesNotMatch(html, /(?:src|href)="\.\.?\//, page)
    assert.doesNotMatch(html, /<script[^>]+src=/, page)
    assert.doesNotMatch(html, /<link rel="stylesheet"/, page)
    assert.match(html, /<meta name="robots" content="noindex/, page)
    assert.match(html, /dir="rtl"/, page)
  }
})
