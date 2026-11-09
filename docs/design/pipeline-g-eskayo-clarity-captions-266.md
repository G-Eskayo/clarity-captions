## North-star fit

**Reuses:** `CaptionLanguage.needsNoTranslation` and `CaptionLanguageSwitch.Shown`/`.shown` (`Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift`) and the `From` row's existing download-progress formatting in `SettingsPage.swift` (`fromValue`) — both already ship the two parts of the owner's decision he *didn't* reject ("same language allowed", "From shows its download") and need no changes. The removal itself follows an existing, recorded pattern: [[feedback-dropped-feature-remove-all-traces]] — a dropped feature is deleted in full (code, tests, debug flags, screenshots, doc mentions), never left half-wired "for later."

**Simplest sufficient approach:** delete, don't refactor. The owner chose "Neither: no swap button; changing From and Into one at a time is enough" — there's no replacement UI to design, so the only correct move is removing the `LanguageSwap` plumbing that was built speculatively for the two now-rejected options.

**Tokens:** spends a small amount now (deletion + a PR reply) to avoid repeatedly re-deriving this same question later — leaving `LanguageSwap`/`-ClarityDemoSwap` in place would let a future design re-read it as live, exactly the failure mode the memory above documents from Seal Speak's vocabulary list.

**User capability:** neutral for the end user (no shipped behavior changes — the swap button was never wired to a real control, only shown under a debug flag for the Decision screenshots). It does leave Gil more able to trust the dashboard: his question gets a real answer instead of silence, and the PR body stops claiming work ("built and tested, but not wired") that no longer exists.

I checked the ticket's own stated fit (none given beyond "What to build") against the code — it matches: PR #256's Decisions comment really did pick "Neither," and the swap code really is cleanly separable (confirmed via `git diff origin/main...origin/fix/252-swap-languages`, which touches only 10 non-screenshot files, 4 of which are swap-only).

## Scope, read before planning

Diffed `origin/fix/252-swap-languages` against current `origin/main` (clean, no conflicts — merge-base is main's tip):

**Swap-only (delete entirely):**
- `Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift` — the `LanguageSwap` struct and its doc comment (bottom of file, `plan(from:into:speech:preferred:)` and `into(after:)`)
- `Packages/CaptionCore/Tests/CaptionCoreTests/LanguageSwapTests.swift` — whole file
- `Apps/Spike/Sources/DemoMode.swift` — `static var swap: String? { value(after: "-ClarityDemoSwap") }`
- `Apps/Mac/Sources/IPhoneViewShims.swift` — `static let swap: String? = nil`
- `Apps/Spike/Sources/SettingsPage.swift` — both `#if DEBUG ... DemoMode.swap ...` blocks (around the From and Into rows) and the `swapProposal(systemName:)` helper
- `docs/images/pr/fix-252-swap-languages/swap-a-light.png`, `swap-a-dark.png`, `swap-b-light.png`, `swap-b-dark.png`

**Not swap-only — keep as-is (already matches the owner's accepted parts of the decision):**
- `CaptionLanguage.needsNoTranslation`, `CaptionLanguageSwitch.Shown`/`.shown`, the `TranslationTargetList` filter change, `TranslationCenter.swift` pass-through logic, `LanguageSettings.swift`'s `from`, `SettingsPage.swift`'s `fromValue`, `DemoMode.captionDownload`, and `CaptionLanguageListTests.swift` / `CaptionLanguageSwitchTests.swift` / `CaptionLanguageTests.swift` (verified line-by-line: none of these three test files reference `swap`/`LanguageSwap`) — also `from-downloading-light.png` / `from-downloading-dark.png`.

**No doc/ADR traces found:** `CONTEXT.md` and `docs/adr/` have no mention of the swap-button feature (the only "swap" hits in the repo today are unrelated — memory swap, code-switching engine swap — and predate this branch). Nothing to edit there.

**Stale env note, not in scope:** an old ticket-scan comment on #266 cites a build failure for a missing `Apps/Spike/Resources/Models/ParakeetUltra` directory. That path doesn't exist in this worktree at all and isn't touched by this branch's diff — it's an unrelated environment/model-fetch issue from an earlier run, not something this ticket is responsible for fixing.

## Verification (this ticket's "How we'll try to break it")

This ticket deletes code and answers a question rather than adding behavior, so the checks are removal-completeness checks, not new XCTest cases:

1. **"The notes contradict a chosen option"** — checked: the Decisions comment is unambiguous (`"Neither: no swap button..."` is the only ticked box); the attached note is a question, not a contradicting instruction. No conflict to report.
2. **"The PR changed since the decisions"** — checked: `git diff origin/main...origin/fix/252-swap-languages` is the same 16-file, clean diff; nothing has landed on the branch or on main that touches this area since 2026-11-03.
3. **Compile-time completeness check:** after deleting `LanguageSwap` and its test file, `swift test --package-path Packages/CaptionCore` must still build and pass — this is the test that removal is total (any remaining reference to `LanguageSwap` fails the build, not silently passes).
4. **Grep sweep for leftovers:** after edits, grep the full tree for `LanguageSwap`, `ClarityDemoSwap`, `swapProposal`, `DemoMode.swap` — must return zero hits outside historical GitHub PR text (which isn't a repo file).
5. **Dependency check on `Apps/Mac`:** confirm `IPhoneViewShims.swift`'s `DemoMode.swap` has no call site in Mac sources before deleting it (grep showed it was added only as a stub to satisfy a shared protocol/shape — verify no Mac view reads `DemoMode.swap`).
6. **Untested behavior to state plainly in the PR reply:** I cannot run or tap the app; the pipeline's own iOS-Simulator app-build step is the only check that `SettingsPage.swift` still renders correctly without the swap overlay blocks. The real-device same-language captioning and real caption-language download paths were already marked untested in PR #256 and remain so — unaffected by this removal.

## Decisions

None. The owner already made the one decision this ticket needs to act on. His one open remark is a question, answered below, not a new choice — it does not get a Decisions block.

**Answer to post on PR #256** (reply carrying `<!-- marvin:decisions-addressed -->`):
- States the decision was carried out: swap button code, tests, debug flag and its four screenshots removed outright (not left unwired) — names the commit once made.
- Answers "do we have the behaviors specced out for how it should react in all edge cases for UI/UX?" honestly: no separate UX-edge-case spec document exists for this feature; the closest thing is the PR's own "Tests first" list and the CaptionCore XCTest files (`CaptionLanguageSwitchTests`, `CaptionLanguageListTests`, `SameLanguageTranslationTests`), which are the executable spec for the parts that shipped (same-language pass-through, From's live download state, failed/superseded/cancelled picks). With the swap button dropped, its edge cases (region fallback, script-crossing, mid-swap download failure) are moot — their tests are deleted along with the feature, not left stranded.
- States screenshots: the two `from-downloading-*` images stand unchanged (that look didn't change); the four `swap-a-*`/`swap-b-*` images are deleted, not retaken, because the feature they depicted no longer exists.
- Proposes a small edit to the PR body's "What changed" bullet ("The swap button's rules are built and tested, but the button isn't wired...") to say it was removed per the owner's decision, so the description stops describing dead code.

## Task List

1. Create/checkout a local branch tracking `origin/fix/252-swap-languages` in this worktree (do not touch `main`).
2. Delete the `LanguageSwap` struct and its doc comment from `Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift`.
3. Delete `Packages/CaptionCore/Tests/CaptionCoreTests/LanguageSwapTests.swift`.
4. Remove `DemoMode.swap` from `Apps/Spike/Sources/DemoMode.swift`.
5. Remove `DemoMode.swap` stub from `Apps/Mac/Sources/IPhoneViewShims.swift` (after confirming no Mac call site reads it).
6. Remove the two `#if DEBUG ... DemoMode.swap ...` blocks and the `swapProposal(systemName:)` helper from `Apps/Spike/Sources/SettingsPage.swift`.
7. `git rm` the four swap screenshots: `swap-a-light.png`, `swap-a-dark.png`, `swap-b-light.png`, `swap-b-dark.png` under `docs/images/pr/fix-252-swap-languages/`.
8. Run `swift test --package-path Packages/CaptionCore`; confirm it's still green (no `LanguageSwap` references left to break the build) and note the pass count change (fewer tests than PR #256's reported 1023, by exactly the removed `LanguageSwapTests` cases).
9. Grep sweep for `LanguageSwap`, `ClarityDemoSwap`, `swapProposal`, `DemoMode.swap` across the repo to confirm zero remaining references.
10. Commit the removal on the branch with a message naming #252/#256 and the owner's decision.
11. Push the branch.
12. Edit PR #256's body "What changed" bullet to say the swap button was removed per the owner's decision (via the gated `gh` wrapper), keeping the existing ticked Decisions section untouched as the record.
13. Post the PR #256 reply with `<!-- marvin:decisions-addressed -->`: what changed, the commit, the screenshot disposition (two stand, four deleted), and the answer to the owner's UX-spec question.
14. Close out ticket #266 once the reply and commit are both in place (it self-closes per the ticket's own filing rule once PR #256 is addressed).