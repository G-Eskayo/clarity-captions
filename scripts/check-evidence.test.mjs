// Tests for check-evidence.mjs (#210): node --test scripts/check-evidence.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'fs'
import { tmpdir } from 'os'
import path from 'path'
import { problems, combined } from './check-evidence.mjs'

const FIELDS = '- **Source:** a\n- **What we took:** b\n- **Confidence:** Ours\n- **Drives:** #1\n- **Public use:** Yes\n'

function folder(files) {
  const dir = mkdtempSync(path.join(tmpdir(), 'evidence-'))
  for (const [name, text] of Object.entries(files)) writeFileSync(path.join(dir, name), text)
  return dir
}

test('a numbered entry and a dated entry both pass', () => {
  const dir = folder({
    'E01-old-entry.md': `# E1. Old entry\n\n${FIELDS}`,
    '2026-10-29-new-entry.md': `# New entry\n\n${FIELDS}`,
  })
  assert.deepEqual(problems(dir), [])
})

test('a missing field is named with its file', () => {
  const dir = folder({ '2026-10-29-x.md': `# X\n\n${FIELDS.replace(/- \*\*Drives.*\n/, '')}` })
  assert.deepEqual(problems(dir), ['2026-10-29-x.md: missing **Drives:**'])
})

test('new entries must be dated, not numbered by hand', () => {
  // Hand-picked numbers are what collided (three PRs all took E28); only E01-E29 keep theirs.
  const dir = folder({ 'E30-new.md': `# E30. New\n\n${FIELDS}`, 'notes.md': `# Notes\n\n${FIELDS}` })
  assert.deepEqual(problems(dir).sort(), [
    'E30-new.md: new entries are named YYYY-MM-DD-<slug>.md (E01-E29 are the only numbered ones)',
    'notes.md: new entries are named YYYY-MM-DD-<slug>.md (E01-E29 are the only numbered ones)',
  ])
})

test('an entry needs a heading on its first line', () => {
  const dir = folder({ '2026-10-29-x.md': `${FIELDS}` })
  assert.deepEqual(problems(dir), ['2026-10-29-x.md: first line must be a "# " heading'])
})

test('a numbered file must carry its own number in the heading', () => {
  const dir = folder({ 'E05-x.md': `# E6. X\n\n${FIELDS}` })
  assert.deepEqual(problems(dir), ['E05-x.md: heading must start with "E5. "'])
})

test('two dated entries added the same day by two branches never collide', () => {
  const dir = folder({
    '2026-10-29-hebrew-normaliser.md': `# Hebrew normaliser\n\n${FIELDS}`,
    '2026-10-29-asset-packs.md': `# Asset packs\n\n${FIELDS}`,
  })
  assert.deepEqual(problems(dir), [])
})

test('the combined page lists numbered entries in number order, then dated ones oldest first', () => {
  const dir = folder({
    '2026-11-02-b.md': `# B\n\n${FIELDS}`,
    'E10-ten.md': `# E10. Ten\n\n${FIELDS}`,
    '2026-10-30-a.md': `# A\n\n${FIELDS}`,
    'E02-two.md': `# E2. Two\n\n${FIELDS}`,
  })
  const headings = combined(dir).split('\n').filter(l => l.startsWith('## '))
  assert.deepEqual(headings, ['## E2. Two', '## E10. Ten', '## A', '## B'])
})
