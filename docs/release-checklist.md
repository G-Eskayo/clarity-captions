# Release Checklist

A reusable checklist for shipping a new version of Seal. Use this template for each release PR (name it `<release>-release-checklist.md` for a specific version if you prefer to keep it in the PR); tick complete items, mark N/A with a reason if applicable.

## Before TestFlight

- [ ] **Versions card matches exactly what ships**: The [Versions page](https://seal-speak.gileskayo.me/versions.html) features list and test results are exactly what this build will have on the App Store. Note: `scripts/check-site.mjs` already enforces that all GitHub links in the site use `main` or a release version, never `HEAD` or a dev branch — this is a sanity check.
- [ ] **Status badge matches App Store Connect**: The green/yellow/red "On the App Store" badge, build numbers, and dates are in sync with ASC.
- [ ] **Only tested and switched-on caption languages**: No caption language is listed in the Versions card or the site unless it shipped in this build and the language toggle in Settings is live.
- [ ] **Prices match App Store Connect**: $4.99 app (once), Live Translation $4.99 iOS/iPad/Duo, $1.99 Mac — verified against current ASC figures (ADR 0028).
- [ ] **Every number on the site is traced to a `docs/perf/` final report**: The performance numbers in the Versions card and on the home page (`#tested` section, iPad translation scores and latency) are from the final, audited test reports in `docs/perf/`. No in-progress or working-copy numbers leak into the site.

## Before Shipping

- [ ] **Home page and support page match the release**: Device requirements (iOS version, iPhone/iPad/Mac support), feature list, and the app's own text (in the app's `.xcstrings` and `.strings` files) match the site's claims exactly. If the app doesn't support a device or language, the site doesn't claim it does.
- [ ] **App Store listing text matches the site**: The name, subtitle, description, keywords, and preview text in App Store Connect match the marketing claims on the site. If the site says something about the app, the ASC listing says it too.
- [ ] **The app builds green for iOS and macOS**: Both `swift test --package-path Packages/CaptionCore` and the full `spike-app` and `mac-app` builds pass.
- [ ] **All checks pass**: `node scripts/check-site.mjs` (no bad refs, prices, honest claims, contrast, links, language parity, demo logic), `node --test scripts/check-site.test.mjs` (content regression and integration tests), `node --test scripts/check-evidence.test.mjs` (research evidence format).

## Notes

- If this is a pre-release (beta on TestFlight, not yet on the App Store), mark the app's status badge as beta, not "On the App Store".
- If you are creating the first release PR for a new version (e.g. 1.1.0), this checklist can be completed as work unfolds — features don't all land at once. The PR should link this checklist in its description for visibility.
- `scripts/check-site.mjs` already runs in CI and the merge gate — every PR to main that touches the site must pass these checks. This checklist is a final verification that the numbers are right, not a substitute for `check-site.mjs`.
