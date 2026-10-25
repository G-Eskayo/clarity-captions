## North-star fit

**Reuses before adding anything new.** `TourState`, `TourCopy`, `TourStore`, `TourDemoLine`, `TourFrames`/`trackTourTarget`, the callback-driven `TourOverlayView`, and the single `endTour`/`advanceTour` choke point already on disk are correct in their *shape* and stay. I verified this by reading the current working tree rather than trusting the prior design doc's claims — several of its claimed fixes are real (`endTour` choke point, `.pause` target moved to the live control, `eoFill` winding, `onGeometryChange`/`ObservableObject` frame tracking, the two-argument `TourDemoLine.isNeeded`), so I'm not redoing those. One claim was false and is the reason this is attempt 3: the doc said the named coordinate space would move to `ContentView`'s outer `ZStack`; the diff never did it (`TourOverlayView.swift:77` still attaches `.coordinateSpace(.named("tour-space"))` to the scrim, a sibling of the tracked controls, not their ancestor).

**Simplest sufficient approach, re-derived, not assumed.** I re-checked the review's own "notes" (lower severity than `fix_these`) against the current tree instead of trusting their severity label: four of them describe bugs that are *still present* and directly break ticket-stated behavior, not cosmetic nits:
- the quiet-room demo line (an explicit "What to build" requirement) is dead code — `saveButton` returns `.unavailable` (`ConversationSession.swift:33`, empty lines) when the room is quiet, so `pauseVeil` never renders at all (`model.veil.isVisible` requires `hasConversation`, `ContentView.swift:643`) and the Save button the demo line is supposed to unlock for never exists to inject into.
- "replay while captioning" (named explicitly in the ticket's break-it list) is actually broken: `onReplayTour` always resets to `TourState()` at `.start`, but if captioning is already running the Start control isn't on screen — only Stop is — so the tour can never receive `.startedCaptioning` and sits dead at `.start` until Skip.
I'm fixing both, because leaving ticket-named behavior broken to only satisfy the one bolded `fix_these` item risks a 4th rejection cycle over defects a reviewer will find again. I'm explicitly *not* doing the other three: the `bundle: .module` note doesn't hold up — every other localized string in CaptionCore (`CaptionStyle.swift`, `FailureReason.swift`, `FirstRun.swift`) omits it, the package declares no `defaultLocalization`/string-catalog resources, and `Bundle.module` only resolves if a resource bundle exists — so matching the rest of the package (no `bundle:`) is correct, not negligent.

**Where this spends/saves tokens.** Spends on re-deriving each defect against real code (tracing `saveButton`→`pauseVeil`→`isVisible`, not guessing); saves by leaving the already-correct 80% of the prior diff untouched and by writing one concrete design doc instead of a transcript the next reviewer has to re-derive the diff against.

**Leaves the user more capable.** Unchanged from the approved design: a one-time, skippable walkthrough on the real screen. The fixes make that walkthrough actually completable in the two conditions ADR 0013's target user will realistically hit — a quiet room, and opening Settings to replay it while already talking — rather than silently stalling.

---

## Current defect inventory (verified against the working tree, not assumed)

| # | Defect | Status | Scope |
|---|---|---|---|
| 1 | **Must-fix.** `.coordinateSpace(.named("tour-space"))` on the scrim (sibling), not the outer `ZStack` (ancestor); scrim missing `.ignoresSafeArea()` | Confirmed still present | `TourOverlayView.swift`, `ContentView.swift` |
| 2 | Demo line can never inject — `saveButton` is `.unavailable` (no view, no tracked target) when the room is quiet | Confirmed still present, breaks a named "What to build" requirement | `ContentView.swift` |
| 3 | Replay while already captioning stalls at `.start` forever | Confirmed still present, named explicitly in the ticket's break-it list | `ContentView.swift`, `Tour.swift` |
| 4 | `onDisappear` sets `CGRect()` not nil → scrim cuts a 16×16 hole top-left once any target has appeared and then disappears (e.g. Copy step after selection clears) | Confirmed still present | `TourOverlayView.swift` |
| 5 | Fixed-size fonts, <44pt Back/Next/Skip hit targets, no Dynamic Type, no VoiceOver announcement on step change | Confirmed still present; also a named acceptance criterion and break-it case, not just a note | `TourOverlayView.swift` |
| 6 | `onNext`/`onBack`/`onSkip` mutate the `t` captured at render time instead of reading current `tour` | Confirmed still present, trivial fix | `ContentView.swift` |
| 7 | `tourFrames` is `@State` holding an `ObservableObject`, should be `@StateObject` | Confirmed still present, trivial fix | `ContentView.swift` |
| — | `bundle: .module` | Checked and rejected — inconsistent with the rest of CaptionCore, no resource bundle declared | N/A |
| — | Dead loop variable in `testEveryStepHasExactlyOneRequiredTrigger` | Already fixed on disk (uses `.map`/`Set`, no loop) | — |

---

## Tests written first (`TourTests.swift`)

CaptionCore is the only testable layer (confirmed: `Apps/Spike/project.yml` defines no test target, no `Tests/` directory exists under `Apps/Spike`). Every fix that lives in `TourOverlayView.swift`/`ContentView.swift` is SwiftUI composition and stated plainly as **unverified by test** below — writing a source-grep "test" against those files would be a false coverage signal, not a real one, and I'm not doing that.

New/changed CaptionCore surface, test-first:

```swift
// Tour.swift: add an optional starting step, a general primitive (not an "isCaptioning" concept —
// CaptionCore stays ignorant of what captioning means, ADR 0010).
public init(startingStep: TourStep = .start) {
    self.step = startingStep
}
```

| Case (from the ticket's break-it list + misuse) | Test |
|---|---|
| **Replay while captioning** (ticket-named) | `testReplayStartingStepSkipsStartWhenAlreadyCaptioning`: `TourState(startingStep: .listening).step == .listening`, `.isActive == true` |
| Replay when idle (must not regress the common case) | `testReplayStartingStepDefaultsToStart`: `TourState().step == .start`, `TourState(startingStep: .start).step == .start` |
| A replayed tour mid-captioning still behaves like any other active state (skip/back/triggers) | Already covered — `testSkipFromEveryStep` iterates `TourStep.allCases` including `.listening`; no duplicate test needed |
| Skip at every step | `testSkipFromEveryStep` — kept, unchanged |
| Backgrounding mid-tour | `testFurtherCommandsAfterSkipAreNoOps`/`AfterFinishingAreNoOps` — kept. Reasoning restated: `tour` is plain `@State`, survives backgrounding without special handling; a cold-launch-after-kill mid-tour correctly restarts the tour since `markSeen()` only fires on completion/skip — no fix needed, no new test fabricated for appearances |
| Real conversation starting mid-tour | `testOutOfOrderTriggerWhilePausedDoesntSkipSteps`, `testDemoLineNeverOverwritesRealConversationDuringTour` — kept, unchanged |
| Quiet-room demo line (fixes defect #2) | `testDemoLineNotInjectedOutsideTour`, `testDemoLineInjectedOnlyDuringTourSaveStep`, `testDemoLineNeverOverwritesRealConversationDuringTour` — kept; `isNeeded`'s pure truth table doesn't change, only the SwiftUI call site moves (see below), so no new pure-function test is needed beyond locking the existing 3 cases, which already fully cover the 2×2 truth table |
| Malformed input | `testStepRawValueEnumIsComplete` — kept |
| Repeats / stale state | `testMarkSeenIsIdempotent`, `testFurtherCommandsAfterFinishingAreNoOps` — kept |
| Trigger/step completeness | `testEveryStepHasExactlyOneRequiredTrigger` — kept (already clean, no loop-variable fix needed, contrary to the prior doc) |
| Concurrency | Not fabricated — `TourState` is a value type mutated only from main-actor SwiftUI closures; no shared mutable state to race, unchanged from the prior (correct) reasoning |
| Largest text size, VoiceOver | Not CaptionCore-testable; implemented against `UIFontMetrics.default.scaledValue(for:)` (SettingsSheet's own established pattern, `SettingsSheet.swift:55-57`) and 44pt/54pt targets (matching `settingsButton`'s 44×44 and `tourRow`'s `minHeight: 54`) — **stated plainly as unverified by test** |

---

## The fixes

**1. Coordinate space (must-fix) + safe area.**
- Add `static let space = "tour-space"` to `TourFrames` (mirrors `TextFrames.space`, the proven pattern this was supposed to copy) and use it as `trackTourTarget`'s default `space:` param.
- Move `.coordinateSpace(.named(TourFrames.space))` off the scrim in `TourOverlayView.swift` onto `ContentView`'s outer `ZStack` (`ContentView.swift:295`), the real common ancestor of `portraitLayout`/`landscapeLayout` (which hold every tracked control) and `TourOverlayView` itself. No call-site changes needed elsewhere — `trackTourTarget`'s default already matches.
- Add `.ignoresSafeArea()` to the `SpotlightScrim`'s `.fill(...)` only (not the whole overlay), so the dim reaches the status bar and home-indicator strips without pushing the card/Skip button into unsafe areas.
- **Unverified by test** — pure SwiftUI view composition, no test target exists for Apps/Spike and no simulator is available here. Implemented to match `trackWords`/`TextFrames.space` exactly, the only proven evidence available headlessly.

**2. Quiet-room demo line (defect #2).** Move the injection from inside the Save button's tap action (where it's dead code, since the button doesn't exist yet) to the `.stop` tap handler in `controlBar` — the moment the tour transitions `.pause → .save`:
```swift
case .stop:
    advanceTour(.paused)
    if TourDemoLine.isNeeded(hasRealConversation: model.hasConversation, tourStepIsSave: tour?.step == .save) {
        model.stream.apply(text: TourDemoLine.text, isFinal: true)
    }
```
By the time SwiftUI re-renders, `hasConversation` is already true, so `saveButton` returns `.save` (not `.unavailable`) and `pauseVeil` actually appears. This also lets the same injected line satisfy the `.copy` step (it's now real content in `model.stream`, visible once the veil is tapped away, per `pauseVeil`'s own documented "tap to clear and copy" behavior) — one injection point instead of two, a genuine simplification. Remove the now-dead injection from `saveButton`'s `.save` case. Naturally idempotent against double-taps: a second `.stop` firing would see `hasConversation == true` already and `isNeeded` returns false.

**3. Replay while captioning (defect #3).** Add `TourState(startingStep:)` (above) and use it at the replay call site:
```swift
onReplayTour: {
    showingSettings = false
    tour = TourState(startingStep: model.state == .listening ? .listening : .start)
}
```
**Known, stated limitation:** if the room goes fully silent right after a mid-captioning replay, `.listening` waits for a caption-count change that may never come. Not fixing further — Skip is the ticket's own universal escape for exactly this, and fabricating a synthetic caption-arrival (like the demo line) for `.listening` isn't in the approved design (spec names the demo line for copy/save only). Also not handling "replay while paused with an existing unsaved conversation" as a distinct starting step — flagged, not silently assumed away.

**4. `onDisappear` nil bug (defect #4).** Change `TourFrames.set` to `func set(_ frame: CGRect?, for step: TourStep)`, update `frame(for:)`'s lookup accordingly (dictionary already handles key removal correctly on `nil`), and change `trackTourTarget`'s `.onDisappear` to `frames.set(nil, for: step)`. Matches `TextFrames.set(_:_:)`'s existing optional signature exactly.

**5. Dynamic Type / 44pt targets / VoiceOver (defect #5, and an explicit acceptance criterion).**
- Extract `SettingsSheet`'s private `scaled(_:_:)` (`UIFontMetrics.default.scaledValue(for:)`) into a small shared `Font` extension used by both `SettingsSheet` and `TourOverlayView`, instead of duplicating it — the title/body/button fonts in `TourOverlayView` switch from fixed `.system(size:)` to this.
- Back/Next/Skip buttons get `minHeight: 44` (matching `settingsButton`'s 44×44 and `tourRow`'s 54pt convention); currently ~32-34pt.
- Progress dots get `.accessibilityHidden(true)` (decorative, six meaningless stops otherwise).
- Title+body combine into one accessibility element (`.accessibilityElement(children: .combine)`) so VoiceOver reads them as one stop.
- On step change, post `UIAccessibility.post(notification: .announcement, argument: "<title>. <body>")` — matching the existing `.announcement` convention already used twice in `ContentView.swift` (lines 357, 474), not `.screenChanged`.
- Deliberately **not** adding `.accessibilityAddTraits(.isModal)`: the tour's whole premise is that she taps the *real* control behind the dim, so VoiceOver must still be able to swipe to it — a modal trait would block exactly the interaction the tour requires.
- **Unverified by test** — same reasoning as #1.

**6. Stale closure capture (defect #6).** `onNext`/`onBack`/`onSkip` read `guard var t = tour else { return }` inside the closure instead of closing over the render-time `t`. Trivial, low-risk, matches the reviewer's own suggested shape.

**7. `@State` → `@StateObject` (defect #7).** `tourFrames` becomes `@StateObject private var tourFrames = TourFrames()`. Correctness-neutral today, avoids redundant `@Published` churn when the tour isn't running.

---

## Explicitly not changing

- `bundle: .module` for `Tour.swift`'s strings — checked against the rest of CaptionCore and rejected (see inventory above).
- Card/spotlight layout positions — no documented spec says otherwise; inventing one would be an unapproved UI change.
- The dead loop variable in `testEveryStepHasExactlyOneRequiredTrigger` — already clean on disk.
- Adding an XCTest target to `Apps/Spike` to manufacture coverage for #1/#5/#6/#7 — out of scope, unbuildable/unverifiable here, and a bigger structural change than this ticket asks for.

## Verification plan

Run `swift test --package-path Packages/CaptionCore` after each CaptionCore change (the `TourState(startingStep:)` addition and its two new tests). Apps/Spike changes (#1, #2's wiring, #3's wiring, #4, #5, #6, #7) cannot be built or run in this environment — stated plainly as unverified by test, verified instead by exact reuse of already-shipped patterns (`trackWords`, `TextFrames.space`, `SettingsSheet.scaled`, the existing `.announcement` convention) and by re-reading the finished diff against this doc's defect list line-by-line before calling it done. Screen recordings/screenshots for the acceptance criteria and VoiceOver walkthrough cannot be captured headlessly either; the PR will say so plainly rather than claim them.