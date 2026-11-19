## North-star fit

**Reuses:** the stateful-pure-struct pattern already used for `SilentEngineWatchdog` (`Packages/CaptionCore/Sources/CaptionCore/EngineFallbackPolicy.swift:146-164`) for the new memory-warning ladder; the existing `FallbackTrigger`/`FallbackAction`/`FallbackReason` vocabulary and `TranscriptionEngine.handle(_:)` (`TranscriptionEngine.swift:357-362`) as the single integration point, instead of a new trigger path; the existing `onFallback` callback idiom (`TranscriptionEngine.swift:158`, wired in `CaptionEngineFactory.make`) for the new shed/switch callback; the existing additive-nullable-field convention on `ConversationRecorder`/`ConversationReport`/`docs/beta/metrics-schema.md` used for `context`/`captionLanguage` (#288) for the new memory-event log; and the `FailureReason.plainLanguage` localized-string pattern for the new note's copy. The ticket's own stated fit ("design's fallback table §5") checks out against the code — `EngineFallbackPolicy.action(for: .memoryWarning, running: .parakeet)` is exactly the one-way `switchToApple` the evidence in #273/#284 describes, fed by `ParakeetBackend`'s real `DispatchSource.makeMemoryPressureSource` (`ParakeetBackend.swift:147-148`), not a stub.

**Simplest sufficient approach:** a single new pure type (`MemoryPressureLadder`, a mutating struct counting warnings seen this session) replaces one `if`-branch in `handle(_:)`. No new trigger types, no architecture change, no live memory re-sampling — "first warning sheds what's still on, second warning switches" is expressed as plain state, not a timer or a second OS signal.

**Tokens/compute:** spends a little (one new struct + tests, a few new fields in the beta schema); saves by reusing the session object's natural lifetime for the ladder's state instead of adding persistence (unlike `EngineFallbackHistory`, which must persist across the day, this must not outlive the session).

**Phone-OS direction:** a session that protects itself under pressure instead of silently degrading is a small step toward "reliable, nothing breaks silently" (north star 2's precondition).

**More capable, not more passive:** she keeps Parakeet's accuracy lead through ordinary memory pressure instead of being downgraded without her knowledge; when it does downgrade, she's told, matching #10's "captions recover or say why" rule and north star 3's test.

**Machine:** no machine choice here — plan only, CaptionCore unit tests run locally (`swift test --package-path Packages/CaptionCore`); the #273 replay re-run is Mac Mini work (`~/seal-replay`, per #273's status comments), outside this worktree.

One correction to the ticket's own framing: it says "if still under pressure, the in-ear voice," implying a live re-check. There's no cheap way to re-measure memory synchronously inside one OS signal, and the codebase has no such re-check pattern. I'm treating "first warning" as shedding *everything currently on* in one pass (labels, then ear voice if labels were already off or also still on) and "second warning" as literally the next distinct `DispatchSource` firing — this is simpler, matches both named acceptance tests exactly, and avoids inventing an untestable live-memory recheck. Flagged as a Decision below rather than assumed.

## Tests first (`Packages/CaptionCore/Tests/CaptionCoreTests/EngineFallbackPolicyTests.swift`, new `MARK: Memory pressure ladder` section, following the existing suite's style)

1. `testFirstMemoryWarningPausesSpeakerLabelsAndStaysOnParakeet` — AC1: one `.warn(labelsOn: true, earVoiceOn: false)` → `[.pauseSpeakerLabels]`.
2. `testFirstMemoryWarningShedsEarVoiceTooWhenBothAreOn` — `.warn(labelsOn: true, earVoiceOn: true)` → `[.pauseSpeakerLabels, .pauseEarVoice]` (covers "if still under pressure, the in-ear voice" as a same-event cascade).
3. `testFirstMemoryWarningShedsEarVoiceWhenLabelsAreAlreadyOff` — break-it case "a warning while labels are already off": `.warn(labelsOn: false, earVoiceOn: true)` → `[.pauseEarVoice]`, not `.switchToApple`.
4. `testFirstMemoryWarningSwitchesWhenNothingIsLeftToShed` — misuse case the ticket didn't name: `.warn(labelsOn: false, earVoiceOn: false)` → `[.switchToApple]` (nothing left to protect Parakeet with, so don't pretend to shed).
5. `testSecondMemoryWarningSwitchesRegardlessOfState` — AC2 + break-it "two warnings a second apart": call `.warn` twice (any state) → second call is `[.switchToApple]` every time, no debounce by elapsed time.
6. `testThirdAndLaterWarningsKeepSwitching` — repeats case: calling `.warn` a third/fourth time after the session is already on Apple still returns `.switchToApple` (idempotent, never regresses to shedding again).
7. `testLadderStateIsPerInstanceNotShared` — misuse case: two separate `MemoryPressureLadder()` instances (two sessions) each start fresh at warning 1 — guards against accidentally making the counter static/global.
8. Update `testEachTriggerOnParakeetTakesTheDocumentedAction` — remove the old `(.memoryWarning, .switchToApple)` pair from the generic `action(for:running:)` table (that bare mapping becomes wrong); add a comment pointing at the new ladder tests instead, so the two don't silently drift apart again.
9. `testNothingHappensWhileOnApple` — keep as-is for `.memoryWarning` (already covers "a warning after the switch has nothing left to do").

`Packages/CaptionCore/Tests/CaptionCoreTests/TranscriptionEngineTests.swift` (or wherever `TranscriptionEngine.handle` is already exercised — check before adding a new file):
10. `testMemoryWarningPausesDiarizerFeedWithoutSwitchingEngine` — drives one real `.memoryWarning` trigger through `TranscriptionEngine.handle(_:)` on a Parakeet-backed engine; asserts the engine stays on Parakeet (`engineName` unchanged) and the diarizer stops receiving samples (no new segments after the pause point) — dependency-failing case: this is the diarizer itself continuing to run fine, just told to stop.
11. `testSecondMemoryWarningSwitchesToAppleAndFiresTheShedCallback` — two `.memoryWarning` triggers; asserts `switchToApple` runs (existing mechanism) and the new `onMemoryPressureEvent` callback fires `.pauseSpeakerLabels` then `.switchToApple` in order.
12. `testConcurrentMemoryWarningsFromMultipleThreadsAreCountedExactlyOnce` — repeats/concurrency case from the north star's test list: fire `.memoryWarning` from several threads at once (mirrors how `DispatchSource`'s queue could overlap with `processBuffer`'s audio thread); assert exactly one shed + one switch happen, never a double-switch or a lost warning — requires a lock around the ladder/`labelsShed` state, not just the bare struct.
13. `testMemoryWarningDuringAnAlreadySwitchedSessionIsANoOp` — wrong-order case: a warning arriving after `switchToApple` has already completed does nothing (no crash, no second `onMemoryPressureEvent`).
14. `testMemoryWarningWhileStopIsInFlightDoesNotCrash` — stale-state case, parallel to the existing `stopped` guard in `switchToApple`: call `stop()` and `handle(.memoryWarning)` concurrently; no crash, no leaked backend.

`Packages/CaptionCore/Tests/CaptionCoreTests/BetaFeedbackTests.swift`:
15. `testMemoryShedEventsAreRecordedInOrderWithTimestamps` — AC3 "every step shows in the beta report": call the recorder's new event method for shed-labels, shed-ear-voice, switch-to-apple in sequence; assert `entry(now:).memoryShedEvents` (or chosen field name) lists all three, in order, each with its reason.
16. `testOldStoredConversationsWithNoMemoryEventsDecodeAsEmpty` — bad/old-input case, parallel to the existing `context`-nil precedent: decode a `ConversationRecorder` JSON blob from "before this field existed" and assert it decodes without throwing and reports no events (nil/empty), not a crash.
17. `testEveryScheduleKeyIsAlwaysWrittenForTheNewField` — parallel to the existing "every schema key is written, null when unknown" rule on `ConversationReport.encode(to:)`: assert the new key is present in the encoded JSON even when there are no events.

`docs/beta/metrics-schema.md`: no test, but the new field's row must be added (additive, schema 1, like the #288 rows) as part of this work, not left undocumented.

## Decisions
<!-- marvin:decisions -->
### shed-scope: What "pause speaker labels" actually does to the diarizer
- [ ] A: stop feeding new audio into the already-loaded diarizer (`LiveDiarizer`/Sortformer) — halts its ongoing inference and growth immediately, resumable, but the loaded Core ML model's resident memory isn't reclaimed (recommended — matches `SilentEngineWatchdog`/existing session-scoped state, no new teardown/reload plumbing)
- [ ] B: fully unload the diarizer's Core ML session on the first shed — reclaims more memory, but needs new teardown-and-reload support in `LiveDiarizer` that doesn't exist today, and the session can't un-shed mid-conversation

### note-scope: Which engine switches get the new on-screen note
- [ ] A: only this ticket's memory-warning switch (recommended — matches the ticket's stated scope; `loadFailed`/`noWordsFromSpeech`/`thermalCritical` stay as they are today, silent)
- [ ] B: every switch away from Parakeet (`engineFallback != nil`), using the same note for all seven `FallbackReason` cases — bigger scope, arguably closer to "a downgrade is never silent," but touches cases this ticket wasn't asked to fix

### note-look: Where the on-screen note sits and what it says (mock-up to follow, same process as #289: branch `mockup/284-memory-note`, real simulator screenshots, `docs/design/mocks/284-memory-note/`)
- [ ] A: a small line under "Listening" naming the engine, same location #289 proposed for the language mismatch — e.g. "Listening · Apple's engine (memory was low)" (recommended for consistency with #289's option A if Gil picks that there)
- [ ] B: a one-off toast that fades after a few seconds, then nothing persists on screen
- [ ] C: an icon only (with VoiceOver/tap for the reason), smallest footprint, reason not visible at a glance

### beta-field-name: What the new beta-report field is called
- [ ] A: `memoryShedEvents: [{action, at}]?` — a short ordered log of this conversation's shed/switch steps (recommended, additive like `context`)
- [ ] B: three separate booleans/timestamps (`labelsShedAt`, `earVoiceShedAt`, `memorySwitchAt`) instead of a list — simpler schema, loses ordering/repeat info if a session gets more than one storm of warnings

## Task List

1. Add `MemoryPressureLadder` to `EngineFallbackPolicy.swift`: pure, mutating struct (`warn(labelsOn:earVoiceOn:) -> [FallbackAction]`) per the design above; extend `FallbackAction` with `.pauseSpeakerLabels` and `.pauseEarVoice`.
2. Update `EngineFallbackPolicyTests.swift`: remove the stale `(.memoryWarning, .switchToApple)` pair from `testEachTriggerOnParakeetTakesTheDocumentedAction`; add the ladder tests (items 1–9 above).
3. `TranscriptionEngine`: add `private var memoryLadder = MemoryPressureLadder()`, `private var labelsShed = false`, `public var earVoiceOn = false` (app-settable), a `memoryLock` (or reuse `routeLock`) guarding them, and `public var onMemoryPressureEvent: (@Sendable (FallbackAction) -> Void)?`.
4. Rewrite `handle(_ trigger:)`: special-case `.memoryWarning` through the ladder (apply each returned action: pause labels / pause ear voice / switch to Apple via the existing `switchToApple(reason: .memoryWarning)` + `recordFallback`), leaving `.loadFailed`/`.noWordsFromSpeech`/`.thermal` on the existing `EngineFallbackPolicy.action(for:running:)` path unchanged.
5. Gate the diarizer feed in `processBuffer` on `!labelsShed` (per shed-scope Decision A), so a shed stops new segments without touching `voiceRecorder`/sound labeler/Parakeet feed.
6. Add TranscriptionEngine-level tests (items 10–14 above) in whichever existing test file already drives `handle(_:)`/`switchToApple` end to end (check `ParakeetIntegrationTests.swift` first — it's already in the memoryWarning grep results).
7. `BetaFeedback.swift`: add `MemoryShedEvent` (action, `at: Date`), `memoryShedEvents: [MemoryShedEvent]?` on `ConversationRecorder` (nil default, matching `context`), a `memoryPressureShed(_:at:)` mutating method, the matching field on `ConversationReport` with its `CodingKeys` case and explicit `encode(to:)` line (per the "every key always written" rule), and wire it into `entry(now:)`.
8. `BetaFeedbackCenter.swift` (app layer): wire `engine.onMemoryPressureEvent` to call the new recorder method; wire `engine.onShedEarVoice`-equivalent (see task 9) into whatever owns Live Translation's ear state (`EarCenter.swift`) so it actually mutes/stops speaking, and pushes `engine.earVoiceOn` up to date.
9. Add `public var onShedEarVoice: (@Sendable () -> Void)?` to `TranscriptionEngine`, fired from `handle(_:)` when the ladder returns `.pauseEarVoice`; wire it in `CaptionEngineFactory`/`EarCenter.swift`.
10. `BetaFeedbackTests.swift`: add items 15–17 above.
11. `docs/beta/metrics-schema.md`: add the `memoryShedEvents` row (additive, schema 1, same style as the #288 rows).
12. Build the on-screen note's mock-up per the note-look Decision (branch `mockup/284-memory-note`, real simulator screenshots, posted on the issue) and wire the chosen look once Gil answers note-scope/note-look — do not wire a final design silently.
13. After merge, re-run the #273 whole-system replay under real memory pressure on the Mac Mini (`~/seal-replay`, `scripts/system-replay/run-ab.sh`, bypassing/observing past the `calm()` gate on purpose this time) and record the result in `docs/perf/whole-system-replay-results.md` — this is Mac Mini operational work, not a Swift test, and can't be done from this worktree.
14. `swift test --package-path Packages/CaptionCore` green; confirm the iPhone app still builds (xcodebuild verify step) with the new callbacks wired but unused by default (`earVoiceOn` defaults false, so existing sessions without Live Translation behave exactly as before on the first warning).

**Untested by this agent:** the actual on-screen note's rendering and the ear-voice mute taking effect in `EarCenter` can only be confirmed by the pipeline's own Simulator screenshot step once task 12's look is approved and wired; task 13 needs the Mac Mini's real replay environment, not available in this worktree.