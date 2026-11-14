// Seeded-fault tests for check-site.mjs: prove the branch-link check catches stale feature-branch refs.
// Tests items 11–16 from docs/design/pipeline-g-eskayo-clarity-captions-168.md
import test from 'node:test'
import assert from 'node:assert'
import { mkdtempSync, cpSync, readFileSync, writeFileSync, rmSync } from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import { spawnSync } from 'child_process'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')

test('11. feature-branch link only in he/index.html is caught', () => {
  const tmp = mkdtempSync(path.join('/tmp', 'check-site-test-'))
  try {
    cpSync(path.join(ROOT, 'site'), path.join(tmp, 'site'), { recursive: true })
    const heIndex = path.join(tmp, 'site', 'he', 'index.html')
    const content = readFileSync(heIndex, 'utf-8')

    // Seed a feature-branch link into the Hebrew page
    const seeded = content + '\n<!-- Hidden link: https://github.com/G-Eskayo/clarity-captions/blob/feature/159-translation-eval/docs/research.md -->'
    writeFileSync(heIndex, seeded, 'utf-8')

    const result = spawnSync('node', ['scripts/check-site.mjs'], {
      cwd: ROOT,
      env: { ...process.env, SITE_DIR: path.join(tmp, 'site') }
    })

    assert(result.status !== 0, 'check-site.mjs should fail with seeded branch link')
    assert(result.stderr.toString().includes('he/index.html'), 'error should name the file')
    assert(result.stderr.toString().includes('feature/159'), 'error should name the branch')
  } finally {
    rmSync(tmp, { recursive: true })
  }
})

test('12. feature-branch link only in devices.js is caught', () => {
  const tmp = mkdtempSync(path.join('/tmp', 'check-site-test-'))
  try {
    cpSync(path.join(ROOT, 'site'), path.join(tmp, 'site'), { recursive: true })
    const devicesJs = path.join(tmp, 'site', 'devices.js')
    const content = readFileSync(devicesJs, 'utf-8')

    // Seed a feature-branch link
    const seeded = content + '\n// export const BAD_LINK = "https://raw.githubusercontent.com/G-Eskayo/clarity-captions/feature/issues/123/assets/img.jpg"'
    writeFileSync(devicesJs, seeded, 'utf-8')

    const result = spawnSync('node', ['scripts/check-site.mjs'], {
      cwd: ROOT,
      env: { ...process.env, SITE_DIR: path.join(tmp, 'site') }
    })

    assert(result.status !== 0, 'check-site.mjs should fail with seeded branch link')
    assert(result.stderr.toString().includes('devices.js'), 'error should name devices.js')
    assert(result.stderr.toString().includes('feature/issues/123'), 'error should name the branch')
  } finally {
    rmSync(tmp, { recursive: true })
  }
})

test('13. branch link in HTML comment and data- attribute are both caught', () => {
  const tmp = mkdtempSync(path.join('/tmp', 'check-site-test-'))
  try {
    cpSync(path.join(ROOT, 'site'), path.join(tmp, 'site'), { recursive: true })
    const indexHtml = path.join(tmp, 'site', 'index.html')
    const content = readFileSync(indexHtml, 'utf-8')

    // Seed links in comment and data attribute
    const seeded = content + '\n<!-- https://github.com/G-Eskayo/clarity-captions/blob/wip-draft/README.md --><div data-link="https://github.com/G-Eskayo/clarity-captions/tree/v1.0-backport/docs"></div>'
    writeFileSync(indexHtml, seeded, 'utf-8')

    const result = spawnSync('node', ['scripts/check-site.mjs'], {
      cwd: ROOT,
      env: { ...process.env, SITE_DIR: path.join(tmp, 'site') }
    })

    assert(result.status !== 0, 'check-site.mjs should fail')
    const output = result.stderr.toString()
    assert(output.includes('wip-draft') || output.includes('v1.0-backport'), 'should catch both branch links')
  } finally {
    rmSync(tmp, { recursive: true })
  }
})

test('14. raw.githubusercontent branch-pinned image is caught', () => {
  const tmp = mkdtempSync(path.join('/tmp', 'check-site-test-'))
  try {
    cpSync(path.join(ROOT, 'site'), path.join(tmp, 'site'), { recursive: true })
    const indexHtml = path.join(tmp, 'site', 'index.html')
    const content = readFileSync(indexHtml, 'utf-8')

    // Seed a raw.githubusercontent branch link
    const seeded = content + '\n<img src="https://raw.githubusercontent.com/G-Eskayo/clarity-captions/feature-branch/assets/demo.png" />'
    writeFileSync(indexHtml, seeded, 'utf-8')

    const result = spawnSync('node', ['scripts/check-site.mjs'], {
      cwd: ROOT,
      env: { ...process.env, SITE_DIR: path.join(tmp, 'site') }
    })

    assert(result.status !== 0, 'check-site.mjs should fail')
    assert(result.stderr.toString().includes('feature-branch'), 'error should name the branch')
  } finally {
    rmSync(tmp, { recursive: true })
  }
})

test('15. real unmodified site/ passes with zero branch-link failures', () => {
  const tmp = mkdtempSync(path.join('/tmp', 'check-site-test-'))
  try {
    cpSync(path.join(ROOT, 'site'), path.join(tmp, 'site'), { recursive: true })

    const result = spawnSync('node', ['scripts/check-site.mjs'], {
      cwd: ROOT,
      env: { ...process.env, SITE_DIR: path.join(tmp, 'site') }
    })

    // The check should pass (status 0) because the real site has no branch links
    assert(result.status === 0, `check-site.mjs should pass (got status ${result.status}: ${result.stderr.toString()})`)
  } finally {
    rmSync(tmp, { recursive: true })
  }
})

test('16. added main and 40-char-SHA links pass (no false failure)', () => {
  const tmp = mkdtempSync(path.join('/tmp', 'check-site-test-'))
  try {
    cpSync(path.join(ROOT, 'site'), path.join(tmp, 'site'), { recursive: true })
    const indexHtml = path.join(tmp, 'site', 'index.html')
    const content = readFileSync(indexHtml, 'utf-8')

    // Seed allowed links (main and 40-char SHA)
    const seeded = content + '\n<!-- OK: https://github.com/G-Eskayo/clarity-captions/blob/main/README.md --><img src="https://raw.githubusercontent.com/G-Eskayo/clarity-captions/abcdef0123456789abcdef0123456789abcdef01/assets/demo.png" />'
    writeFileSync(indexHtml, seeded, 'utf-8')

    const result = spawnSync('node', ['scripts/check-site.mjs'], {
      cwd: ROOT,
      env: { ...process.env, SITE_DIR: path.join(tmp, 'site') }
    })

    assert(result.status === 0, `check-site.mjs should pass with allowed links (got status ${result.status}: ${result.stderr.toString()})`)
  } finally {
    rmSync(tmp, { recursive: true })
  }
})
