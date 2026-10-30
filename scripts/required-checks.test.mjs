// One list of required checks, run the same way by GitHub CI and by MARVIN's merge gate (marvin#826).
//   node --test scripts/required-checks.test.mjs
// .github/required-checks.json names each check; CI runs one job per check with that exact name, each through
// .github/run-check.sh (the same runner the gate uses), and branch protection on main requires those names. These
// tests fail when the workflow and the list drift apart, and try the runner against a temp repo.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'fs'
import { execFileSync, spawnSync } from 'child_process'
import { tmpdir } from 'os'
import path from 'path'
import { fileURLToPath } from 'url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const list = JSON.parse(readFileSync(path.join(ROOT, '.github/required-checks.json'), 'utf8')).checks

// The jobs in ci.yml: `  <id>:` at two spaces under `jobs:`, each with its `name:` and every `run:` text.
function ciJobs () {
  const lines = readFileSync(path.join(ROOT, '.github/workflows/ci.yml'), 'utf8').split('\n')
  const jobs = {}
  let inJobs = false
  let cur = null
  for (const line of lines) {
    if (/^jobs:\s*$/.test(line)) { inJobs = true; continue }
    if (!inJobs) continue
    const job = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/)
    if (job) { cur = jobs[job[1]] = { name: null, text: '' }; continue }
    if (!cur) continue
    const name = line.match(/^ {4}name:\s*(.+?)\s*$/)
    if (name) cur.name = name[1].replace(/^["']|["']$/g, '')
    cur.text += line + '\n'
  }
  return Object.values(jobs)
}

test('the list is well formed: unique ids and names, a command for every check the gate runs', () => {
  assert.ok(list.length > 0)
  assert.equal(new Set(list.map((c) => c.id)).size, list.length)
  assert.equal(new Set(list.map((c) => c.name)).size, list.length)
  for (const c of list) {
    assert.match(c.id, /^[a-z0-9][a-z0-9-]*$/)
    if ((c.where || 'both') === 'both') assert.ok(Array.isArray(c.command) && c.command.every((a) => typeof a === 'string'), c.id)
  }
})

test('every required check is a CI job with the same name, run through the shared runner', () => {
  const jobs = ciJobs()
  for (const c of list) {
    const job = jobs.find((j) => j.name === c.name)
    assert.ok(job, `no CI job is named "${c.name}": branch protection would wait for it forever`)
    if ((c.where || 'both') === 'both') assert.ok(job.text.includes(`.github/run-check.sh ${c.id}`), `CI job "${c.name}" does not run its listed command`)
  }
})

test('the runner skips a check whose paths the change does not touch, and runs it otherwise', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'rc-'))
  try {
    mkdirSync(path.join(dir, '.github'))
    copyFileSync(path.join(ROOT, '.github/run-check.sh'), path.join(dir, '.github/run-check.sh'))
    writeFileSync(path.join(dir, '.github/required-checks.json'), JSON.stringify({ checks: [
      { id: 'site', name: 'Site', paths: ['site/*'], command: ['echo', 'ran site'] }
    ] }))
    mkdirSync(path.join(dir, 'site'))
    writeFileSync(path.join(dir, 'site/a.html'), '1')
    writeFileSync(path.join(dir, 'README.md'), '1')
    const git = (...a) => execFileSync('git', a, { cwd: dir, encoding: 'utf8' })
    git('init', '-q', '-b', 'main')
    git('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'add', '-A')
    git('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-qm', 'init')
    const base = git('rev-parse', 'HEAD').trim()
    const run = () => spawnSync('bash', ['.github/run-check.sh', 'site'], { cwd: dir, encoding: 'utf8', env: { ...process.env, MARVIN_BASE: base } })
    writeFileSync(path.join(dir, 'README.md'), '2')
    git('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-qam', 'docs')
    let r = run()
    assert.equal(r.status, 0)
    assert.match(r.stdout, /not affected/)
    writeFileSync(path.join(dir, 'site/a.html'), '2')
    git('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-qam', 'site')
    r = run()
    assert.match(r.stdout, /ran site/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('a failing check fails the runner with its own exit code', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'rc-'))
  try {
    mkdirSync(path.join(dir, '.github'))
    copyFileSync(path.join(ROOT, '.github/run-check.sh'), path.join(dir, '.github/run-check.sh'))
    writeFileSync(path.join(dir, '.github/required-checks.json'), JSON.stringify({ checks: [
      { id: 'bad', name: 'Bad', command: ['bash', '-c', 'exit 7'] }
    ] }))
    const env = { ...process.env }
    delete env.MARVIN_BASE
    assert.equal(spawnSync('bash', ['.github/run-check.sh', 'bad'], { cwd: dir, env }).status, 7)
    assert.equal(spawnSync('bash', ['.github/run-check.sh', 'nope'], { cwd: dir, env }).status, 2)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
