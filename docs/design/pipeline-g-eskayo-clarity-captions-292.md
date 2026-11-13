Good, this confirms `sample(_:)` and all state I need already exist. I now have a complete picture. Let me write the plan.

## North-star fit

**Reuses:** `TranslatedCaptionView` + `SaidFold`'s tap pattern (`Apps/Spike/Sources/TranslatedCaptionView.swift`, already the one view CaptionCore's `SaidFold.swift` docstring says is "the same view on the iPhone, in the face-to-face split and on the Mac") — exactly the component `ContentView.swift`'s live captions (`saidFold.isOpen(line.id)` / `.tap(line.id)`, lines 1085–1094) and `CallPopupView.swift`'s Mac pop-up (lines 167–172) already use. `SettingsPage.preview` (SettingsPage.swift:134–162) is the only remaining caller still drawing translated captions by hand (`translatedLine`/`originalUnderTranslation`, lines 166–181) instead of this shared view — this ticket deletes that one-off duplicate and reuses the real component, per owner's own instruction ("fold the sample **like every caption**"). **No new type, view, or CaptionCore logic is added.**

**Simplest sufficient approach:** a pure copy/view fix in the one file (`SettingsPage.swift`) that already holds both offending notes and the preview — no new files, no new demo/screenshot scaffolding. The wording ("Each caption shows its translation; tap it to see what was said.") reuses the phrase Gil already approved for the Mac's equivalent note in PR #231 ("Approve as shown, go ahead and wire it"), adapted "click" → "tap" for the touch devices this file also serves — not a new, unapproved copy decision.

**Tokens:** spends a small, bounded amount (one file, ~20 changed lines) to close a known look/wording inconsistency the owner already flagged and approved fixing; saves nothing by itself but removes ~15 lines of now-redundant hand-drawn translation UI.

**Phone-OS direction:** neutral — a correctness/parity fix, not new capability.

**More capable or more passive:** neutral for the end user (SeAl's mom); it makes the *shipped* look match the one look Gil already approved across devices, which is what `[[feedback-seal-device-parity]]` (written on this exact ticket) requires.

**Machine:** none specified — Build/App-build/Look-proof stages run per the `ios-app` playbook on whatever the pipeline assigns; nothing here needs a specific machine.

**Is this an owner-decided feature/look change needing a gate?** No new gate needed: the look itself (folded caption) and its wording are already Gil-approved (PR #255/#246, and PR #231's "look" decision); this PR only applies that approved look to the two places that still showed the old one, per his explicit `settings-old-look` decision. Screenshots still go on the PR per his instruction, so he can confirm the applied look, not to re-decide it.

## Scope (confirmed by reading the code and both PRs)

Three spots, all in `Apps/Spike/Sources/SettingsPage.swift` (shared by iPhone, iPad, **and** the Mac via `Apps/Mac/project.yml:29` — not platform-guarded):
1. `preview` (lines 134–162): draws the sample caption with the pre-#246 stacked layout (`translatedLine` + always-visible `originalUnderTranslation`) instead of the folded, tap-to-reveal look every other caption surface now uses.
2. `translationOfferNote` (line 307): "...Each caption shows its translation on top, with what was said underneath..."
3. `translationNote` (line 311): "...Each caption shows its translation on top, with what was said in smaller text underneath..."

(`CaptionLanguagePage.swift` has no matching text — checked, no change needed there.)

## Earlier-answers checklist (all 8 items) — verdict: keep all, none restate an older answer

- `~/.agents/docs/life-of-a-ticket.md`:397 and `~/.agents/instance/docs/plans/pipeline-visibility-2026-10-07.md`:38 and `~/.agents/instance/docs/plans/ticket-triage-2026-10-07.md`:9 — all cite **MARVIN's own** issue #213 ("Holds come back"), a different tracker's number, not clarity-captions#213. Keep.
- `~/.agents/instance/docs/plans/pipeline-verify-timeouts-2026-10-30.md`:11 — cites clarity-captions #213/#214 only as a Simulator-build-crash/disk-space incident (unrelated to the look/wording decision). Keep.
- `feedback-seal-device-parity.md` — already written 2026-11-10 specifically about this ticket; states the current, correct rule. Keep, current.
- `project-mom-captioning-app.md`:11 and `project-seal-ear-translation.md`:19 — cite clarity-captions#213 only for Live Translation **pricing** ($1.99 Mac / $4.99 elsewhere), a different question from Settings' look/wording. Keep.
- `project-plan-first-credit-overflow.md`:22 — cites clarity-captions #213/#214 only as a pipeline-infra Simulator crash reference. Keep.

The PR reply will state these verdicts; no file outside `clarity-captions` needs an edit.

## Tests first

This is a pure SwiftUI view/copy change in the app target (`Apps/Spike`/`Apps/Mac`), which has no XCTest target — matching the precedent PR #231 itself states for its own Settings UI change ("a SwiftUI switch in the app target, which has no test target. So the check was screenshots both ways"). `swift test --package-path Packages/CaptionCore` is unaffected (no CaptionCore file touched) and must stay green exactly as today (currently 1 known, unrelated clock-change failure). There is no new logic to unit-test — `TranslatedCaptionView`/`SaidFold` are already covered by `SaidFoldTests.swift` and used/proven elsewhere.

"How we'll try to break it," applied to a copy/view change:
- **Translation off** (default state, no purchase): preview must still show the plain, untranslated sample exactly as before — verified by reading the unchanged `else` branch stays unchanged.
- **Translation on, long/short sample text, RTL (Hebrew/Arabic target)**: the shared `TranslatedCaptionView` already handles word-wrap and RTL (used live for every language); nothing Settings-specific to break.
- **Dynamic Type at largest size / smallest size**: both fonts still route through `style.font(for:)` / `scaled(_:)`, same as today — no new font path.
- **VoiceOver**: moving off a forced `.accessibilityElement(children: .combine)` wrapper onto `TranslatedCaptionView`'s own label/hint/action (already relied on by the live caption screen and the Mac pop-up) rather than risking that wrapper swallowing the tap action — this is the one real risk in the diff, called out explicitly below as untested by me.
- **Repeated taps**: `sampleFold` is a plain `Bool` toggle — open/close/open is idempotent, same as `SaidFold.tap` elsewhere.
- **Mac target build**: `preview` is *not* `#if !os(macOS)`-guarded, so the Mac app target compiles this too — must build clean there as well as on iOS Simulator.

**Untested by me (stated plainly, per the playbook):** I cannot run or tap the app. The pipeline's existing screenshot scenes (`-ClarityDemoLanguage`/`-ClarityDemoTranslate`, which already drive `language.translationOn`/`target`) will capture the sample in its default **folded** state after my change — proving the look fixed the "stacked" bug. The tap-to-open interaction on the Settings sample specifically is not separately screenshotted (no existing demo flag opens it, and I'm not adding one — the underlying tap/fold mechanism is already proven in production via the live caption screen and the Mac pop-up, so this would be screenshot plumbing, not new risk, and stays out of scope per minimal-sufficient-change). I say this plainly rather than claim it's verified.

## Task List

1. In `Apps/Spike/Sources/SettingsPage.swift`: add `@State private var sampleFold = false` near the other `@State`/`@Environment` properties (~line 33–35).
2. Rewrite `preview` (lines 134–162) to call `TranslatedCaptionView(translated:said:font:saidFont:text:muted:mark:volatileOpacity:isOpen:onTap:)` in the `translationOn` branch instead of `translatedLine`/`originalUnderTranslation`, passing `isOpen: sampleFold`, `onTap: { sampleFold.toggle() }`, `mark: style.gear.color`, `volatileOpacity: style.volatileOpacity`. Drop the outer `.accessibilityElement(children: .combine)`/fixed label on the whole `VStack` (it would swallow `TranslatedCaptionView`'s own interactive label/hint/action); keep an equivalent `.accessibilityLabel` only on the plain `Text(original)` in the non-translated `else` branch, matching how the live caption screen and the Mac pop-up already leave each `TranslatedCaptionView` un-wrapped.
3. Delete the now-unused `translatedLine(_:)` and `originalUnderTranslation(_:)` private methods (lines 164–181) — confirmed no other call sites in the file.
4. Reword `translationOfferNote` (line 307): replace "...Each caption shows its translation on top, with what was said underneath..." with "...Each caption shows its translation; tap it to see what was said..." (keeping the `%@`/one-time-purchase wording around it unchanged).
5. Reword `translationNote` (line 311): replace "...Each caption shows its translation on top, with what was said in smaller text underneath..." with "...Each caption shows its translation; tap it to see what was said..." (keeping the From/download-pack wording around it unchanged).
6. Run `swift test --package-path Packages/CaptionCore` to confirm the suite is unchanged (same single known clock-change failure, nothing new).
7. Verify both app targets build (`CaptionSpike` iOS Simulator, `CaptionMac`) — the pipeline's own app-build verify step, since `preview` is shared, unguarded code.
8. Post the PR (linking issue #292 and PR #231) with before/after screenshots of the Settings sample (translation on, light + dark) and the two reworded notes, plus the `<!-- marvin:decisions-addressed -->` reply on PR #231 answering `settings-old-look`: what changed, the commit, confirmation the images are retaken/pinned, and the earlier-answers checklist verdicts above.