// Tests for check-fluidaudio-pin.sh: static checks (all packages pin the same version) and
// optional build-time checks (resolved version matches the pin).
//   node --test scripts/check-fluidaudio-pin.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from 'fs'
import { execSync } from 'child_process'
import { tmpdir } from 'os'
import path from 'path'
import { fileURLToPath } from 'url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')

test('check-fluidaudio-pin.sh exists and is executable', () => {
  const script = path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')
  const content = readFileSync(script, 'utf8')
  assert.match(content, /^#!/)
  assert.match(content, /check-fluidaudio-pin\.sh/)
})

test('static check: all packages pin the same FluidAudio version', () => {
  const result = execSync('bash scripts/check-fluidaudio-pin.sh', { cwd: ROOT, encoding: 'utf8' })
  assert.match(result, /static check:.*0\.17\.5/)
  assert.match(result, /✓/)
})

test('static check: fails if a Package.swift pins a different version', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-test-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })
    mkdirSync(path.join(dir, 'Packages', 'B'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    writeFileSync(path.join(dir, 'Packages', 'B', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "B",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0"),
    ],
    targets: []
)
`)

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail with mismatched pins')
    assert.match(error.stdout || error.stderr, /pin mismatch/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: rejects from: pinning (must use exact:)', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-from-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })
    mkdirSync(path.join(dir, 'Packages', 'B'), { recursive: true })

    // Package A uses exact: (good)
    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    // Package B uses from: (bad - must use exact:)
    writeFileSync(path.join(dir, 'Packages', 'B', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "B",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5"),
    ],
    targets: []
)
`)

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when from: is used instead of exact:')
    assert.match(error.stdout || error.stderr, /must use exact: pinning/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: rejects upToNextMinor: pinning (must use exact:)', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-uptonext-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })
    mkdirSync(path.join(dir, 'Packages', 'B'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    writeFileSync(path.join(dir, 'Packages', 'B', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "B",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", upToNextMinor: "0.17.5"),
    ],
    targets: []
)
`)

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when upToNextMinor: is used instead of exact:')
    assert.match(error.stdout || error.stderr, /must use exact: pinning/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: rejects branch: pinning (must use exact:)', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-branch-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })
    mkdirSync(path.join(dir, 'Packages', 'B'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    writeFileSync(path.join(dir, 'Packages', 'B', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "B",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
    ],
    targets: []
)
`)

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when branch: is used instead of exact:')
    assert.match(error.stdout || error.stderr, /must use exact: pinning/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: ignores packages without FluidAudio', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-test-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })
    mkdirSync(path.join(dir, 'Packages', 'B'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    writeFileSync(path.join(dir, 'Packages', 'B', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "B",
    dependencies: [],
    targets: []
)
`)

    const result = execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    assert.match(result, /0\.17\.5/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: fails if no FluidAudio pin is found', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-test-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [],
    targets: []
)
`)

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when no pin is found')
    assert.match(error.stdout || error.stderr, /no FluidAudio pin found/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('build-time check: verifies resolved version matches pin', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-resolved-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    const resolvedContent = {
      object: {
        dependencies: [
          {
            packageRef: { identity: "fluidaudio" },
            state: { checkoutState: { version: "0.17.5" } }
          }
        ]
      }
    }
    writeFileSync(path.join(dir, 'resolved.json'), JSON.stringify(resolvedContent))

    const result = execSync(
      `bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')} --app-resolved ${path.join(dir, 'resolved.json')} --app-name test`,
      { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' }
    )
    assert.match(result, /build check.*test.*resolved FluidAudio 0\.17\.5/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('build-time check: fails if resolved version does not match pin', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-mismatch-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    const resolvedContent = {
      object: {
        dependencies: [
          {
            packageRef: { identity: "fluidaudio" },
            state: { checkoutState: { version: "0.18.3" } }
          }
        ]
      }
    }
    writeFileSync(path.join(dir, 'resolved.json'), JSON.stringify(resolvedContent))

    let error
    try {
      execSync(
        `bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')} --app-resolved ${path.join(dir, 'resolved.json')} --app-name myapp`,
        { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' }
      )
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail with resolved mismatch')
    assert.match(error.stdout || error.stderr, /app-resolved mismatch/)
    assert.match(error.stdout || error.stderr, /myapp/)
    assert.match(error.stdout || error.stderr, /0\.17\.5.*0\.18\.3/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('build-time check: fails if workspace-state.json path does not exist', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-notfound-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    let error
    try {
      execSync(
        `bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')} --app-resolved /nonexistent/path.json --app-name test`,
        { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' }
      )
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when path does not exist')
    assert.match(error.stdout || error.stderr, /error:.*path not found/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: verifies Package.resolved files match the pinned version', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-resolved-static-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    const resolvedContent = {
      object: {
        dependencies: [
          {
            packageRef: { identity: "fluidaudio" },
            state: { checkoutState: { version: "0.17.5" } }
          }
        ]
      }
    }
    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.resolved'), JSON.stringify(resolvedContent))

    const result = execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    assert.match(result, /static check:.*0\.17\.5/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: fails if Package.resolved does not match the pinned version', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-resolved-mismatch-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    const resolvedContent = {
      object: {
        dependencies: [
          {
            packageRef: { identity: "fluidaudio" },
            state: { checkoutState: { version: "0.18.0" } }
          }
        ]
      }
    }
    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.resolved'), JSON.stringify(resolvedContent))

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when Package.resolved does not match the pin')
    assert.match(error.stdout || error.stderr, /resolved version mismatch/)
    assert.match(error.stdout || error.stderr, /0\.18\.0/)
    assert.match(error.stdout || error.stderr, /0\.17\.5/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('final check: includes note about transitive dependencies', () => {
  const result = execSync('bash scripts/check-fluidaudio-pin.sh', { cwd: ROOT, encoding: 'utf8' })
  assert.match(result, /transitive dependencies/)
})

test('static check: fails on malformed JSON in Package.resolved', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-malformed-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    // Malformed JSON in Package.resolved
    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.resolved'), `{
      "object": { "dependencies": [{ invalid json`)

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when Package.resolved has malformed JSON')
    assert.match(error.stdout || error.stderr, /parse error/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: fails when Package.resolved missing state.version in v1 format', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-missing-v1-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    // v1 format with missing state.version
    const resolvedContent = {
      pins: [
        {
          identity: "fluidaudio",
          state: {}  // missing version
        }
      ]
    }
    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.resolved'), JSON.stringify(resolvedContent))

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when state.version is missing')
    assert.match(error.stdout || error.stderr, /parse error/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})

test('static check: fails when Package.resolved missing state.checkoutState.version in v2 format', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'fluidaudio-missing-v2-'))
  try {
    mkdirSync(path.join(dir, 'Packages', 'A'), { recursive: true })

    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.swift'), `
import PackageDescription
let package = Package(
    name: "A",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: []
)
`)

    // v2 format with missing state.checkoutState.version
    const resolvedContent = {
      object: {
        dependencies: [
          {
            packageRef: { identity: "fluidaudio" },
            state: { checkoutState: {} }  // missing version
          }
        ]
      }
    }
    writeFileSync(path.join(dir, 'Packages', 'A', 'Package.resolved'), JSON.stringify(resolvedContent))

    let error
    try {
      execSync(`bash ${path.join(ROOT, 'scripts/check-fluidaudio-pin.sh')}`, { cwd: dir, env: { ...process.env, SCRIPT_ROOT: dir }, encoding: 'utf8' })
    } catch (e) {
      error = e
    }

    assert.ok(error, 'should fail when state.checkoutState.version is missing')
    assert.match(error.stdout || error.stderr, /parse error/)
    assert.match(error.stdout || error.stderr, /own PR, scored by the #273 replay/)
  } finally {
    rmSync(dir, { recursive: true })
  }
})
