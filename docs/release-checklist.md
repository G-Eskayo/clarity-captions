# Release Checklist (#XXX)

Pre-App-Review checklist for releasing a version of Seal Speak. Paste this list into each release PR and check off each item (or mark N/A with a reason). All acceptance criteria must be verified before opening the PR to App Review.

**Note:** Version 1.1.0 is currently marked "Coming next" on the site and has no release PR yet. The sections below that reference the 1.1.0 release PR will be completed when that PR opens.

## Prices

Every price in the app, the website, and the store listing matches the current figures:

- [ ] App: $4.99 (once, one-time purchase, iOS)
- [ ] Live Translation: $4.99 (iPhone, iPad, iPhone Duo) from `docs/perf/`
- [ ] Live Translation: $1.99 (Mac) from `docs/perf/`
- [ ] No other prices mentioned anywhere in the code or site
- [ ] StoreKit file at `Apps/Spike/StoreKit/SealSpeak.storekit` shows correct prices
- [ ] Debug fake store prices in `Apps/Spike/Sources/TranslationCenter.swift` match StoreKit

## Versions Card Content

The website's versions page shows the right status, languages and features for this release.

- [ ] Versions card content matches what is built and shipped in the App Store build
- [ ] Release status (e.g., "On the App Store", "Coming next", "In testing") is accurate
- [ ] No single caption language is named in an upcoming release (say "more caption languages" instead)
- [ ] Every number in the release cards is traceable to `docs/perf/` (e.g., accuracy scores, latency numbers)
- [ ] Source links in the versions page point to `main` branch or a full 40-character commit SHA, never a tag or branch name
- [ ] Hebrew site (`he.json`) has no `versions.*` strings (Hebrew doesn't publish versions.html)

## Source Link Integrity

Every GitHub source link on the site and in the app's documentation points to a stable reference.

- [ ] All `github.com/G-Eskayo/clarity-captions/(blob|tree)/<ref>` links use `main` or a 40-character SHA
- [ ] All `raw.githubusercontent.com/<owner>/<repo>/<ref>` links use `main` or a 40-character SHA
- [ ] No source links point to tags (e.g., `v1.0.0`, `v1.1.0`)
- [ ] No source links point to feature branches (e.g., `main-old`, `develop`, `feature-*`)
- [ ] Run: `node scripts/check-site.mjs` passes (verifies all source link refs)

## Home Page Parity

The website's home page accurately reflects the app's current capabilities and limitations.

- [ ] App description matches what is shipped (no promised features not yet built)
- [ ] Captions accuracy and latency numbers match the app's actual performance from `docs/perf/`
- [ ] Device support list matches the app's targeted devices (iPhone, iPad, Mac, iPhone Duo where applicable)
- [ ] No claims about accuracy, speed or medical benefits
- [ ] "Captions can contain mistakes" is stated on the marketing page
- [ ] All device screenshots use the app's English caption language (no language-specific screenshots)

## Support Page Parity

The support page accurately documents what the app does and how to use it.

- [ ] Support page URL in App Store listing (`docs/app-store-listing.md`) matches the built site
- [ ] Support page describes only features that are shipped and live
- [ ] Links in support page work and point to correct sections
- [ ] Support page has no pricing or purchase information (that belongs to the app and store listing)

## App Store Listing

The App Store listing text is accurate and up-to-date.

- [ ] Product name: "Seal Speak" (exact spelling, never "Seal speak" or "Seal")
- [ ] Subtitle: "Captions for conversations" or current exact text from `docs/app-store-listing.md`
- [ ] Description matches `docs/app-store-listing.md` word-for-word (no medical claims, no promises of accuracy)
- [ ] Keywords match the set in `docs/app-store-listing.md`
- [ ] Support URL points to the live site's support page
- [ ] Privacy policy URL points to the live site's privacy page
- [ ] No mention of prices in the name, subtitle, keywords or description (App Review Guideline 2.3.7)
- [ ] Screenshot text and captions are up-to-date (if captions feature set changed, screenshots must too)

## Honest Claims Verification

The website and app follow the honest claims policy (docs/research/evidence/).

- [ ] Run: `node scripts/check-site.mjs` passes (verifies no banned claims in marketing text)
- [ ] No "who is speaking" claims without the caveat that speaker detection can mix people up
- [ ] No promises about accuracy or real-time speed (e.g., "within a second")
- [ ] No hearing or reading improvement claims
- [ ] No "free" language — it's a paid app
- [ ] Mac price ($1.99 for translation) is only mentioned with the Mac, never with iPhone/iPad/Duo
- [ ] Every language's home page has been checked: English and Hebrew must pass the respective language rules

## Build and Test Verification

Core tests pass before submission to App Review.

- [ ] `swift test --package-path Packages/CaptionCore` passes (unit tests green)
- [ ] `xcodebuild` builds for iOS Simulator without warnings
- [ ] Full site CI passes: `node scripts/check-site.mjs` and all site tests green
- [ ] App Store build passes signing (code signing allowed for submission)
- [ ] Testable behavior is listed in the PR description (which features were tested manually, which are automated)

## Notes

- **Deferred for 1.1.0:** This checklist's references to "1.1.0 release PR" are left blank until the 1.1.0 release PR opens. At that time, the checklist will be completed as part of accepting 1.1.0 onto the App Store.
- **Data sources:** All perf numbers must be traceable to a date-stamped file in `docs/perf/` (e.g., `engine-accuracy-comparison.md`). If a number can't be found, the claim must be removed or updated with the latest measurement.
- **Link stability:** GitHub source links are checked by CI (`node scripts/check-site.mjs` runs on every PR). Links that point to non-existent refs or unstable branch names will fail the build.
