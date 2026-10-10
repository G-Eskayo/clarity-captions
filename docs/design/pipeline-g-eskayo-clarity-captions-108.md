## North-star fit

- **Reuses before adding anything new:** `HowToUseTour`/`TourCopy`/`TourDemoScript`/`HowToUseTourStore` in CaptionCore are already correct, already tested (32 cases), and match the ticket's six named steps (Start, pause/X, [Save], [New], hold-to-copy, gear) exactly — kept as-is. For the real UI fix: `TextFrames`/`trackWords(in:key:)` (already built for #102/#107's word/button hit-testing) is the exact primitive a real spotlight needs — recording a control's on-screen frame by key — so spotlighting reuses it rather than inventing a new geometry system. The selection chrome's existing clamp idiom (`max(36, ends.start.minY - 46)`) is reused to place the tour card next to its spotlighted control. `veilAnimation`'s reduce-motion duration is reused for the spotlight/card transitions.
- **Correction to the prior attempt's own fit claim:** it said the fix was "move `tour` onto `CaptionModel`" and called that done. Reading the current worktree shows that move is only *half* done: `CaptionModel.perform/save/requestNew` correctly call `tour.didPerform(...)` on `self`, but two leftover call sites in `ContentView` — `pauseVeil`'s New button (`ContentView.swift:702`) and `saveButton`'s Save button (`:717`) — still call a bare `tour.didPerform(...)` that has no declaration in `ContentView`'s scope. That's what's still failing to compile; it's not a new bug, it's the same bug the prior doc diagnosed, left half-fixed.
- **Second correction, more consequential:** the prior doc's own fit claimed `showsDemoContent` was "the entire fix" for demo content. It isn't: `PauseVeil.isVisible(state:hasConversation:)` (`ConversationSession.swift:66-68`) and `saveButton`'s `model.session.saveButton(lines: model.stream.lines, ...)` both key off the *real* `model.hasConversation`/`model.stream.lines`, not the demo-swapped caption list. In a genuinely quiet room (exactly the case the ticket calls out), `[Save]` and `[New]` never render at all — `showsDemoContent` only changes which caption *text* draws, not whether the pause veil and its buttons exist to spotlight. This plan fixes that gap for real (detail below) instead of repeating the same partial claim a third time.
- **Simplest sufficient approach:** no new state machine, no new persistence, no new gesture framework — one more pure CaptionCore function, one SwiftUI-side render-only boolean threaded through three existing call sites, and reuse of `TextFrames` for geometry. The spotlight-cutout itself is a single `Path`/even-odd `.mask`, a standard SwiftUI idiom, not a new abstraction.
- **Token/build cost:** this attempt must also **rebase onto latest `origin/main`** (see below) — unavoidable, not a choice, since the base this worktree branched from is now three PRs behind and the real #107 copy implementation it needs to hook into doesn't exist in this branch's history yet. That's the single biggest line-count item here, but it's integration, not new design.
- **Phone-OS direction:** unchanged — offline, no new permissions, no network, no telemetry.
- **More capable, not more passive:** unchanged in intent, but now actually true in the silent-room case the feature is for — previously [Save]/[New] would have silently failed to appear for her, teaching nothing.
- **Reliability (what actually regressed last time):** `spike-app_build_ok` failed because of a scope error CaptionCore's test suite structurally cannot see. This plan's mitigation (below) is the same discipline the prior attempt promised and then didn't fully apply: hand-trace every `tour.`/`model.` reference across the class/struct boundary before calling it done, not just claim the trace was done.

## Root cause, confirmed in the current worktree (not the prior diff — this one)

`ContentView.swift:699-704` (inside `pauseVeil`, a computed property of `struct ContentView`, which does **not** declare `tour`):
```swift
retroButton(String(localized: "New"), ...) { model.requestNew(); tour.didPerform(.new) }
```
`ContentView.swift:710-718` (inside `saveButton`, same struct):
```swift
retroButton(String(localized: "Save"), ...) {
    withAnimation(.easeInOut(duration: 0.2)) { model.save() }
    tour.didPerform(.save)
}
```
Both are dead weight even if they compiled: `model.requestNew()` already calls `tour.didPerform(.new)` internally (`CaptionModel.requestNew`, line 150) and `model.save()` already calls `tour.didPerform(.save)` internally (line 134). **Fix: delete both stray lines outright** — not rewrite them as `model.tour.didPerform(...)`, since that would double-advance the tour on every Save/New tap. This single two-line deletion is what actually restores `spike-app_build_ok`.

## This worktree is 3 PRs behind — must rebase before touching anything else

`git fetch origin main` shows `origin/main` at `cc42788` (merge of **#109, "Copy: press and hold to select across lines"**, closing **#107**), while this worktree's `HEAD` is still at `2423411` (pre-#107). PR #109 rewrote `ContentView.swift`'s entire caption-selection stack: `.textSelection(.enabled)` is gone, replaced by `CaptionSelection`/`CopyButtonTiming`/`SelectionColors` (CaptionCore, already tested) and a real cross-line press-and-hold-then-Copy-button flow (`copySelection()`, `selectionChrome`). The current worktree's tour changes are layered on the **old** pre-#107 `ContentView.swift` and still use a placeholder `LongPressGesture(minimumDuration: 0.5)` to fake a copy signal — exactly the stopgap the prior doc flagged as temporary "until #107's real settle-timer callback lands." It landed. Plan:
1. Rebase this branch onto `origin/main` (merge commit `cc42788`), resolving the `ContentView.swift` conflict in favor of #109's real selection code as the base.
2. Re-apply the tour's additions on top of that: `@Published var tour`/`showingTour` on `CaptionModel`; `.sheet(...)`'s `onShowTour:` closure; the tour overlay.
3. Hook `.copy` into the **real** completion point: `copySelection()` (`ContentView.swift`, the function that does `UIPasteboard.general.string = ...; clearSelection()`) calls `model.tour.didPerform(.copy)` right after the pasteboard write — the actual moment she copies, not a fake 0.5s hold. Delete the placeholder `LongPressGesture` entirely; it has no reason to exist once this lands.

## The real functional gap: demo content doesn't make its own controls appear

Traced structurally (not assumed): `PauseVeil.isVisible(state:hasConversation:)` requires real `hasConversation`. `saveButton` reads `model.session.saveButton(lines: model.stream.lines, ...)`, also real data. So even with `showsDemoContent` swapping which caption *lines* render, in an actually-quiet room **`[Save]` and `[New]` never render at all**, because nothing makes the veil think there's a conversation. The `.save` tour step would have nothing to spotlight — the exact failure mode the ticket's demo-content bullet exists to prevent.

Fix: a single render-only boolean in `ContentView`, computed once per render, never touching persisted state:
```swift
let demoActive = model.showingTour && HowToUseTour.showsDemoContent(step: model.tour.currentStep, hasConversation: model.hasConversation)
```
Thread it through three existing call sites, display-only:
- `captions(bottomReserve:)`'s line source (already wired).
- `model.veil.isVisible(state: model.state, hasConversation: model.hasConversation || demoActive)`.
- `saveButton`'s `model.session.saveButton(lines: demoActive ? TourDemoScript.lines : model.stream.lines, names: ...)`.

`model.save()` itself, `model.stream`, `model.session`, `currentStore` are never touched by `demoActive` — if she somehow taps `[Save]` while on demo content with nothing real recorded, `session.makeSaved(...)` already returns `nil` on empty content and `save()` no-ops. That's the "never record or save real audio" guarantee actually holding structurally, not just claimed.

**Open question, not silently resolved:** the ticket scopes demo content to "the copy and save steps," but also lists `[New]` as its own spotlighted step, and `[New]` lives in the same veil as `[Save]`. If the room is quiet, by the time the tour reaches `.new` (right after `.save`), `demoActive` goes `false` per the ticket's literal wording and the veil — and `[New]` — disappears exactly when it needs spotlighting. My default: extend the veil-visibility (not the caption-line swap) override to include `.new` too, so `[New]` stays visible across `.save`→`.new`. Flagging this plainly in the PR description for sign-off rather than picking silently, per "choices need options."

## The other real gap: this is currently an instruction card, not a spotlight — the ticket says not to build that

`docs/design/mocks/2026-10-09/09-how-to-use-intro.png` and `v1-polish-spec.md:74-76` are explicit: *"not instruction cards... spotlight on the real Start, X, [Save], caption text, gear."* The current overlay (`ContentView.swift:309-342`) is a full-screen 50%-black scrim with a **centered floating card** and a full-width Back/Skip/Next row — structurally exactly the instruction-card pattern the ticket says not to build. The prior design doc flagged `TextFrames`/`trackWords` as reusable "for future spotlighting" and then deferred it twice. This attempt builds it:
- Move `.coordinateSpace(.named(TextFrames.space))` from the captions `ScrollView` up to the top-level `ZStack` in `body` (the only change needed so controls outside the scroll view — Start/Stop pill, gear, `[Save]`/`[New]` — can report frames into the same space captions already use).
- Tag each spotlightable control with `.trackWords(in: textFrames, key:)`: `controlBar` → one key shared by `.start`/`.pause` (it's the same physical pill morphing state, not two controls — deliberate simplification, no `MorphingControl` internals touched), `saveButton` → `.save`, the `[New]` `retroButton` → `.new`, a caption word frame (already tracked as `"text-\(id)"`) → `.copy`, `settingsButton` → `.gear`.
- Add one pure, tested mapping in CaptionCore: `HowToUseTour.frameKey(for step: TourStep) -> String`, so a future `TourStep` rename can't silently break the lookup (test: 6 cases → 6 distinct non-empty keys).
- Render: `Color.black.opacity(0.6)` masked with an even-odd-filled `Path` (full rect + rounded-rect cutout at the spotlighted frame) — standard SwiftUI cutout, no new type. Card positioned just below the spotlight rect (above it if that would clip), reusing the `max(36, frame.minY - 46)`-style clamp already in `selectionChrome`.
- Chrome redesign to match the mock exactly ("invent nothing beyond it"): "Skip tour" as a persistent top-right text link (not a button in the Back/Next row); a 6-dot step-progress indicator; Back/Next inline at the card's bottom-right; last step (`gear`) reads **"Done ✓"** instead of "Next".
- Guard the tour from ever showing during screenshot/demo capture, which would silently break every existing `-ClarityDemo*` screenshot flow used by #102/#103/#107: `.onAppear { if !DemoMode.isOn && !HowToUseTourStore().hasSeenTour { model.showingTour = true } }`.

## Dead file, same call as before

`Apps/Spike/Sources/HowToUseTourView.swift` is still two comment lines saying it's unused. Delete it.

## Tests I'll write first

**From "How we'll try to break it":**
1. Skip at every step finishes cleanly, including skip-from-last and skip-after-finished (idempotent) — keep the 3 existing cases.
2. Backgrounding mid-tour: `scenePhaseChanged(.background)` must not read or mutate `tour` — test that a mid-tour `HowToUseTour` value is byte-identical before/after calling it.
3. A real conversation starting mid-tour: keep `initialStep` tests; keep/extend `showsDemoContent` tests (`.save`/`.copy` true without conversation, false the instant it flips true) — **add** the veil-visibility composition as a pure case: a small testable helper `HowToUseTour.showsSpotlightTarget(step:hasConversation:) -> Bool` (or fold `.new` into `showsDemoContent`'s scope per the open question above) so the "which steps keep the veil artificially visible" decision is pure and tested, not buried in SwiftUI.
4. Replay while captioning — keep `initialStep(.listening, hasConversation: true) → .pause` and the other pinned states.
5. Largest text size — still no pure-logic surface; flagged untestable here.

**Required + misuse the section didn't name, kept/extended from prior:**
6. `TourStep.allCases` order regression guard.
7. Fresh tour starts at `.start`, not finished.
8. Mismatched `didPerform` silently ignored; duplicate `didPerform` doesn't double-advance; `didPerform` after `isFinished` ignored (now a real hazard — a delayed `save()` `Task` completing after Skip must not resurrect the tour via a stray `tour.didPerform(.save)`, which is exactly why the two stray ContentView call sites are being deleted, not fixed).
9. `back()`/`skip()` boundaries; scripted Next/Next/Back/Back/Next sequence.
10. `HowToUseTourStore`: fresh-false, persists across instances, idempotent `markSeen()`.
11. `TourDemoScript`: non-empty, no sound labels, no audio-reachable type (structural/type-signature guarantee).
12. `TourCopy`: every step non-empty, jargon-free, and — regression test for the previous attempt's shipped placeholder bug — none of `["open question", "todo", "placeholder", "tbd", "["]`.
13. **New** — `HowToUseTour.frameKey(for:)`: all 6 cases return distinct, non-empty keys (guards the spotlight lookup against a silent `TourStep` rename).
14. **New** — repeats/wrong order: `didPerform(.copy)` fired twice in a row (as `copySelection()` could if tapped twice fast) doesn't double-advance past `.gear`.
15. **New** — stale state: tour finishes (Skip) while a `save()` `Task` is still in flight; the `Task` completing afterward leaves `tour.isFinished == true` (covered by #8, stated explicitly as its own case since it's the concrete hazard created by moving `tour` onto the same object as the async save).

Not applicable, same reasoning as before: no outward-facing text input or network boundary → no injection/XSS/CSRF class; no new permission requested.

## What stays untested here, stated plainly

- **Compilation itself.** This environment cannot build `Apps/Spike`. Mitigation: before calling the SwiftUI changes done, hand-trace every `tour`/`model.tour` reference — which type declares it, which type reads it — specifically because that trace is what produced the regression being fixed right now. This is still not a substitute for an actual build; whoever takes this to a simulator must build the Apps/Spike scheme before merge.
- **The rebase itself compiling cleanly against #109's rewritten `ContentView.swift`.** This is new risk this attempt is deliberately taking on (previous attempts didn't have to merge against a moving target). I'll resolve it by hand, re-reading #109's version in full before merging, not by trusting a mechanical conflict resolution.
- Spotlight visual correctness, VoiceOver tour order, Reduce Motion fades-only, Dynamic Type at largest size, and the required GIF/screenshots next to the mock — simulator-only, unchanged caveat.
- Whether the `.new`-step veil-visibility default I'm picking (extend the override) matches what Gil actually wants versus the ticket's literal "copy and save" wording — flagged above as an open question for the PR, not silently resolved.