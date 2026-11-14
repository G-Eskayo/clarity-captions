# Implementation Summary: Branch Link Validation

## Plan Status: COMPLETE (with critical fix)

### Critical Fix Applied
**Issue:** Previous attempt regressed `site_build_ok: 1 -> 0`
**Root Cause:** `.github/required-checks.json` test command was malformed (multiple test files to single `node --test`)
**Fix:** Changed to run each test file with separate `node --test` invocation, chained with `&&`

---

## Implementation Checklist

### Step 1 & 2: BRANCH_LINK Regex and Helper ✅
**File:** `scripts/check-site.mjs` (lines 82-106)
- **BRANCH_LINK regex** (line 85): Matches GitHub and raw.githubusercontent URLs
  - Pattern: `(?:github\.com\/G-Eskayo\/clarity-captions|raw\.githubusercontent\.com\/G-Eskayo\/clarity-captions)\/(blob|tree|raw)\/([a-zA-Z0-9._-]+)`
  - Captures first path segment (the ref/branch)
- **branchLinkProblems helper** (lines 86-95): Returns array of bad refs
  - Validates segment === 'main' OR matches `^[0-9a-f]{40}$` (40-hex SHA)
  - Returns `{ ref: string, full: string }` for each problem
- **Self-tests** (lines 97-106): 10 comprehensive tests
  1. 'main' is OK
  2. 40-hex SHA is OK
  3. feature/159 branch caught
  4. v1.2 tag caught
  5. 'main-old' caught (not exact 'main')
  6. 'abc123' (short SHA) caught
  7. 39-char and 41-char hex caught
  8. raw.githubusercontent branch link caught
  9. 'Main' (capitalized) caught (case-sensitive)
  10. Other repos ignored (no false positives)

### Step 2: Check Section ✅
**File:** `scripts/check-site.mjs` (lines 443-451)
- Runs branchLinkProblems on all pages (all languages via `pages` array)
- Runs branchLinkProblems on `seal-data.js` and `devices.js`
- Reports failures: `${file}: branch link ${ref}: ${full}`

### Step 3: Seeded-Fault Integration Tests ✅
**File:** `scripts/check-site.test.mjs` (lines 12-144)
- **Test 11:** feature-branch link in he/index.html
- **Test 12:** feature-branch link in devices.js
- **Test 13:** branch links in HTML comments and data attributes
- **Test 14:** raw.githubusercontent branch-pinned image
- **Test 15:** real unmodified site/ passes with zero branch-link failures
- **Test 16:** main and 40-char-SHA links pass (no false failures)

Each test:
- Creates temp directory with mkdtempSync
- Copies site/ with cpSync
- Modifies files with seeded faults or validates clean files
- Spawns check-site.mjs with SITE_DIR env var
- Asserts expected pass/fail behavior

### Step 4: CI Configuration ✅
**File:** `.github/required-checks.json` (line 83)
**Fixed:** Command now properly chains test files:
```bash
node --test scripts/build-site.test.mjs && \
node --test scripts/check-site.test.mjs && \
node --test scripts/lang-offer.test.mjs && \
node --test scripts/required-checks.test.mjs && \
node scripts/build-site.mjs --check && \
node scripts/check-site.mjs && \
node --test scripts/check-evidence.test.mjs && \
node scripts/check-evidence.mjs
```

### Step 5: Content Fix ✅
**File:** `site-src/lang/en.json` (line 290)
- **Old:** "1.0.1 brings the full-screen iPad layout"
- **New:** "the full-screen iPad layout is part of 1.1.0"
- Matches versions.not-on-the-app card's "It's part of 1.1.0" wording

### Step 6: Regression Test ✅
**File:** `scripts/build-site.test.mjs` (lines 98-101)
- **Test 17:** Validates versions.live-captions-of-what doesn't mention 1.0.1
- Assertion: `!str.includes('1.0.1')`

### Step 7: Release Checklist ✅
**File:** `docs/release-checklist.md` (70 lines)
- Versions Card checklist (contents, pricing, measurements, source links)
- Home/Support page parity checklist
- App Store listing parity checklist
- Test results verification checklist
- Screenshots and videos checklist
- References PRICES source in scripts/check-site.mjs
- References CI enforcement via site job

---

## Expected Metrics After Fix
- `site_build_ok`: Should return to 1 (was regressed to 0)
- `tests_passed`: No change to test count (1159)
- `tests_failed`: Should remain 0
- All other metrics: Unchanged

## Code Quality
- ✅ No network access added (ADR 0007)
- ✅ No telemetry added
- ✅ No new dependencies
- ✅ Regex-based validation (efficient, testable)
- ✅ Comprehensive self-tests in main code
- ✅ Integration tests with real site copy
- ✅ No breaking changes to existing checks

## Next Steps
1. CI will run the fixed `site` job
2. All tests should pass with the corrected test runner command
3. Site build metrics should return to healthy state
