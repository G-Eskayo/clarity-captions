// Check that FluidAudio version is pinned consistently across all packages.
//   node scripts/check-fluidaudio-pin.mjs                         check all Packages/*/Package.swift
//   node scripts/check-fluidaudio-pin.mjs --app-resolved <path>  also check transitive version in an app build's resolved
// All packages must agree on FluidAudio version; CaptionCore pins it exactly, others must match (#273).
import { readFileSync, globSync, existsSync } from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')

export function parsePackageSwift(content) {
  // First check if FluidAudio is mentioned at all
  const hasFluidAudio = content.includes('FluidAudio')
  if (!hasFluidAudio) return null

  // Match: .package(...url: "...FluidAudio...", <requirement>: "<version>")
  // Handles: exact, from, upToNextMajor, upToNextMinor, range literals "X"..."Y" or "X"..<"Y"
  let match

  // Try exact: "version"
  match = content.match(/\.package\([^)]*url:\s*"[^"]*FluidAudio[^"]*"[^)]*,\s*exact:\s*"([^"]+)"/)
  if (match) return { requirement: 'exact', version: match[1] }

  // Try from: "version"
  match = content.match(/\.package\([^)]*url:\s*"[^"]*FluidAudio[^"]*"[^)]*,\s*from:\s*"([^"]+)"/)
  if (match) return { requirement: 'from', version: match[1] }

  // Try .upToNextMajor(from: "version")
  match = content.match(/\.package\([^)]*url:\s*"[^"]*FluidAudio[^"]*"[^)]*,\s*\.upToNextMajor\(from:\s*"([^"]+)"\)/)
  if (match) return { requirement: 'upToNextMajor', version: match[1] }

  // Try .upToNextMinor(from: "version")
  match = content.match(/\.package\([^)]*url:\s*"[^"]*FluidAudio[^"]*"[^)]*,\s*\.upToNextMinor\(from:\s*"([^"]+)"\)/)
  if (match) return { requirement: 'upToNextMinor', version: match[1] }

  // Try range: "from"..<"to" or "from"..."to"
  match = content.match(/\.package\([^)]*url:\s*"[^"]*FluidAudio[^"]*"[^)]*,\s*"([^"]+)"(\.\.< ?|\.\.\.)"([^"]+)"/)
  if (match) return { requirement: 'range', version: match[1], versionTo: match[3] }

  // FluidAudio is mentioned but doesn't match any known requirement format
  return { requirement: 'unknown', version: null }
}

export function parsePackageResolved(content) {
  try {
    const data = JSON.parse(content)
    const pin = data.pins?.find(p => p.identity?.toLowerCase().includes('fluidaudio'))
    return pin?.state?.version || null
  } catch {
    return null
  }
}

export function checkFluidAudioPin(packages, appResolveds, resolvedFiles = []) {
  const problems = []
  const notes = []
  const versions = new Map()
  const requirements = new Map()
  const pkgFiles = new Map()

  // First pass: collect all versions from Packages/*/Package.swift
  for (const pkg of packages) {
    const result = parsePackageSwift(pkg.content)
    if (!result) continue

    // Extract just the package name (last component of path before Package.swift)
    // Path like /path/to/Packages/CaptionCore/Package.swift -> 'CaptionCore'
    const pkgName = pkg.file.split('/').slice(-2, -1)[0]

    // Fail closed if FluidAudio is mentioned but unparseable
    if (result.requirement === 'unknown') {
      problems.push(`${pkgName}: FluidAudio mentioned but requirement format not recognized`)
      continue
    }

    if (!result.version) continue

    const key = result.version

    if (!versions.has(key)) {
      versions.set(key, [])
    }
    versions.get(key).push(pkgName)

    requirements.set(pkgName, result.requirement)
    pkgFiles.set(pkgName, pkg.file)
  }

  // Check for version mismatches
  if (versions.size > 1) {
    const versionList = Array.from(versions.entries())
    problems.push(`FluidAudio version mismatch: ${versionList.map(([v, pkgs]) => `${v} (${pkgs.join(', ')})`).join('; ')}`)
  }

  // Check that CaptionCore pins exactly
  const captionCoreReq = requirements.get('CaptionCore')
  if (captionCoreReq && captionCoreReq !== 'exact') {
    problems.push(`CaptionCore must pin FluidAudio exactly (exact: "..."), not ${captionCoreReq}`)
  }

  // Check that ALL packages pin exactly, not just prevent "from"
  for (const [pkg, req] of requirements) {
    if (req !== 'exact') {
      problems.push(`${pkg} must pin FluidAudio exactly (exact: "..."), not ${req}`)
    }
  }

  // Check sibling Package.resolved files
  const resolvedVersions = new Map()
  for (const resolved of resolvedFiles) {
    const resolvedVersion = parsePackageResolved(resolved.content)
    if (resolvedVersion) {
      if (!resolvedVersions.has(resolvedVersion)) {
        resolvedVersions.set(resolvedVersion, [])
      }
      resolvedVersions.get(resolvedVersion).push(resolved.file)
    }
  }

  // Compare Package.swift pins with their sibling Package.resolved files
  for (const [pkgName, pkgFile] of pkgFiles) {
    const dir = pkgFile.split('/').slice(0, -1).join('/')
    const resolvedFile = `${dir}/Package.resolved`
    const matching = resolvedFiles.find(r => r.file === resolvedFile)
    if (matching) {
      const resolvedVersion = parsePackageResolved(matching.content)
      const pinnedVersion = Array.from(versions.keys()).find(v =>
        versions.get(v).includes(pkgName)
      )
      if (resolvedVersion && pinnedVersion && resolvedVersion !== pinnedVersion) {
        notes.push(`${pkgName}: Package.swift pins ${pinnedVersion} but Package.resolved has ${resolvedVersion}`)
      }
    }
  }

  // Check transitive versions in app builds
  for (const appResolved of appResolveds) {
    const appVersion = appResolved.version
    if (!appVersion) {
      problems.push(`App resolved file ${appResolved.file} has no FluidAudio pin`)
      continue
    }
    for (const [pkgVersion] of versions) {
      if (appVersion !== pkgVersion) {
        problems.push(`Transitive drift: packages pin ${pkgVersion}, but ${appResolved.file} resolved ${appVersion}`)
      }
    }
  }

  return { problems, notes }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const appResolvedIdx = process.argv.indexOf('--app-resolved')
  const appResolvedPath = appResolvedIdx !== -1 ? process.argv[appResolvedIdx + 1] : null

  const packageFiles = globSync(path.join(ROOT, 'Packages/*/Package.swift'))
  const packages = packageFiles.map(f => ({
    file: f,
    content: readFileSync(f, 'utf8')
  }))

  const appResolveds = []
  if (appResolvedPath) {
    if (!existsSync(appResolvedPath)) {
      console.error(`error: ${appResolvedPath} does not exist`)
      process.exit(1)
    }
    try {
      const resolved = JSON.parse(readFileSync(appResolvedPath, 'utf8'))
      const pin = resolved.pins?.find(p => p.identity?.toLowerCase().includes('fluidaudio'))
      if (pin?.state?.version) {
        appResolveds.push({ file: appResolvedPath, version: pin.state.version })
      } else {
        // If the file exists but has no FluidAudio pin, that's a failure
        appResolveds.push({ file: appResolvedPath, version: null })
      }
    } catch (e) {
      console.error(`error reading ${appResolvedPath}: ${e.message}`)
      process.exit(1)
    }
  }

  // Load sibling Package.resolved files
  const resolvedFiles = globSync(path.join(ROOT, 'Packages/*/Package.resolved')).map(f => ({
    file: f,
    content: readFileSync(f, 'utf8')
  }))

  const result = checkFluidAudioPin(packages, appResolveds, resolvedFiles)

  for (const problem of result.problems) {
    console.error(`fluidaudio-pin: ${problem}`)
  }
  for (const note of result.notes) {
    console.log(`fluidaudio-pin (note): ${note}`)
  }

  if (result.problems.length > 0) {
    console.log('\nWhen fixing this, ensure CaptionCore pins FluidAudio with exact: "version" and all other packages match. This prevents transitive version drift (#273).')
    process.exit(1)
  }

  console.log(packages.length > 0 ? 'FluidAudio pin OK' : 'no packages found')
  process.exit(0)
}
