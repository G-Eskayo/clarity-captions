// Tests for the FluidAudio pin checker. Ensures all packages agree on FluidAudio version.
//   node --test scripts/check-fluidaudio-pin.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { checkFluidAudioPin, parsePackageSwift, parsePackageResolved } from './check-fluidaudio-pin.mjs'
import { writeFileSync, mkdtempSync, rmSync } from 'fs'
import { tmpdir } from 'os'
import path from 'path'

test('1. parsePackageSwift extracts the FluidAudio dependency requirement', () => {
  const swift = `
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
  `
  const result = parsePackageSwift(swift)
  assert.deepEqual(result, { requirement: 'exact', version: '0.17.5' })
})

test('2. parsePackageSwift handles "from" requirement', () => {
  const swift = `
    .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5"),
  `
  const result = parsePackageSwift(swift)
  assert.deepEqual(result, { requirement: 'from', version: '0.17.5' })
})

test('3. parsePackageSwift returns null if no FluidAudio dependency', () => {
  const swift = `
    .package(url: "https://github.com/Other/Lib.git", from: "1.0.0"),
  `
  const result = parsePackageSwift(swift)
  assert.strictEqual(result, null)
})

test('4. parsePackageResolved extracts FluidAudio version from Package.resolved', () => {
  const resolved = {
    version: 3,
    pins: [
      {
        identity: 'fluidaudio',
        kind: 'remoteSourceControl',
        location: 'https://github.com/FluidInference/FluidAudio.git',
        state: { revision: 'abc123', version: '0.17.5' }
      }
    ]
  }
  const result = parsePackageResolved(JSON.stringify(resolved))
  assert.strictEqual(result, '0.17.5')
})

test('5. parsePackageResolved returns null if no FluidAudio pin', () => {
  const resolved = {
    version: 3,
    pins: [
      {
        identity: 'other-lib',
        kind: 'remoteSourceControl',
        location: 'https://example.com/lib.git',
        state: { revision: 'abc123', version: '1.0.0' }
      }
    ]
  }
  const result = parsePackageResolved(JSON.stringify(resolved))
  assert.strictEqual(result, null)
})

test('6. checkFluidAudioPin detects version mismatch between packages', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'check-fa-'))
  try {
    const result = checkFluidAudioPin([
      { file: path.join(dir, 'Pkg1/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' },
      { file: path.join(dir, 'Pkg2/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0")' }
    ], [])
    assert.ok(result.problems.length > 0)
    assert.ok(result.problems.some(p => p.includes('version mismatch')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('7. checkFluidAudioPin detects "from" when CaptionCore has "exact"', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'check-fa-'))
  try {
    const result = checkFluidAudioPin([
      { file: path.join(dir, 'CaptionCore/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' },
      { file: path.join(dir, 'SystemReplay/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5")' }
    ], [])
    assert.ok(result.problems.length > 0)
    assert.ok(result.problems.some(p => p.includes('CaptionCore pins exactly')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('8. checkFluidAudioPin reports transitive drift in app-resolved', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'check-fa-'))
  try {
    const result = checkFluidAudioPin(
      [{ file: path.join(dir, 'CaptionCore/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' }],
      [{ file: 'App.resolved', version: '0.18.0' }]
    )
    assert.ok(result.problems.length > 0)
    assert.ok(result.problems.some(n => n.includes('Transitive drift')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('9. checkFluidAudioPin succeeds when all versions align', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'check-fa-'))
  try {
    const result = checkFluidAudioPin([
      { file: path.join(dir, 'CaptionCore/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' },
      { file: path.join(dir, 'SystemReplay/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' },
      { file: path.join(dir, 'EngineEval/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' }
    ], [])
    assert.strictEqual(result.problems.length, 0)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('10. checkFluidAudioPin fails when package mentions FluidAudio with unparseable requirement', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'check-fa-'))
  try {
    const result = checkFluidAudioPin([
      { file: path.join(dir, 'CaptionCore/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main")' }
    ], [])
    assert.ok(result.problems.length > 0)
    assert.ok(result.problems.some(p => p.includes('requirement format not recognized')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('11. checkFluidAudioPin requires all packages to use exact, not just non-from', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'check-fa-'))
  try {
    const result = checkFluidAudioPin([
      { file: path.join(dir, 'CaptionCore/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' },
      { file: path.join(dir, 'SystemReplay/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.17.5"))' }
    ], [])
    assert.ok(result.problems.length > 0)
    assert.ok(result.problems.some(p => p.includes('must pin FluidAudio exactly')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('12. checkFluidAudioPin compares Package.swift pins with sibling Package.resolved files', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'check-fa-'))
  try {
    const result = checkFluidAudioPin(
      [{ file: path.join(dir, 'CaptionCore/Package.swift'), content: '.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5")' }],
      [],
      [{ file: path.join(dir, 'CaptionCore/Package.resolved'), content: JSON.stringify({ pins: [{ identity: 'fluidaudio', state: { version: '0.18.0' } }] }) }]
    )
    assert.ok(result.notes.length > 0)
    assert.ok(result.notes.some(n => n.includes('Package.swift pins') && n.includes('Package.resolved')))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
