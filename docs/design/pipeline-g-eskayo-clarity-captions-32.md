## North-star fit

- **Reuses**: the `NemoTextProcessing` trait FluidAudio already publishes at our exact pinned revision (`Packages/CaptionCore/.build/checkouts/FluidAudio/Package@swift-6.2.swift:27-38`, revision `0b1f4628...`/v0.17.5, matching `Package.resolved`) — `traits: []` on the dependency drops the static binary with zero forking. Also reuses this repo's existing credits machinery (`ThirdPartyNotice.swift`, `CreditsEntry.swift`, `NOTICE.md`, `ThirdPartyNoticeTests.swift`) exactly the way #271 already removed/corrected a stale license entry.
- **Simplest sufficient approach**: flip one existing, upstream-documented trait off. No new dependency, no version bump, `Package.resolved` is untouched (traits aren't part of the resolution record) — this is config, not a dependency change in the sense the repo guardrail means (adding/removing/bumping a package).
- **Tokens/cost**: cheap — one line in `Package.swift`, a prune of now-false credits text, 3-4 small tests. No new build-phase scripting, no abstraction.
- **Phone-OS direction**: neutral (compliance/size hygiene, not a capability).
- **User capability**: neutral — smaller download and cleaner legal footing, doesn't change what she can do.
- **Where this doesn't fully close the ticket**: the LuxTTS English lexicon (`luxtts_en_us_lexicon.tsv.zz` + aux json, ~1 MB total) ships as an unconditional `.process()` resource on FluidAudio's single `FluidAudio` target (`Package@swift-6.2.swift:42-55`) — not trait-gated, no smaller product exists upstream at this version. Confirmed no license for it anywhere in FluidAudio's own `ThirdPartyLicenses/` or `Documentation/TTS/LuxTts.md` (checked both; the doc even says it was "harvested offline from espeak-ng via piper_phonemize" with no license discussion). The only way to drop the bytes is forking/vendoring just the diarizer out of FluidAudio — rejected: a permanent fork-maintenance burden to save ~1 MB, against north star 1 and the Colton check, and it drops us off FluidAudio's upstream fixes. That half is a genuine owner Decision, below.

## Tests to write first

The issue has no "How we'll try to break it"/Attacks section, so these come from the acceptance criteria plus misuse of a build-config change:

1. **`testFluidAudioDependencyOptsOutOfNemoTextProcessingTrait`** — read `Package.swift`'s source text, assert the FluidAudio `.package(...)` line contains `traits: []`. Catches someone silently reverting the opt-out on a future edit.
2. **`testNemoTextProcessingIsNotLinked`** — `XCTAssertFalse(TextNormalizer().isNativeAvailable, "NemoTextProcessing binary must be excluded via traits: [] (#32)")`. This is the actual link-time truth, and deliberately uses an **instance**, not `TextNormalizer.isNativeAvailable` — the exact mistake that crashed the first automated attempt (`isNativeAvailable` is a non-static `let`, confirmed at `ITN/TextNormalizer.swift:37,39`).
3. **`testNoStaleNemoTextProcessingNotice`** — `ThirdPartyNotice.all` has no `"nemotextprocessing"` id, and `NOTICE.md` no longer contains a `"## NemoTextProcessing"` heading. Directly implements AC #4 (notice list matches the binary) as a regression guard, not a one-off manual check.
4. **`testCreditsEntryDoesNotClaimNemoTextProcessingCoverage`** — `CreditsEntry.coveredByFullLicenseTexts` no longer contains `"nemotextprocessing"`.
5. **Regression**: existing `testThirdPartyNoticesAreComplete`, `testFluidAudioNoticeExists`, `testEveryNoticeLinksToItsSource`, `testSortformerNoticeExists`/`...ShipsTheAgreement...` must still pass unedited — proves removing one entry doesn't break the generic well-formedness checks or the unrelated Sortformer notice.
6. **Misuse the ticket didn't name**: a future `swift package update` moves FluidAudio past the version where this trait exists — tests #1+#2 together fail loudly (either a resolver/compile error from the vanished trait name, or `isNativeAvailable` flipping back to `true`) instead of silently re-bundling ~28 MB.
7. **Decision-dependent** (see below): once the owner picks a LuxTTS-lexicon option, one more assertion matching that path — either a new `NOTICE.md`/`ThirdPartyNotice` entry documenting the accepted-risk note, or nothing new if the "ship as-is, no claimed license" option is taken (there's no code fact to assert for "we did nothing").

**Time/space complexity**: every new test is an O(file size) string scan over `Package.swift` (~25 lines) or `NOTICE.md` (~520 lines) — negligible, same order as the existing `ThirdPartyNoticeTests`.

<!-- marvin:decisions -->
### luxtts-lexicon-license: The LuxTTS English lexicon (~1 MB) has no license anywhere in FluidAudio's own repo, and SwiftPM can't exclude it without forking. What do we do?
- [ ] Ship it as-is, documented as an accepted risk in ADR 0014: it's FluidAudio's own offline-harvested phonetic data (probed from espeak-ng's *output*, not a copy of espeak-ng's dictionary files or source), most likely factual/non-copyrightable pronunciation data; note the gap in NOTICE.md rather than inventing a license that doesn't exist upstream (recommended — matches the size/cost tradeoff, keeps FluidAudio un-forked)
- [ ] Leave it unresolved and open the question with FluidAudio upstream (an issue asking them to license it or gate it behind a trait), keep shipping it unchanged until they answer
- [ ] Fork/vendor only the Diarizer sources out of FluidAudio into this repo and drop the SwiftPM dependency entirely, to guarantee nothing TTS-related can ever ship again

## Task List

1. [ ] `Packages/CaptionCore/Tests/CaptionCoreTests/ThirdPartyNoticeTests.swift`: add the four new tests above (they fail against today's code — `TextNormalizer` still linked, `nemotextprocessing` still credited).
2. [ ] `Packages/CaptionCore/Package.swift`: add `traits: []` to the FluidAudio `.package(...)` dependency, matching the exact syntax FluidAudio's own `Package@swift-6.2.swift:31` documents.
3. [ ] `Packages/CaptionCore/Sources/CaptionCore/ThirdPartyNotice.swift`: remove the `"nemotextprocessing"` entry (lines 46-53).
4. [ ] `Packages/CaptionCore/Sources/CaptionCore/CreditsEntry.swift`: remove `"nemotextprocessing"` from `coveredByFullLicenseTexts`, and update the now-stale comment above it (line 26) that says it "comes in through FluidAudio."
5. [ ] `NOTICE.md`: delete the "## NemoTextProcessing (statically linked through FluidAudio)" through "## Other Rust dependencies" sections (current lines 331-383); add one line under "## FluidAudio" noting the engine is now excluded via the trait (#32), and — per the Decision's answer — a line on the still-shipping LuxTTS lexicon.
6. [ ] `docs/adr/0014-bundle-diarizer-models-in-the-app.md`: append a dated section recording the trait opt-out, the raw per-slice static-lib size found in this session (`libtext_processing_rs.a`, iOS arm64: 29,432,088 bytes, pre-link-time dead-stripping — the real `.app`-size delta must come from the pipeline's app-build step and gets filled in here, not guessed), the LuxTTS lexicon finding (no license either side, ~1 MB, not excludable via trait/product at this pinned revision), and the Decision's resolved answer.
7. [ ] Run `swift test --package-path Packages/CaptionCore` (full suite, confirming `ThirdPartyNoticeTests` specifically) — this is AC #4's "re-run the credits check."
8. [ ] State plainly in the PR: the real pre/post `.app` size delta is untested by this plan's author (no `xcodebuild`/simulator access here) and depends on the pipeline's own app-build/screenshot stage; this PR only guarantees the *source-level* exclusion and the credits-consistency checks above.