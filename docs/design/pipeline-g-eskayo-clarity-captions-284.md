## North-star fit

- **Reuses before adding anything new:** `EngineFallbackPolicy.action(for:running:)` and `FallbackTrigger`/`FallbackReason` (`Packages/CaptionCore/Sources/CaptionCore/EngineFallbackPolicy.swift:66-118`) — the memory-warning trigger already exists, it just maps straight to `.switchToApple` today, which is exactly the bug #284 reports. `TranscriptionEngine.switchToApple(reason:)` (`TranscriptionEngine.swift:366-400`, including `recordFallback`/`onFallback` and the 24 h pin) is reused unchanged — only *when* it's called moves, from warning 1 to warning 2. `CaptionUpdate.engine`/`engineFallback`, already snapshotted onto every update and consumed by `BetaFeedbackCenter.captionUpdate` (`BetaFeedbackCenter.swift:138-144`) and `ConversationRecorder.engineUsed` (`BetaFeedback.swift:246-249`), is the exact pattern the new shed fields follow. `EngineFallbackPolicy.memoryFloor` (400 MB, already used by `EngineFallbackPolicy.engine(...)`) is reused as the "still under pressure" threshold rather than inventing a second number. `EarCenter.foregroundChanged`'s `stopAll()` (`EarCenter.swift:240-243`) is the existing precedent for a temporary, settings-untouched pause — the memory pause reuses that shape instead of `setOn(false)`.
- **Simplest sufficient approach:** no new engine, no new notification mechanism, no new ADR. The change is a small ladder inside the existing fallback trigger plus two booleans on the existing report row. The in-ear-voice shed is one flag and one `stopAll()` call, not a new subsystem.
- **Where it spends tokens, not saves them:** this ticket genuinely needs new behavior (shedding didn't exist before), so it isn't a reuse-only win; the spend buys the north star directly — "a downgrade is never silent" — by making the *first* memory warning invisible to her instead of an immediate accuracy drop.
- **Phone-OS direction:** neutral; this is reliability plumbing, not a new capability surface.
- **User capability:** more capable — she keeps Parakeet's accuracy lead (13.8% vs 17.2% WER) through a transient memory warning instead of losing it for the rest of the session on a notification that, per the #273 replay, often says more about what else the OS is doing than about her conversation.
- **Machine:** `swift test --package-path Packages/CaptionCore` on this worktree for everything below except the #273 replay rerun, which needs the Mac build host and the recordings `scripts/system-replay` already uses (flagged below as the one acceptance criterion this run can't execute).
- **Fit with #10:** the ladder's state (`LoadShedState`) lives on the same `TranscriptionEngine` instance that already survives a session across lock/background/call-interruption per the existing mid-session-switch machinery; it is session-scoped (reset only when a new `TranscriptionEngine` is created for a new conversation), the same lifetime #10 already uses for `fallbackReason`. No #10 behavior is built here, and no assumption about foreground-only state is introduced — the ladder runs identically whatever #10 is doing with the UI.

## What the current code gets wrong (confirmed by reading it)

`EngineFallbackPolicy.action(for: .memoryWarning, running: .parakeet)` returns `.switchToApple` unconditionally (`EngineFallbackPolicy.swift:103`), and `TranscriptionEngine.handle(_:)` calls `switchToApple` the first time this fires (`TranscriptionEngine.swift:357-362`). That's exactly the bug: one warning, silent session-long switch. `ParakeetIntegrationTests.swift:143-165` (`testAMemoryWarningInSpanishFallsBackToAppleInSpanish`) encodes this old assumption with a single `.handle(.memoryWarning)` call expecting an immediate switch — it will need to fire twice under the new ladder.

## Design

**Pure policy** (`EngineFallbackPolicy.swift`):

```swift
public enum LoadShedAction: Sendable, Equatable { case none, pauseSpeakerLabels, pauseEarVoice }

public struct LoadShedState: Sendable, Equatable {
    public private(set) var warnings = 0
    public private(set) var speakerLabelsPaused = false
    public private(set) var earVoicePaused = false
    public init() {}
}

extension EngineFallbackPolicy {
    /// One `memoryWarning` while on Parakeet (owner, #284/#296): shed load before ever switching engines.
    /// Pure given the same state and memory reading; `shouldSwitch` leaves the switch itself to the caller,
    /// which already owns `TranscriptionEngine.switchToApple`.
    public static func memoryWarningShed(_ state: inout LoadShedState, availableMemory: UInt64) -> (action: LoadShedAction, shouldSwitch: Bool) {
        state.warnings += 1
        if state.warnings >= 2 { return (.none, true) }
        if !state.speakerLabelsPaused { state.speakerLabelsPaused = true; return (.pauseSpeakerLabels, false) }
        if !state.earVoicePaused, availableMemory < memoryFloor { state.earVoicePaused = true; return (.pauseEarVoice, false) }
        return (.none, false)
    }
}
```

`action(for: .memoryWarning, running:)` changes its `.memoryWarning` row to return `.none` (memory warnings no longer flow through the generic path — a one-line change with a comment pointing at `memoryWarningShed`).

**`TranscriptionEngine.swift`:**
- `diarizer` becomes `private var diarizer: LiveDiarizer?` behind a new `diarizerLock` (currently a non-optional `let`, read on the audio thread in `processBuffer` and in `diagnostics`/`makeResultStream`/`makeFaceToFaceStream`/`stop()`). Shedding calls `diarizer?.finish()` then sets it to `nil`, which drops FluidAudio's Sortformer `MLModel` (≈241 MB) via ARC — the actual memory relief, not just stopping `feed()`. Every read site becomes `diarizer?.segments ?? []` / `diarizer?.diagnostics`; `SpeakerLabelSmoother.label(...)` already returns `nil` for no segments, so captions keep flowing with no speaker row (`SpeakerLabelState.unknown`/`.pending` already render this correctly — no new UI needed for this part).
- New `private var loadShed = LoadShedState()` and `private let shedLock = NSLock()`.
- New injectable `public var availableMemory: @Sendable () -> UInt64 = { UInt64(os_proc_available_memory()) }` — a closure, not a stored value, because it must read memory *at the moment of the warning*; tests override it for determinism (the same reason `EngineFallbackPolicy.engine(...)` takes `availableMemory` as an explicit parameter rather than reading the OS itself).
- New `public var onLoadShed: (@Sendable (LoadShedAction) -> Void)?`, fired only for `.pauseEarVoice` (CaptionCore can't reach `EarCenter`; `.pauseSpeakerLabels` is handled entirely inside this class, `.switchToApple` already has `onFallback`).
- `handle(_ trigger:)` special-cases `.memoryWarning` before the existing generic path: guards `running == .parakeet` (else no-op, matching `testNothingHappensWhileOnApple`), calls `memoryWarningShed` under `shedLock`, pauses the diarizer or fires `onLoadShed?(.pauseEarVoice)`, and calls the existing `switchToApple(reason: .memoryWarning)` only when `shouldSwitch` is true. Every other trigger (`loadFailed`, `noWordsFromSpeech`, `thermal`) goes through the unchanged generic path.
- Every `CaptionUpdate` gains two always-current booleans, set the same way `update.engineFallback = self.fallbackReason` already is: `update.speakerLabelsShed = shedLock.withLock { loadShed.speakerLabelsPaused }`, `update.earVoiceShed = shedLock.withLock { loadShed.earVoicePaused }`.

**`CaptionUpdate`** (`TranscriptionEngine.swift:6-27`): add `public var speakerLabelsShed = false` and `public var earVoiceShed = false`.

**`BetaFeedback.swift`:** `ConversationRecorder` gains `private(set) var speakerLabelsShed = false` / `earVoiceShed = false`, set sticky-true (never reset to false) via a new `mutating func loadShed(labels: Bool, earVoice: Bool)` called from `captionUpdate`, mirroring `lowPowerModeSeen`'s sticky-bool pattern. `ConversationReport` gains the same two fields (schema-additive, `encode(to:)` updated, default `false` so old stored JSON without them still decodes). `BetaFeedbackCenter.captionUpdate` (`BetaFeedbackCenter.swift:138-144`) calls `$0.loadShed(labels: u.speakerLabelsShed, earVoice: u.earVoiceShed)` alongside the existing `engineUsed` call. `docs/beta/metrics-schema.md` gets the two new fields documented next to the existing `engine`/`engineFallback` row.

**App layer (`Apps/Spike`, untested by `swift test` — flagged):**
- `CaptionEngineFactory.make` (`CaptionEngineFactory.swift:66-85`): alongside the existing `engine.onFallback = {...}`, add `engine.onLoadShed = { action in if action == .pauseEarVoice { Task { @MainActor in EarCenter.shared.pauseForMemory() } } }`, and reset any pause from a previous conversation: `EarCenter.shared.resumeFromMemoryPause()` right before returning the new engine (the natural per-session boundary this factory already is).
- `EarCenter.swift`: new `private var memoryPaused = false`; `func pauseForMemory() { memoryPaused = true; stopAll() }`; `func resumeFromMemoryPause() { memoryPaused = false }`; gate `state`/`take(from:active:)` on `!memoryPaused` the same way `foreground` already gates (`EarCenter.swift:166-168`). Settings (`isOn`, `UserDefaults`) are never touched — this is a runtime pause, not a preference change.
- On-screen note: a small published flag in the screen's model, derived from the two fields already on `CaptionUpdate` (`update.engine == "apple-speechanalyzer" && update.engineFallback == .memoryWarning` — no new CaptionCore API needed, the data already exists). The exact wording/placement is an owner-gated look change (playbook: "Any look change: a mock-up on the ticket and screenshots on the PR") — see Decisions below; the pipeline's own screenshot step supplies that mock-up/look-proof once a scene for it exists.

**Docs:** amend ADR 0025's fallback-trigger table (memory-warning row) and `docs/design/parakeet-engine-switch.md` §5's same row to describe the shed-then-switch ladder instead of "switch to Apple for the rest of the session" (both currently state the old, wrong behavior).

## Tests first (red before green)

Pure, `Packages/CaptionCore/Tests/CaptionCoreTests/EngineFallbackPolicyTests.swift` (new cases) and a new `LoadShedTests.swift` section:

1. One `memoryWarning` on Parakeet with plenty of memory → `(.pauseSpeakerLabels, shouldSwitch: false)`; state now has `warnings == 1, speakerLabelsPaused == true, earVoicePaused == false`. (AC1: "labels pause, Parakeet stays.")
2. One `memoryWarning` on Parakeet with `availableMemory` under `memoryFloor` → still `.pauseSpeakerLabels` first (labels, not voice, go first), `shouldSwitch == false`.
3. A second `memoryWarning` (any memory level, labels already paused) → `(.none, shouldSwitch: true)`. (AC2: "a second warning switches to Apple.")
4. A second `memoryWarning` arriving "a second apart" vs. "immediately back to back" give the same result — the ladder has no time component, only a counter (break-list: "Two warnings a second apart").
5. A warning while labels are already paused from the first warning (break-list: "a warning while labels are already off") → the second warning still switches; it never tries to re-pause labels or get stuck never switching.
6. A third, fourth, fifth `memoryWarning` after the switch → `shouldSwitch` stays `true`, `warnings` keeps climbing, no crash, no re-triggering a second `recordFallback` (bounded growth: `warnings` is a plain `Int`, no unbounded collection).
7. `memoryWarningShed` is a pure function: same `(state, availableMemory)` in → same `(action, shouldSwitch)` out, and the same resulting `state`, called 1,000 times with randomized memory values either side of `memoryFloor`.
8. `action(for: .memoryWarning, running: .parakeet)` now returns `.none` (was `.switchToApple`) — update `EngineFallbackPolicyTests.testEachTriggerOnParakeetTakesTheDocumentedAction` and `CaptionEnginePlanTests.swift:58`. `testNothingHappensWhileOnApple` extended to also cover `handle(.memoryWarning)` on an Apple-backed engine doing nothing.

`TranscriptionEngineBackendTests`-style tests (fake `SpeechRecognizerBackend`, no real model — reuse the existing fake-backend harness):

9. `handle(.memoryWarning)` once on a Parakeet-backed engine with a fake `availableMemory` returning plenty: the next `CaptionUpdate` has `speakerLabelsShed == true`, `earVoiceShed == false`, `engine` still Parakeet's name, `fallbackReason == nil`; `onLoadShed` never called (nothing to tell the app to pause).
10. Same with `availableMemory` under the floor: `onLoadShed` is called exactly once with `.pauseEarVoice` in the same `handle` call that paused the labels, alongside a true `earVoiceShed` on the next update — confirms both sheds can land from a single first warning when memory is still tight (the "if still under pressure, the in-ear voice" line in "What to build").
11. `handle(.memoryWarning)` twice: the second call switches the engine (`engineName` becomes Apple's, `fallbackReason == .memoryWarning`), `onFallback` fires exactly once (reuses `recordFallback`'s existing dedupe, already covered by `ParakeetIntegrationTests`'s `Counter`), and captions never stop (a `CaptionUpdate` keeps arriving across the switch — reuses the existing mid-session-switch assertions already in `ParakeetIntegrationTests`).
12. A diarizer that never finished loading (`prepare()` failed or was still in flight) and then receives a shed → no crash, `diarizer` is nil-safe throughout (`processBuffer`, `diagnostics`, both result-stream builders).
13. Concurrency: fire `handle(.memoryWarning)` from several threads at once (simulating two `DispatchSource` memory-pressure queues under real pressure) → `warnings` never double-counts past what's expected, no data race (reuses the file's existing `NSLock`-per-concern style; this is the "repeats, concurrency" break case).
14. A `memoryWarning` arriving while a different trigger's `switchToApple` is already mid-flight (`switching == true`) → the existing guard in `switchToApple` still holds; no double switch, no crash (extends the existing guard's coverage to this new call site).
15. `BetaFeedback.swift`: `ConversationRecorder.loadShed(labels:earVoice:)` is sticky (once true, a later update with `false` doesn't unset it — mirrors `lowPowerModeSeen`); `entry(now:)`/`ConversationReport` round-trip through `FeedbackReport.json()` with both flags set, both unset, and a decode of an *old* stored JSON blob missing the two keys (defaults to `false`, never throws — "stale state" break case).
16. `FeedbackPreview.cards` (or wherever the preview renders) is unaffected by the new fields being present (no accidental crash/garbling of the existing preview rows).

Explicitly **not** covered by `swift test`, stated plainly per the playbook's own rule:
- `EarCenter.pauseForMemory()`/`resumeFromMemoryPause()` and the `CaptionEngineFactory.onLoadShed` wiring line — `Apps/Spike` has no test target; this is app-layer glue around already-tested CaptionCore behavior.
- The on-screen note's actual rendering — a SwiftUI view, verified by the pipeline's screenshot step against a debug-launch scene, not by `swift test`.
- A real call interruption co-occurring with a memory warning (break-list item 3) — no interruption harness exists at the CaptionCore pure-policy level; the ladder doesn't special-case foreground/interruption state, so nothing in the design depends on it, but this combination is not exercised automatically.
- The #273 replay rerun under memory pressure (AC4) — needs the Mac build host and `scripts/system-replay`'s recordings; flagged as a task to run after merge, not something this sandbox can execute.

## Decisions

<!-- marvin:decisions -->
### t284-shed-within-one-warning: does "if still under pressure, the in-ear voice" check memory within the *same* first warning, or wait for a distinct second notification?
- [ ] A. Within the same first warning: pause speaker labels, then immediately re-check `availableMemory` against the existing 400 MB floor, and also pause the in-ear voice if still under it — both sheds can land from warning 1; only warning 2 switches engines. (Recommended: matches the acceptance criteria literally — AC1 tests exactly "one warning: labels pause, Parakeet stays," AC2 tests exactly "a second warning switches.")
- [ ] B. Three discrete notifications: warning 1 pauses labels, warning 2 pauses the in-ear voice (and stays on Parakeet), warning 3 switches to Apple. ("Second warning... switch to Apple" in the ticket would then mean the second *shed* event, not the literal second notification.)

### t284-note-scope: the on-screen note is written here to appear only when the switch reason is `memoryWarning`. Should it also show for the other silent-switch reasons (`thermalCritical`, `loadFailed`, `noWordsFromSpeech`) that already move her to Apple without telling her?
- [ ] A. Memory warning only, for this ticket — keep the other reasons' silence as a separate, later ticket. (Recommended: matches #284's literal scope; avoids a wider UI change riding on this one.)
- [ ] B. Every silent switch-to-Apple reason, now, since the north star ("a downgrade is never silent") applies to all of them equally.

### t284-note-look: the note's exact wording and placement (owner gate: any look change needs a mock-up before it's wired)
- [ ] A. A small de-emphasized text line near the top of the caption area, in the spirit of ADR 0012 ("dim, don't dismiss"), e.g. "Using the backup dictation to save memory" — shown only while on Apple for this reason, gone once a new conversation starts.
- [ ] B. Something else — Gil describes the look he wants and it's mocked up before wiring.
<!-- /marvin:decisions -->

## Task List

1. `EngineFallbackPolicy.swift`: add `LoadShedAction`, `LoadShedState`, `memoryWarningShed(_:availableMemory:)`; change `action(for: .memoryWarning, running:)` to return `.none`. TDD per tests 1-8.
2. `EngineFallbackPolicyTests.swift` / `CaptionEnginePlanTests.swift`: add the new cases, fix the two assertions that encode the old behavior.
3. `TranscriptionEngine.swift`: `diarizer` → `private var diarizer: LiveDiarizer?` behind `diarizerLock`, nil-safe at every read site (`processBuffer`, `diagnostics`, `makeResultStream`, `makeFaceToFaceStream`, `stop()`, `warmUp(diarizerModelURL:)` untouched). Add `loadShed`, `shedLock`, `availableMemory` closure, `onLoadShed`. Special-case `.memoryWarning` in `handle(_:)`; add `speakerLabelsShed`/`earVoiceShed` to `CaptionUpdate` and set them on every update. TDD per tests 9-14.
4. `ParakeetIntegrationTests.swift` (opt-in, `CAPTION_PARAKEET=1`): update `testAMemoryWarningMidSessionSwitchesToAppleAndCaptionsKeepFlowing`'s comment (first call now sheds, second switches — assertions already correct) and fix `testAMemoryWarningInSpanishFallsBackToAppleInSpanish` to call `handle(.memoryWarning)` twice before expecting the switch.
5. `BetaFeedback.swift`: add `speakerLabelsShed`/`earVoiceShed` to `ConversationRecorder` (sticky, via `loadShed(labels:earVoice:)`) and `ConversationReport` (schema-additive `encode(to:)`). `BetaFeedbackCenter.captionUpdate`: call `loadShed`. TDD per tests 15-16.
6. `docs/beta/metrics-schema.md`: document the two new fields next to `engine`/`engineFallback`.
7. `CaptionEngineFactory.swift`: wire `engine.onLoadShed` to `EarCenter.shared.pauseForMemory()` and reset with `EarCenter.shared.resumeFromMemoryPause()` per new engine. (Untested by `swift test` — app-layer glue only.)
8. `EarCenter.swift`: add `memoryPaused`, `pauseForMemory()`, `resumeFromMemoryPause()`, gate speaking on it alongside `foreground`. (Untested by `swift test`.)
9. Resolve `t284-note-scope` and `t284-note-look` with Gil; add the on-screen note view and a debug-launch scene for it so the pipeline's screenshot step can produce the look-proof. (Untested by `swift test`; look change needs the mock-up gate.)
10. `docs/adr/0025-parakeet-ultra-caption-engine.md` and `docs/design/parakeet-engine-switch.md` §5: update the memory-warning row to describe the shed-then-switch ladder.
11. Full `swift test --package-path Packages/CaptionCore` green; `xcodebuild` app-build verify step green.
12. Rerun the #273 replay under memory pressure (`scripts/system-replay/run-ab.sh` or a new arm) against a build of this branch, score it against the existing B (8/40) and D (4/40) switch rates in `docs/perf/whole-system-replay-results.md`, and record the new arm's numbers there. Needs the Mac build host and existing recordings — flagged as not executable from this sandbox.