# Release Checklist: Seal Speak

A version-agnostic checklist for releases. Copy this into the release PR's description and tick off each item as it's verified.

## Versions Card

**Contents**
- [ ] Card opens and all text is readable (check light and dark mode)
- [ ] Feature list matches what ships in this version
- [ ] Status badge says the version's state (On the App Store, In testing, Planned)
- [ ] Languages listed are only ones that ship in this version (checked in `build-site.test.mjs`: test "17")

**Pricing**
- [ ] Prices match `PRICES` in `scripts/check-site.mjs` (the source of truth; see values below)
  - App: $4.99 (once, no subscription)
  - Live Translation iOS (iPhone, iPad, Duo): $4.99
  - Live Translation macOS: $1.99
- [ ] Mac pricing never appears outside macOS context (`check-site.mjs` enforces this; `site` CI job verifies)

**Measurements**
- [ ] Every number is traced to its source in `docs/perf/`
  - Engine accuracy: `docs/perf/engine-accuracy-comparison.md`
  - Language accuracy: `docs/perf/language-accuracy-comparison.md`
  - Translation (iPad): `docs/perf/translation-comparison.md` and `docs/perf/translation-comparison-results.md`
  - Latency: `docs/perf/engine-accuracy-comparison.md` (Live latency section)
- [ ] Each table cell matches the current report value (build-site.test.mjs checks this)

**Source Links**
- [ ] All GitHub links use `main` or a 40-character commit SHA (never a feature branch; `check-site.mjs` enforces; `site` CI verifies)
- [ ] All external links are live (no 404s)

## Home Page and Support Page Parity

- [ ] Home page (`index.html`) and support page say the same things about:
  - App price: $4.99 once
  - What it does: shows captions of conversations in real time on your iPhone
  - What it runs on: iPhone, iPad (in 1.0 iPhone-sized; 1.1+ full-screen), iPhone Duo face-to-face, Mac
  - Devices it does NOT work on (watches, any others) are absent from claims
- [ ] Honest-claims rules still apply (`check-site.mjs` enforces; test language):
  - No "who is speaking" claims
  - No naming speakers claims
  - No speed or accuracy promises (except "instant" in marketing context is OK)
  - No reading or hearing benefits claims
  - App and captions are in English (or list the languages that ship in this version)
  - Captions can be wrong (stated once per language)

## App Store Listing Parity

- [ ] App Store listing name matches the app's canonical name ("Seal Speak")
- [ ] App Store description says what the site says (same price, same devices, same features)
- [ ] Screenshots or preview video show the version that's live (not a future unreleased version)
- [ ] App Store availability (regions, devices) matches what this PR targets

## Test Results

- [ ] `node scripts/build-site.mjs --check` passes (syntax check)
- [ ] `node scripts/check-site.mjs` passes (all checks: local links, honest claims, contrast, anchors, branch links, etc.)
- [ ] `node --test scripts/*.test.mjs` passes (all tests green):
  - `build-site.test.mjs` (17 tests, including version regression test)
  - `check-site.test.mjs` (6 integration tests for branch links)
  - `lang-offer.test.mjs`
  - `required-checks.test.mjs`
  - `check-evidence.test.mjs`
- [ ] CI `site` job is green (GitHub Actions runs the same tests)

## Screenshots and Videos

- [ ] Versions card shows the correct status, features, and pricing (screenshot in PR)
- [ ] If anything moves or animates, a GIF or video clip shows it (iPad scroll, Duo fold, etc.)
