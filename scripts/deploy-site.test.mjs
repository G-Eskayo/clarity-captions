// Tests for deploy-site infrastructure (#N): node --test scripts/deploy-site.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, existsSync } from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')

test('build-site.mjs exports DOMAIN and includes CNAME in buildAll output', () => {
  const src = readFileSync(path.join(ROOT, 'scripts/build-site.mjs'), 'utf-8')
  assert.match(src, /export const DOMAIN = new URL\(ORIGIN\)\.hostname/, 'DOMAIN is exported')
  assert.match(src, /out\.push\(\['CNAME'/, 'CNAME is pushed into output')
})

test('check-site.mjs uses recursive directory reading', () => {
  const src = readFileSync(path.join(ROOT, 'scripts/check-site.mjs'), 'utf-8')
  assert.match(src, /readdirSync\(SITE, \{ recursive: true \}\)/, 'uses recursive: true')
})

test('check-site.mjs includes unlisted-pages checks', () => {
  const src = readFileSync(path.join(ROOT, 'scripts/check-site.mjs'), 'utf-8')
  assert.match(src, /unlisted page must carry noindex/, 'checks for noindex on unlisted pages')
  assert.match(src, /links to unlisted page/, 'checks that built pages don\'t link to unlisted ones')
})

test('check-site.mjs includes redirect-target checks', () => {
  const src = readFileSync(path.join(ROOT, 'scripts/check-site.mjs'), 'utf-8')
  assert.match(src, /redirect target/, 'checks redirect targets exist')
})

test('deploy-site.yml exists and runs on main push with correct paths', () => {
  const src = readFileSync(path.join(ROOT, '.github/workflows/deploy-site.yml'), 'utf-8')
  assert.match(src, /on:\s+push:\s+branches: \[main\]/, 'runs on main push')
  assert.match(src, /paths:/, 'has paths filter')
  assert.match(src, /- 'site\/\*\*'/, 'includes site/**')
  assert.match(src, /- 'site-src\/\*\*'/, 'includes site-src/**')
})

test('deploy-site.yml builds and deploys to GitHub Pages', () => {
  const src = readFileSync(path.join(ROOT, '.github/workflows/deploy-site.yml'), 'utf-8')
  assert.match(src, /\.github\/run-check\.sh site/, 'runs the site check')
  assert.match(src, /actions\/upload-pages-artifact/, 'uploads pages artifact')
  assert.match(src, /actions\/deploy-pages/, 'deploys to pages')
})

test('redirect pages exist at preview/he-review paths', () => {
  const redirects = [
    'site/preview/he-review/index.html',
    'site/preview/he-review/privacy.html',
    'site/preview/he-review/support.html',
    'site/preview/he-review/versions.html',
    'site/preview/he-review/for-mom-8089b966.html',
    'site/preview/he-review/he/index.html',
    'site/preview/he-review/he/privacy.html',
    'site/preview/he-review/he/support.html'
  ]
  for (const r of redirects) {
    assert.ok(existsSync(path.join(ROOT, r)), `${r} exists`)
  }
})

test('redirect pages carry noindex and meta refresh', () => {
  const redirects = [
    { file: 'site/preview/he-review/index.html', target: '/he/' },
    { file: 'site/preview/he-review/privacy.html', target: '/he/privacy.html' },
    { file: 'site/preview/he-review/he/index.html', target: '/he/' }
  ]
  for (const { file, target } of redirects) {
    const html = readFileSync(path.join(ROOT, file), 'utf-8')
    assert.match(html, /noindex, nofollow/, `${file} has noindex`)
    assert.match(html, new RegExp(`refresh.*${target.replace(/\//g, '\\/')}`, 's'), `${file} redirects to ${target}`)
  }
})

test('korea beta page has honest-claims rewording', () => {
  const html = readFileSync(path.join(ROOT, 'site/beta/korea/index.html'), 'utf-8')
  assert.match(html, /noindex, nofollow/, 'has noindex, nofollow')
  assert.ok(!html.includes('free in TestFlight'), 'does not say free')
  assert.ok(!html.includes('within a second or two'), 'does not say within a second or two')
  assert.match(html, /is a paid feature/, 'explains the paid feature')
  assert.match(html, /appears quickly/, 'uses safer timing language')
})
