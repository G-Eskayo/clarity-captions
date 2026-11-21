## North-star fit

**Reuses:**
- `EngineFallbackPolicy` (`Packages/CaptionCore/Sources/CaptionCore/EngineFallbackPolicy.swift`) — the pure fallback-decision table already used for `loadFailed`/`noWordsFromSpeech`/`thermal`. This ticket extends it with a new pure function for memory warnings instead of inventing a second policy mechanism.
- `TranscriptionEngine.handle(_ trigger:)` / `switchToApple(reason:)` (`TranscriptionEngine.swift:357-400`) — the existing mid-session-switch machinery (keeps mic/diarizer/clock alive, flushes the old backend's words as final) is reused unchanged for the second-warning switch; only the *first*-warning path changes.
- `onFallback` callback precedent (`TranscriptionEngine.swift:158`, wired in `CaptionEngineFactory.make`, `Apps/Spike/Sources/CaptionEngineFactory.swift:80`) — the new `onMemoryEvent` callback for the beta report follows the exact same "fire immediately, don't wait for a caption piece" shape, for the same reason (a switch with no more speech after it must still be recorded).
- `StatusWords` pure functions + `statusLine` (`Packages/CaptionCore/Sources/CaptionCore/MainScreen.swift`, `Apps/Spike/Sources/ContentView.swift:1012`) — the existing "small informational line under Listening/Can't hear" seam (ADR 0012 dim-don't-dismiss) is reused for the "on Apple" note instead of a new banner component.
- `ConversationRecorder`/`ConversationReport` additive-field pattern (precedent: #288's `captionLanguage`/`faceToFace`/`build`) for the new per-step memory-event log, schema stays 1.
- `FaceToFaceEngine.swift:109` already clears `backend.onTrigger` for face-to-face, so this ticket's whole mechanism is correctly scoped to one-way captioning only — no new exclusion code needed.

**Simplest sufficient approach:** one new pure function (`EngineFallbackPolicy.memoryWarningAction`) replacing the one wrong case in the existing table, plus session-scoped counters in the one class that already owns session state (`TranscriptionEngine`). No new actor, no new store, no new UI component.

**Tokens:** spends a little (new fields, one new pure function, one new SwiftUI line) to fix a measured, real-user-facing accuracy bug (#273: 8/40 and 4/40 sessions silently lost Parakeet's accuracy lead). No ongoing cost.

**Phone-OS direction:** neutral — internal reliability fix, not surface area.

**Leaves the user more capable:** yes — she keeps the better engine through ordinary memory pressure instead of silently losing it, and is told plainly when she's on the fallback instead of never finding out.

**Machine:** this agent's sandbox (`swift test --package-path Packages/CaptionCore`) only; the pipeline's simulator build covers the app-build/look-proof stages. The `#273` replay rerun needs the Mac mini's `~/seal-replay` box under real memory pressure — out of scope for this run, flagged below as untested.

## Decisions

<!-- marvin:decisions -->
### t284-shed-steps: How many memory-warning steps before switching to Apple?
- [ ] A: Two warnings total. The first sheds whatever load is still on (speaker labels, then the in-ear voice if labels were already off); the second warning switches to Apple regardless of what's left to shed. Matches the acceptance criteria ("A second warning switches to Apple") literally. (recommended)
- [ ] B: Three warnings total. First sheds speaker labels, second sheds the in-ear voice (if still on), third switches. Matches the "What to build" sentence's literal two-tier shed, but means a bare "second warning" does *not* switch when the ear voice was still on to shed — conflicting with the acceptance criterion as written.

I'm building Option A (it's what the acceptance criteria and the "two warnings a second apart" break-it case actually test against); the pure function below is a one-line change if Gil picks B instead.

## Tests first (CaptionCore, pure where possible; adversarial cases added beyond the ticket's list are marked *)

**`EngineFallbackPolicyTests.swift`** — new `EngineFallbackPolicy.memoryWarningAction(priorWarnings:load:)`:
1. First warning, speaker labels on → `.shedSpeakerLabels`.
2. First warning, speaker labels already off, ear voice on → `.shedEarVoice` (the ticket's own misuse case: "a warning while labels are already off").
3. First warning, both already off* → `.switchToApple` (a free pass that frees nothing isn't worth spending; adversarial case the ticket's list didn't name).
4. Second warning (any load state) → `.switchToApple`.
5. `MemoryLoad` and `MemoryWarningAction` round-trip `Equatable`/raw-value sanity (guards a silent rename breaking the beta-report string).
6. Update `testEachTriggerOnParakeetTakesTheDocumentedAction` and `testNothingHappensWhileOnApple`: `.memoryWarning` through the old `action(for:running:)` now returns `.none` (documented as "ask `memoryWarningAction` instead"), not `.switchToApple`.

**`CaptionEnginePlanTests.swift`** — remove the now-wrong `EngineFallbackPolicy.action(for: .memoryWarning, running: .parakeet) == .switchToApple` assertion at line 58; keep the thermal-critical one.

**New session-level tests** (new file, e.g. `MemoryPressureSessionTests.swift`, `@testable import CaptionCore`, a minimal fake `SpeechRecognizerBackend` so no real Parakeet/Apple model is needed — same technique the design doc proposed for `TranscriptionEngineBackendTests` and never built):
7. One `.memoryWarning` on a Parakeet session: `engine.handle(.memoryWarning)` → engine stays on Parakeet (`engineName` unchanged, `fallbackReason` nil), speaker labels are shed (new read-only flag, or observed via `onMemoryEvent`), `onMemoryEvent` fired exactly once with `.shedSpeakerLabels`.
8. Two `.memoryWarning`s → second switches to Apple: `fallbackReason == .memoryWarning`, `engineName == "apple-speechanalyzer"`, `onMemoryEvent` fired twice (`.shedSpeakerLabels` then `.switchToApple`), `onFallback` (daily-pin callback) fired exactly once (reuses `testOnlySwitchesCountTowardTheDailyPin`'s existing contract).
9. Two warnings a second apart* (ticket's break-it list): fire `.handle(.memoryWarning)` twice back-to-back with no caption piece in between → both events still delivered via `onMemoryEvent` (guards the "piggyback on the next CaptionUpdate" trap that would silently drop the first event — this is *why* `onMemoryEvent` is a direct callback, not a `CaptionUpdate` field).
10. A warning while already on Apple (e.g. after a `.loadFailed` start) does nothing: no `onMemoryEvent` call, `fallbackReason` unchanged (existing `testNothingHappensWhileOnApple`-style guard, now also covering memory).
11. A warning during a call interruption (#10's territory)*: fire `.memoryWarning` while the engine is mid-`switchToApple` from an unrelated trigger (reuse the existing `switching` guard) → no double-switch, no crash (adversarial concurrency case from the ticket's own list, "a second warning during the switch changes nothing" pattern already proven for the old behaviour).
12. Repeats/flood*: ten `.memoryWarning`s in a row on a session already switched to Apple → still exactly one `onFallback`, one `onMemoryEvent(.switchToApple)` (idempotence under a misbehaving memory-pressure source).

**`BetaFeedbackTests.swift`** — `ConversationRecorder`:
13. `memoryEvent(.shedSpeakerLabels)` then `memoryEvent(.switchToApple)` → `entry(now:).memoryEvents == ["shedSpeakerLabels", "switchToApple"]`, in order.
14. Empty session (no memory event ever) → `memoryEvents` is `[]`/omitted, not nil-vs-empty ambiguity; existing `engineFallback`/`engine` fields unaffected (regression guard).
15. A pathological flood of events (cap test)*: 50 `memoryEvent` calls don't grow the stored array unboundedly (bounded per the "space/time complexity = correctness" convention already used elsewhere in this file, e.g. `PercentileHistogram`).

**`MainScreenTests.swift`** — new `StatusWords.engineNote(fallback:)`:
16. `.memoryWarning` → a non-nil note string.
17. `nil`, `.locale`, `.modelMissing`, `.repeatedFallbacks`, `.lowMemory`, `.loadFailed`, `.noWordsFromSpeech`, `.thermalCritical` → `nil` (the note is specific to *this* ticket's memory-driven mid-session switch, not every reason Apple might be running; misuse case beyond the ticket's list*).

**Untested in this pass (say so plainly):**
- The actual app build / UI placement of the note (pipeline's look-proof stage screenshots it after I finish; `StatusWords.engineNote` only gives the pure text).
- `EarCenter.pauseForSession()`'s real effect on `AVSpeechSynthesizer` (needs a device/simulator with headphones; `EarCenter` isn't unit-testable the way `CaptionCore` is).
- The `#273` replay rerun under memory pressure (acceptance criterion 4) — needs the Mac mini's `~/seal-replay` box; this agent cannot run it. Flagging as a follow-up operational step, not skipped silently.

## Task List

1. **`EngineFallbackPolicy.swift`**: add `MemoryLoad` (speakerLabelsOn/earVoiceOn) and `MemoryWarningAction` (`shedSpeakerLabels`/`shedEarVoice`/`switchToApple`) types; add `EngineFallbackPolicy.memoryWarningAction(priorWarnings:load:)` implementing Decision t284-shed-steps option A; change `action(for: .memoryWarning, running:)`'s case to `.none` with a doc comment pointing at the new function. (Tests 1-6.)
2. **`TranscriptionEngine.swift`**: add session-scoped state (a small lock-protected struct: warning count, speaker-labels-shed flag) private to the class; add public `earVoiceOn: @Sendable () -> Bool = { false }` and `onMemoryEvent: (@Sendable (MemoryWarningAction) -> Void)?`; split `handle(_ trigger:)` so `.memoryWarning` routes to a new `handleMemoryWarning()` that calls `memoryWarningAction`, fires `onMemoryEvent`, and either sets the shed flag or kicks off the existing `switchToApple(reason: .memoryWarning)`; gate `diarizer.feed(samples)` in `processBuffer` and the `labels.label(...)` call in `makeResultStream` on the shed flag. (Tests 7-12.)
3. **`BetaFeedback.swift`**: add a `memoryEvents` list to `ConversationRecorder` (bounded, additive `CodingKeys` entry) with a `mutating func memoryEvent(_ action: MemoryWarningAction)`; surface it on `ConversationReport` as `memoryEvents: [String]`. (Tests 13-15.)
4. **`docs/beta/metrics-schema.md`**: document the new `memoryEvents` field in the shape example and the field table, same style as the #288 additions.
5. **`MainScreen.swift`**: add `StatusWords.engineNote(fallback: FallbackReason?) -> String?`, returning a note only for `.memoryWarning`. (Tests 16-17.)
6. **`Apps/Spike/Sources/EarCenter.swift`**: add a session-only `pauseForSession()` (stops speaking, sets a non-persisted flag) distinct from `setOn(false)` (which persists the user's Settings choice); gate `take(from:active:)` on it; reset it when a new conversation starts. Untested by this agent — note in the PR.
7. **`Apps/Spike/Sources/CaptionEngineFactory.swift`**: alongside the existing `engine.onFallback` wiring, wire `engine.earVoiceOn = { EarCenter.shared.isOn && EarCenter.offered }` and `engine.onMemoryEvent` to hop to `@MainActor` and call `EarCenter.shared.pauseForSession()` on `.shedEarVoice`, and `BetaFeedbackCenter.shared.memoryEvent(action)` (new method, mirrors `BetaFeedbackCenter.update`'s persist pattern) on every action.
8. **`Apps/Spike/Sources/ContentView.swift`**: show `StatusWords.engineNote(fallback: model.engineFallback)` near `statusLine`/`statusDetail`, following the existing dim-don't-dismiss treatment (opacity, no dismissal control). Add a debug-only launch-argument scene showing this state for the pipeline's look-proof screenshots, per the playbook. This is the look the ticket says needs the owner's approval — flagged in the PR, not gated on a reply.
9. **Integration tests** (`ParakeetIntegrationTests.swift`, opt-in `CAPTION_PARAKEET=1`, not run by this agent's `swift test`): update `testAMemoryWarningMidSessionSwitchesToAppleAndCaptionsKeepFlowing` to fire a *third* `.memoryWarning` (first sheds, second switches, third is the no-op-while-on-Apple case) and update `testAMemoryWarningInSpanishFallsBackToAppleInSpanish` to fire two warnings before asserting the Apple switch.
10. Run `swift test --package-path Packages/CaptionCore` full suite green; confirm no other call site assumed the old `.memoryWarning → .switchToApple` single-warning behaviour (`rg "memoryWarning"` across the package once more after the change).
11. Note in the PR, as a follow-up (not blocking this PR): rerun the `#273` whole-system replay under memory pressure on the Mac mini's `~/seal-replay` box and score it against the new shed-first behaviour (acceptance criterion 4) — needs real memory pressure and the box, which this agent's sandbox doesn't have.