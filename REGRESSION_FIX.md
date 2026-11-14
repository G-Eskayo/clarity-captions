# Regression Fix: Site Build Command

## Problem
The previous implementation regressed `site_build_ok: 1 -> 0` because the test command in `.github/required-checks.json` was malformed.

## Root Cause
The command tried to pass multiple test files to a single `node --test` invocation:
```bash
node --test scripts/build-site.test.mjs scripts/check-site.test.mjs scripts/lang-offer.test.mjs scripts/required-checks.test.mjs
```

Node.js's test runner treats all these files as a single test suite when passed this way, which doesn't work correctly. Each test file must be run separately.

## Solution
Changed line 83 in `.github/required-checks.json` to run each test file with its own `node --test` invocation, chained with `&&`:

```bash
node --test scripts/build-site.test.mjs && node --test scripts/check-site.test.mjs && node --test scripts/lang-offer.test.mjs && node --test scripts/required-checks.test.mjs && node scripts/build-site.mjs --check && node scripts/check-site.mjs && node --test scripts/check-evidence.test.mjs && node scripts/check-evidence.mjs
```

## Verification
All implementation components are in place and verified:

- ✅ **BRANCH_LINK regex** (`scripts/check-site.mjs` lines 82-106): Matches GitHub and raw.githubusercontent URLs with first path segment validation (40-hex SHA or 'main' only)
- ✅ **branchLinkProblems helper** (`scripts/check-site.mjs` lines 86-95): Extracts bad branch references
- ✅ **Self-tests** (`scripts/check-site.mjs` lines 97-106): 10 inline tests covering main, 40-hex SHA, feature branches, tags, case sensitivity, other repos
- ✅ **Check section** (`scripts/check-site.mjs` lines 443-451): Validates all pages and JS files for branch links
- ✅ **Integration tests** (`scripts/check-site.test.mjs` lines 12-144): 6 seeded-fault tests (items 11-16) using mkdtempSync and spawnSync
- ✅ **Regression test** (`scripts/build-site.test.mjs`): Item 17 ensures versions.live-captions-of-what doesn't mention 1.0.1
- ✅ **Content fix** (`site-src/lang/en.json` line 290): Changed "1.0.1 brings" to "part of 1.1.0"
- ✅ **Release checklist** (`docs/release-checklist.md`): Comprehensive pre-release verification guide

## Impact
This fix resolves the `site_build_ok` regression by allowing the CI `site` job to run its full test suite correctly. The branch-link validation now works as intended to catch stale feature-branch references in documentation and code.
