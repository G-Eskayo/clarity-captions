## North-star fit

Reuses `TranslatedCaptionView` + its `Said == SaidText` convenience init (`Apps/Spike/Sources/TranslatedCaptionView.swift:53-62`), already wired at `ContentView.swift:1087` and `FaceToFaceView.swift:140-143` for #246's folded look — the same component the folded call/room captions in PR #231 draw through. No new view, no new fold-state type: `SaidFold` is for a scrolling list keyed by line id, but `SettingsPage`'s sample is one static line, so a plain local `@State` toggle (the same kind of state `SettingsPage` already owns for its other rows) is the simplest sufficient choice — adding `SaidFold` here would be machinery for a list that doesn't exist. The reworded note text ("Each caption shows its translation; click it to see what was said") is lifted verbatim in spirit from the Mac-only note PR #231 already wrote (`feature/213-mac-call-translation`, `SettingsPage.swift:334`), swapped to "tap" for touch devices — same concept, device-appropriate verb, which is what the parity memory ([[feedback-seal-device-parity]], 2026-11-10, on this very fix) calls for. Spends a small number of tokens on a scoped copy+view fix; saves future ones by removing the only place in the app that still describes the old stacked look. Leaves the user more capable: the sample now demonstrates the real, current interaction (tap to reveal what was said) instead of teaching a layout that no longer exists.

This PR is new, off `main`, separate from #231 (the owner's explicit choice). It runs on the Mac Mini (iOS Simulator + Mac app builds only; no CaptionCore change, so no new machine needed for `swift test`).

**Scope check against the file:** `SettingsPage.swift`'s `preview` (the "How your captions will look" sample, lines 134-181) is unguarded by `#if !os(macOS)` and already renders on both platforms; its stacked branch (`translatedLine`/`originalUnderTranslation`) is what "fold the sample like every caption" targets. `translationOfferNote` (307) and `translationNote` (311) are the "two notes" — both inside the `#if !os(macOS)` "Translate captions" section, so today they only render on iPhone/iPad (the Mac hides that section until #213's wiring lands per #230/#239, confirmed by reading the body of `SettingsPage.swift:52-55`). Nothing else in the repo matches "translation on top" / "underneath" (checked with a repo-wide grep).

## Tests first

`Apps/Spike` has no test target (SwiftUI app code, per repo convention — logic lives in `CaptionCore`). This PR touches no `CaptionCore` file, so **no new XCTest is added**, consistent with how PR #231 itself verified its own Settings-only UI change (screenshots before/after, not a test). Verification is:

- `swift test --package-path Packages/CaptionCore`: unaffected, run to confirm still green (no file in this PR lives there).
- iOS Simulator app build (`CaptionSpike`) and Mac app build (`CaptionMac`): both must succeed, since `SettingsPage.swift` is shared between them.
- Screenshots (see Task List) stand in for the "break it" cases that apply to a text/view change:
  - **Both purchase states** (not bought / bought-and-on) get their own screenshot, since both notes changed.
  - **Light and dark**, since the note color (`muted`) and sample text color depend on theme.
  - **Repeated taps**: `TranslatedCaptionView`'s `onTapGesture` just flips a `Bool`; idempotent by construction, no new state to corrupt (unlike `SaidFold`, which already has its own tests for exactly this).
  - **VoiceOver / accessibility misuse**: the current `preview` wraps the whole sample in one `.accessibilityElement(children: .combine)` with a fixed label (line 155-156) that ignores translation state. Swapping in `TranslatedCaptionView` (which supplies its own label, hint and `.isButton` trait/action) under that same combine wrapper would **silently swallow the tap affordance for VoiceOver** — a real misuse case this change must not introduce. Fix: only apply the fixed-label combine wrapper to the untranslated (plain-text) branch; let `TranslatedCaptionView`'s own accessibility stand when translation is on.
  - **Dynamic Type / long strings**: reworded notes are prose of similar length to the originals; wraps the same way via the existing `Text(note).font(scaled(13))...` in `section(...)` — no new risk.
- **Explicitly untested** (can't be exercised by `simctl`, which can't tap): the real open/close tap interaction on-device, for both platforms. Screenshots will show the sample in its default (closed, "folded") state only — consistent with #246's existing rule that "a new conversation starts folded" — so this PR does not need a throwaway XCUITest target (`docs/agents/pr-requirements.md` "Screens that need a tap") to prove it.

## Decisions

None needed — the owner's `settings-old-look` answer is a complete, unambiguous instruction, and the only implementation call left (showing one default state in screenshots, not both open/closed) is a minor rendering detail, not something the acceptance criteria asked him to choose between.

## Earlier answers to the same question

Checked all 8 citations against their actual content (not just the number match):

- `docs/life-of-a-ticket.md`, `instance/docs/plans/pipeline-verify-timeouts-2026-10-30.md`, `instance/docs/plans/pipeline-visibility-2026-10-07.md`, `instance/docs/plans/ticket-triage-2026-10-07.md` — all four cite **MARVIN's own ticket #213** ("Holds come back: an On-hold group, a Revisit date, a revisit agent") or the disk-space/Simulator-crash infra issue that happened to also affect clarity-captions #213/#214 as a build failure. None are about the Mac Settings look. **Keep as-is** — different ticket/question, a numeric collision across repos, not a stale answer.
- `~/.claude/projects/-Users-gileskayo/memory/project-mom-captioning-app.md`, `project-plan-first-credit-overflow.md`, `project-seal-ear-translation.md` — mention clarity-captions #213 only as a 1.1.0 feature-list line item, an infra-crash log entry, or a pricing note (ADR 0028, $1.99 Mac IAP). **Keep as-is** — different question (feature list / infra / pricing, not the Settings-look fix).
- `feedback-seal-device-parity.md` — already records *this exact* decision ("Gil, 2026-11-10, on the Mac Settings old-look fix, PR #231 / ticket 213: keep parity across devices"), dated the same day as the decision being acted on now. **Keep as-is, no amendment** — it isn't stale, it's the correct standing rule this PR's two reworded notes (both device-facing, not Mac-only) already follow.

No amendment is needed on any of the 8; each is either a different question or already correct.

## Task List

1. In `Apps/Spike/Sources/SettingsPage.swift`: add `@State private var sampleOpen = false` to `SettingsPage`.
2. Replace the stacked branch in `preview` (lines 146-153: `translatedLine(line)` + `originalUnderTranslation(original)`) with `TranslatedCaptionView(translated: line, said: original, font: style.font(for: SystemTextSizeCategory(dynamicTypeSize)), text: style.text.color, muted: muted, mark: style.gear.color, volatileOpacity: style.volatileOpacity, isOpen: sampleOpen, onTap: { sampleOpen.toggle() })`, matching the call site already used at `ContentView.swift:1087` / `FaceToFaceView.swift:140`.
3. Move the `.accessibilityElement(children: .combine)` / fixed `.accessibilityLabel` (lines 155-156) so they apply only to the untranslated (`else`) branch; let the translated branch use `TranslatedCaptionView`'s own accessibility.
4. Delete the now-unused `translatedLine(_:)` and `originalUnderTranslation(_:)` private methods (lines 166-181).
5. Reword `translationOfferNote` (line 307) and `translationNote` (line 311) to describe the folded tap interaction instead of "on top ... underneath", keeping every other fact (device word, one-time purchase, 200 MB download, no-internet-after) unchanged.
6. `swift test --package-path Packages/CaptionCore` — confirm still green (no file here changed).
7. Build `CaptionSpike` (iOS Simulator, signing off) and `CaptionMac` (Debug, signing off) — both must succeed since `SettingsPage.swift` is shared.
8. Screenshots via existing debug flags, no new flag needed, light and dark for each: `-ClarityDemoSettings -ClarityDemoSettingsSection translation` (offer state, not bought) and `-ClarityDemoSettings -ClarityDemoSettingsSection translation -ClarityDemoTranslate es-ES` (bought and on, folded sample + reworded note) — iPhone Simulator. Same two states on the Mac app via its existing `-MarvinSettingsSection translation` scene.
9. `pr-shots` to commit, pin and write the 8 images into the new PR's description.
10. Open the new PR off `main` ("Part of #213"), body states what changed (fold the sample, reword both notes) and includes the screenshots; link PR #231 from it per issue #292's instruction.
11. Reply on PR #231 with `<!-- marvin:decisions-addressed -->`: state `settings-old-look` was acted on in the new PR (link it), and that #231 itself carries no look change so its own pinned screenshots stand unchanged.
12. In the same reply, record the earlier-answers check: the four doc citations are a different ticket (MARVIN's own #213, numeric collision) and the three memory citations are a different question (feature list / infra / pricing); `feedback-seal-device-parity.md` already matches this decision and needs no amendment.