// Site link validation tests: seeded-fault proof for GitHub refs (#XXX)
// Runs via: node --test scripts/check-site.test.mjs
// These tests copy the site/ dir (with seeded faults) and verify check-site.mjs catches them.
import { test, describe } from 'node:test'
import assert from 'node:assert/strict'
import { cpSync, rmSync, readFileSync, writeFileSync } from 'fs'
import { execSync } from 'child_process'
import path from 'path'
import { fileURLToPath } from 'url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')

// Test each case by seeding a copy of site/ with the fault, then checking if check-site.mjs catches it.
const testCase = (name, shouldFail, fault) => {
  test(name, () => {
    const tmpSite = path.join(ROOT, `.tmp-site-test-${Date.now()}-${Math.random().toString(36).slice(2)}`)
    try {
      cpSync(path.join(ROOT, 'site'), tmpSite, { recursive: true })
      fault(tmpSite)
      let output = ''
      let exitCode = 0
      try {
        output = execSync(`SITE_DIR="${tmpSite}" node scripts/check-site.mjs`, {
          cwd: ROOT,
          encoding: 'utf-8',
          stdio: 'pipe'
        })
      } catch (e) {
        // execSync throws on non-zero exit; with encoding, stdout/stderr are strings in the error
        exitCode = e.status || e.code || 1
        output = (e.stdout || '') + (e.stderr || '')
      }
      if (shouldFail) {
        assert(exitCode !== 0, `Expected check to fail but passed with exit code ${exitCode}:\n${output}`)
        assert(output.includes('bad GitHub ref'), `Expected "bad GitHub ref" in error output, got:\n${output}`)
      } else {
        assert(exitCode === 0, `Expected check to pass but got exit code ${exitCode}:\n${output}`)
      }
    } finally {
      rmSync(tmpSite, { recursive: true, force: true })
    }
  })
}

describe('GitHub ref validation', () => {
  testCase('baseline: no bad refs passes', false, (tmpSite) => {
    // No seeded fault — the baseline should pass.
  })

  testCase('catches tag in Hebrew page link', true, (tmpSite) => {
    const langFile = path.join(tmpSite, 'he', 'index.html')
    let html = readFileSync(langFile, 'utf-8')
    html = html.replace(
      'github.com/G-Eskayo/clarity-captions/blob/main',
      'github.com/G-Eskayo/clarity-captions/blob/v1.0.0'
    )
    writeFileSync(langFile, html)
  })

  testCase('catches tag in devices.js link', true, (tmpSite) => {
    const jsFile = path.join(tmpSite, 'devices.js')
    let src = readFileSync(jsFile, 'utf-8')
    src = src.replace(
      'github.com/G-Eskayo/clarity-captions/tree/main',
      'github.com/G-Eskayo/clarity-captions/tree/v1.0.0'
    )
    writeFileSync(jsFile, src)
  })

  testCase('catches tag in HTML href', true, (tmpSite) => {
    const indexFile = path.join(tmpSite, 'index.html')
    let html = readFileSync(indexFile, 'utf-8')
    html = html.replace(
      'href="https://github.com/G-Eskayo/clarity-captions/blob/main',
      'href="https://github.com/G-Eskayo/clarity-captions/blob/tag-v1'
    )
    writeFileSync(indexFile, html)
  })

  testCase('catches short SHA', true, (tmpSite) => {
    const indexFile = path.join(tmpSite, 'index.html')
    let html = readFileSync(indexFile, 'utf-8')
    html = html.replace(
      'github.com/G-Eskayo/clarity-captions/blob/main',
      'github.com/G-Eskayo/clarity-captions/blob/abc123def456'
    )
    writeFileSync(indexFile, html)
  })

  testCase('catches main-old branch name', true, (tmpSite) => {
    const indexFile = path.join(tmpSite, 'index.html')
    let html = readFileSync(indexFile, 'utf-8')
    html = html.replace(
      'github.com/G-Eskayo/clarity-captions/blob/main',
      'github.com/G-Eskayo/clarity-captions/blob/main-old'
    )
    writeFileSync(indexFile, html)
  })

  testCase('catches bad ref in HTML comment', true, (tmpSite) => {
    const indexFile = path.join(tmpSite, 'index.html')
    let html = readFileSync(indexFile, 'utf-8')
    html += `\n<!-- See https://github.com/G-Eskayo/clarity-captions/blob/feature-branch/README.md -->`
    writeFileSync(indexFile, html)
  })

  testCase('catches bad ref in data attribute', true, (tmpSite) => {
    const indexFile = path.join(tmpSite, 'index.html')
    let html = readFileSync(indexFile, 'utf-8')
    html += `\n<div data-source="https://github.com/G-Eskayo/clarity-captions/blob/dev-branch/docs/README.md"></div>`
    writeFileSync(indexFile, html)
  })

  testCase('catches bad ref on raw.githubusercontent.com', true, (tmpSite) => {
    const indexFile = path.join(tmpSite, 'index.html')
    let html = readFileSync(indexFile, 'utf-8')
    html += `\n<a href="https://raw.githubusercontent.com/G-Eskayo/clarity-captions/develop/README.md">Link</a>`
    writeFileSync(indexFile, html)
  })

  testCase('allows main ref', false, (tmpSite) => {
    // Verify main is allowed (this should NOT trigger an error)
  })

  testCase('allows 40-char SHA', false, (tmpSite) => {
    const indexFile = path.join(tmpSite, 'index.html')
    let html = readFileSync(indexFile, 'utf-8')
    html += `\n<a href="https://github.com/G-Eskayo/clarity-captions/blob/abc123def456abc123def456abc123def456abcd/README.md">Link</a>`
    writeFileSync(indexFile, html)
  })
})
