// Tests for scripts/check-site.mjs (#279): node --test scripts/check-site.test.mjs
// Content regression: the built site no longer contains the dropped phrase.
// Integration tests: seed faults in a tmp copy of site/, verify check-site.mjs catches them.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execSync } from 'child_process'
import { readFileSync, writeFileSync, cpSync, rmSync, mkdtempSync } from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import { badRefLinks, refOk } from './check-site.mjs'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const SITE_DIR = path.join(ROOT, 'site')

// Content regression: 1.0.0 card no longer says "1.0.1 brings"
test('content regression: built 1.0.0 card no longer mentions 1.0.1 full-screen iPad layout', () => {
  const versions = readFileSync(path.join(SITE_DIR, 'versions.html'), 'utf-8')
  const id10card = versions.split('id="v1-0-0"')[1]?.split(/id="v1-/)[0] || ''
  assert.ok(id10card.length > 100, 'found the 1.0.0 card')
  assert.ok(!id10card.includes('1.0.1 brings'), 'the card no longer mentions 1.0.1 full-screen iPad layout')
})

// Integration tests: check-site.mjs catches seeded faults
const runCheckSite = (siteDir) => {
  try {
    execSync(`SITE_DIR="${siteDir}" node scripts/check-site.mjs`, { cwd: ROOT, stdio: 'pipe' })
    return null
  } catch (e) {
    return e.stdout.toString() + e.stderr.toString()
  }
}

test('integration: check-site.mjs catches a bad GitHub ref link (HEAD)', () => {
  const tmp = mkdtempSync(path.join(ROOT, 'tmp-'))
  try {
    cpSync(SITE_DIR, tmp, { recursive: true })
    const idx = path.join(tmp, 'index.html')
    writeFileSync(idx, readFileSync(idx, 'utf-8').replace('</body>', '<a href="https://github.com/G-Eskayo/clarity-captions/blob/HEAD/file">link</a>\n</body>'))
    const output = runCheckSite(tmp)
    assert.ok(output?.includes('HEAD'), `check-site caught the bad ref: ${output}`)
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
})

test('integration: check-site.mjs allows GitHub ref links to main and releases', () => {
  const tmp = mkdtempSync(path.join(ROOT, 'tmp-'))
  try {
    cpSync(SITE_DIR, tmp, { recursive: true })
    const idx = path.join(tmp, 'index.html')
    writeFileSync(idx, readFileSync(idx, 'utf-8').replace('</body>', '<a href="https://github.com/G-Eskayo/clarity-captions/blob/main/file">main</a><a href="https://raw.githubusercontent.com/G-Eskayo/clarity-captions/v1.0.0/file">v1.0.0</a>\n</body>'))
    const output = runCheckSite(tmp)
    assert.strictEqual(output, null, `check-site passed with allowed refs; output: ${output}`)
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
})

test('integration: check-site.mjs catches a bad GitHub ref in seal-data.js', () => {
  const tmp = mkdtempSync(path.join(ROOT, 'tmp-'))
  try {
    cpSync(SITE_DIR, tmp, { recursive: true })
    const dataFile = path.join(tmp, 'seal-data.js')
    writeFileSync(dataFile, readFileSync(dataFile, 'utf-8') + '\n// https://github.com/G-Eskayo/clarity-captions/blob/dev/something\n')
    const output = runCheckSite(tmp)
    assert.ok(output?.includes('dev'), `check-site caught the bad ref in seal-data.js: ${output}`)
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
})

// Unit tests for refOk and badRefLinks
test('refOk: main and version tags are ok, other refs are not', () => {
  assert.strictEqual(refOk('main'), true)
  assert.strictEqual(refOk('v1.0.0'), true)
  assert.strictEqual(refOk('v2.1.3'), true)
  assert.strictEqual(refOk('HEAD'), false)
  assert.strictEqual(refOk('dev'), false)
  assert.strictEqual(refOk('v1.0'), false)
  assert.strictEqual(refOk('feature/x'), false)
})

test('badRefLinks: extracts GitHub and raw.githubusercontent.com refs', () => {
  const hits = badRefLinks('https://github.com/G-Eskayo/clarity-captions/blob/dev/README.md and https://raw.githubusercontent.com/G-Eskayo/clarity-captions/feature/x/file.js')
  assert.strictEqual(hits.length, 2)
  assert.ok(hits[0].includes('dev'))
  assert.ok(hits[1].includes('feature/x'))
})

test('badRefLinks: ignores non-repo URLs', () => {
  const hits = badRefLinks('https://github.com/other/repo/blob/main/file and example.com/something')
  assert.strictEqual(hits.length, 0)
})
