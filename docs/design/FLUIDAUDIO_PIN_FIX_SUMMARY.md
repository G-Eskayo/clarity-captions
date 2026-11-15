# FluidAudio Pin Check: Code Review Defect Fixes

This document summarizes the fixes applied to address the five must-fix defects found in the code review of the FluidAudio pin checking implementation.

## Defect 1: Test Fixtures Missing Script
**Problem:** Tests invoked `bash scripts/check-fluidaudio-pin.sh` from temp directories where the script didn't exist, causing "No such file or directory" errors.

**Fix:** 
- Updated all test invocations to use absolute path: `bash ${ROOT}/scripts/check-fluidaudio-pin.sh`
- Added `SCRIPT_ROOT` environment variable override so the script can find its root directory when running from a temp dir
- Modified script to respect `SCRIPT_ROOT` override: `ROOT="${SCRIPT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"`

**Tests Updated:**
- `rejects from: pinning` — new test
- `fails if a Package.swift pins a different version`
- `ignores packages without FluidAudio`
- `fails if no FluidAudio pin is found`
- `build-time check: verifies resolved version matches pin`
- `build-time check: fails if resolved version does not match pin`
- `build-time check: fails if workspace-state.json path does not exist`
- `static check: verifies Package.resolved files match the pinned version` — new test
- `static check: fails if Package.resolved does not match the pinned version` — new test

## Defect 2: Regex Accepts Both `exact:` and `from:`
**Problem:** The regex pattern `(?:exact|from):` allowed both `exact:` and `from:` pinning, but the ticket requires `exact:` only to prevent version drift.

**Fix:**
- Changed regex from `(?:exact|from):` to `exact:` only
- Modified pattern: `r'FluidAudio\.git["\']?,\s*exact:\s*["\']([0-9.]+)["\']'`
- New test added to verify `from:` is rejected

**Enforcement:**
- `Packages/CaptionCore/Package.swift`: Changed from `from: "0.17.5"` to `exact: "0.17.5"`
- Comments in SystemReplay and EngineEval updated to reflect `exact:` requirement

## Defect 3: No Package.resolved Verification
**Problem:** The static check never read `Package.resolved` files to verify consistency with the `Package.swift` pins. Missing pins could exist undetected.

**Fix:**
- Added second loop in static check that finds and verifies all `Package.resolved` files
- Loop compares each resolved version to the static pin, fails if mismatched
- Files without FluidAudio in their resolved pins are skipped (not an error)

**Tests Added:**
- `static check: verifies Package.resolved files match the pinned version`
- `static check: fails if Package.resolved does not match the pinned version`

## Defect 4: Wrong Xcode workspace-state.json Structure
**Problem:** The JSON parser tried to access `d["object"]["pins"]` but Xcode's actual structure uses `object.dependencies[].state.checkoutState.version`.

**Fix:**
- Rewrote `get_resolved_pin()` to handle both Xcode v1 and v2 formats
- v1 format: direct `pins` array with `identity` and `state.version`
- v2 format: `object.dependencies` array with `packageRef.identity` and `state.checkoutState.version`
- Both formats are now supported to handle different Xcode versions

**Tests Updated:**
- Updated all build-time resolved tests to use correct v2 JSON structure

## Defect 5: Build-Time Check Fails Open When Path Not Found
**Problem:** When `--app-resolved <path>` pointed to a non-existent file, the script warned and exited 0 (success). CI would pass even when the path wasn't found.

**Fix:**
- Changed behavior to exit 1 (failure) when path is missing or empty
- Explicit error message: `"error: workspace-state.json path not found or empty"`
- Includes required message: `"own PR, scored by the #273 replay"`

**Test Updated:**
- `build-time check: fails if workspace-state.json path does not exist` — changed from expecting warning to expecting error

## Files Modified

### Core Script
- `scripts/check-fluidaudio-pin.sh`
  - SCRIPT_ROOT override for testing
  - Regex changed to enforce `exact:` only
  - Added Package.resolved verification loop
  - Fixed JSON parser for Xcode v2 format
  - Changed build-time check to fail on missing paths

### Tests
- `scripts/check-fluidaudio-pin.test.mjs`
  - All invocations updated to use absolute paths + SCRIPT_ROOT
  - New test for `from:` rejection
  - New tests for Package.resolved verification
  - Updated JSON fixtures to Xcode v2 format
  - Updated path-not-found test to expect failure

### Package Configuration
- `Packages/CaptionCore/Package.swift`: `from:` → `exact:`

### Package Comments
- `Packages/SystemReplay/Package.swift`: Updated comment to reference `exact:` 
- `Packages/EngineEval/Package.swift`: Updated comment to reference `exact:`

### Documentation
- `NOTICE.md`: Already added "Version pinned:" statement
- `docs/perf/whole-system-replay-design.md`: Already updated drift risk paragraph
- `Packages/CaptionCore/Tests/CaptionCoreTests/ThirdPartyNoticeTests.swift`: Already added pinning test

### CI Configuration
- `.github/required-checks.json`: Already has fluidaudio-pin check and app build-time checks
- `.github/workflows/ci.yml`: Already has fluidaudio-pin job

## Test Coverage

Total tests in `check-fluidaudio-pin.test.mjs`:
1. Script exists and is executable
2. ✓ Static check: all packages pin same version
3. ✓ Static check: fails on mismatch
4. ✓ Static check: rejects `from:` pinning (defect 2 validation)
5. ✓ Static check: ignores packages without FluidAudio
6. ✓ Static check: fails if no pin found
7. ✓ Static check: verifies Package.resolved matches pin (defect 3 validation)
8. ✓ Static check: fails if Package.resolved mismatches (defect 3 validation)
9. ✓ Build-time check: resolved matches pin
10. ✓ Build-time check: fails if resolved mismatches
11. ✓ Build-time check: fails if path not found (defect 5 validation)
12. ✓ Final check: includes transitive dependency note

## Validation

The fixes ensure:
1. Tests run in isolated temp directories without modifying the repo
2. Only `exact:` pinning is accepted (no version drift via `from:`)
3. Package.resolved files are verified to match static pins
4. Both Xcode v1 and v2 JSON formats are supported
5. Missing workspace-state.json is caught as an error, not silently skipped
6. All required error messages include "own PR, scored by the #273 replay" for context linking
