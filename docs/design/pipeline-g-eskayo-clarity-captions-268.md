## North-star fit

**Reuses before adding anything new:**
- `PercentileHistogram` (`Packages/CaptionCore/Sources/CaptionCore/BetaFeedback.swift:78`) — the exact fixed-memory median/P95 structure `lag` and `micLevel` already use; this ticket's three new measurements (translate delay, voice-start delay, behind-by) each get their own instance of it rather than a new stats type. `value(at: 1.0)` (already implemented) gives the "max" the ticket asks for — no new percentile machinery.
- The beta-only gate and per-conversation mutating-method style already in `ConversationRecorder` (`BetaFeedback.swift:153`, e.g. `audioLevel`, `thermal`) — new events (`earPhraseSpoken`, `earTranslationReady`, `earVoiceStarted`, `earVoiceFinished`, `earVoiceCutOff`, `earTranslationFailed`) are added the same way, funnelled through `BetaFeedbackCenter` (`Apps/Spike/Sources/BetaFeedbackCenter.swift`), which is already the single place that gates everything by `isOn`/TestFlight (ADR 0023 fail-closed) — no new center class needed.
- The `context: CaptioningContext?` precedent (`BetaFeedback.swift:174`, added additively for #288) for how to add a field to a `Codable` struct that's already persisted on testers' phones (`FeedbackStore`/`unsent.json`) without breaking decode of records written before this ships: the new field must be **Optional**, not a non-optional default, or an old unsent conversation on a tester's phone silently fails to decode (`try? decoder.decode` in `FeedbackStore.read()`) and all their unsent data for that file is lost. This is a concrete, testable risk, not theoretical.
- The existing bounded-eviction pattern in `EarCenter.speak(_:translation:)` (`Apps/Spike/Sources/EarCenter.swift:193`, `if speakers.count > 200 { speakers = speakers.filter {...} }`) — reused for capping the new tracker's in-flight instance dictionary, so a 2-hour session stays bounded without inventing a new eviction scheme.
- The existing closure-injection pattern already in `EarCenter` (`onCheck: (() -> Void)?`, `EarCenter.swift:41`) and in `ContentView`'s engine setup (`idleStopSetting: { [weak self] in self?.idleStop ?? .default }`, `ContentView.swift:104`) — reused for a new `onVoiceEvent` closure on `EarCenter` (voice started/finished/cut-off) and for getting the live `ConversationSession` into `TranslationCenter` without storing a stale copy.
- **The key insight that avoids inventing any new audio-clock plumbing:** caption lag's own definition (`WordLagTracker.sample`, `TranscriptionEngine.swift:519`) is `lagSeconds = wallClockElapsed − audioEndSeconds`, and `wallClockElapsed` is `Date().timeIntervalSince(sessionStart)` (`FedWallTime.elapsedSinceStart()`). Algebraically, **`phraseEndDate = updateArrivalDate − lagSeconds`** recovers the real wall-clock moment the speaker actually finished that phrase, in the *same* `Date` axis as everything else (translation-ready, voice-start, voice-finish are all naturally captured as `Date()` at their own event sites). This is exactly "the audio clock caption lag already uses," reused by subtraction rather than re-derived — no new plumbing into `TranscriptionEngine`/`CaptionLine` (which stays in pure audio-seconds, untouched) and no `ProcessInfo.systemUptime` (EarCenter's own internal pacing clock) involved at all.

**Why this is the simplest sufficient approach:** every other candidate (threading a wall-clock `Date` field onto `CaptionLine`, or converting `EarCenter`'s `systemUptime`-based pacing clock into audio-seconds) either breaks `CaptionLine`'s existing purity (audio-seconds only, no `Foundation.Date`) or re-derives a wall-clock↔audio-clock mapping that caption lag already computed. Subtracting `lagSeconds` from the arrival `Date` is one line of arithmetic at the one call site (`ContentView.onUpdate`) that already has both values.

**Tokens:** spends a little now (new pure type + tests, ~1 file + edits to 3 existing files) to avoid a second, larger spend later disentangling a second ad-hoc clock. No network, no new dependency, fixed-size histograms keep storage flat regardless of session length.

**Phone-OS direction:** a delay the tester can see in-app (and that MARVIN can later read from the same beta-feedback pipeline, ADR 0024) is a small step toward the system noticing its own degradation and reporting it, rather than Gil going by vibes.

**More capable, not more passive:** this gives Gil a number instead of a feeling during his at-home test — he still judges what's acceptable; the app just stops hiding the number from him.

---

## Decisions

Two points in the ticket are genuinely ambiguous — a different, silently-guessed reading of either is my best guess at what caused the previous attempt's "must-fix" code review. I'm not guessing this time.

<!-- marvin:decisions -->
### repeat-count-meaning: What should "repeat count" (AC #2: "median, P95 and max of each, plus the repeat count") actually count?
- [ ] A: How many times a tester said essentially the same sentence twice as two separate utterances (two distinct caption lines, detected by comparing a word-hash fingerprint the way `rewriteRate` already does, never keeping text) — a tester-behavior signal.
- [ ] B: How many times the tracker caught and collapsed what would otherwise have been a double-counted measurement for the *same* spoken instance (a structural de-dupe safety counter) — this is almost always 0 given `EarPhrases`' one-shot-per-word-range design (confirmed by the existing test `testAnEarlyPhraseThatTurnsOutWrongIsNotSpokenAgain`), so it mostly documents that the guard exists rather than measuring anything that happens in practice.
- [ ] C: Drop this field for now (ship translate delay / voice-start delay / behind-by + the min viable counters below) and revisit once build 10's existing tester-facing question that prompted it is identified precisely.

### cutoff-and-miss-visibility: How should "a translation that never arrives" and "a voice cut off by the next line" be made visible in the report, beyond not corrupting the three histograms?
- [ ] A: Two small additive integer counters next to `earDelay` in the schema — `translationMisses`, `voiceCutOffs` — mirroring how `relabelsPerMinute` and `samples` already sit beside `lag`.
- [ ] B: No separate counters; a miss/cut-off simply contributes nothing to the histograms (silently dropped, "recorded as such" = "not fabricated," nothing more).
<!-- /marvin:decisions -->

I'll build on the assumption that **A** is chosen for both (cheapest, most consistent with the existing schema's style, and reversible — dropping a field later is easy, adding one needs another additive schema bump) unless told otherwise, but the PR will carry these for a real answer before merge.

---

## Tests first (CaptionCore, `swift test --package-path Packages/CaptionCore`)

New file `Packages/CaptionCore/Tests/CaptionCoreTests/EarDelayTrackingTests.swift`, same style as `WordLagTrackerTests.swift`/`BetaFeedbackTests.swift` — pure `EarDelayTracker` value, fake `Date`s (`Date(timeIntervalSinceReferenceDate: n)`), no AVFoundation, no real engine ("fake clock and fake voice" per AC #1):

1. `testPhraseToVoiceStartIsTheDelay` — `phraseSpoken` then `voiceStarted` 1.2 s later records `voiceStartDelay` ≈ 1.2.
2. `testTranslateDelayIsPhraseToTranslationReady` — same, for `translationReady`.
3. `testBehindByGrowsWithBacklogNotWithASingleLinesOwnDelay` — three lines spoken in quick succession (phraseEnd at t=0, 1, 2), each voice-started only after all three have been heard (backlog): line 1's `behindBy` ≈ 2 (how far live speech has already gotten) while its own `voiceStartDelay` is whatever the wait was — the two numbers must differ, proving `behindBy` is not just a renamed `voiceStartDelay`.
4. `testARewrittenPhraseIsOneLineNotTwo` — calling `phraseSpoken` once for a word range, with no second `phraseSpoken` for the same range (matches `EarPhrases`' one-shot design, already covered at the `EarPhrases` level by `testAnEarlyPhraseThatTurnsOutWrongIsNotSpokenAgain`) → exactly one sample lands in the histograms, not two.
5. `testATranslationThatNeverArrivesRecordsNothingNegativeOrEndless` — `phraseSpoken` then `translationFailed`, no `voiceStarted` ever called: zero samples added to any histogram, instance is gone (not retained forever), `translationMisses == 1`.
6. `testAVoiceCutOffByTheNextLineIsRecordedNotLost` — `phraseSpoken`, `voiceStarted`, then `voiceCutOff` (no `voiceFinished`): `voiceStartDelay`/`behindBy` (already computable at voice-start) are still recorded; `voiceCutOffs == 1`; nothing hangs open.
7. `testQueueingBehindABacklogIsNotMistakenForACutOff` — several phrases queued and spoken late, all finishing normally: `voiceCutOffs == 0` — a long wait alone must never be misreported as a cut-off.
8. `testHeadphonesUnpluggedMidLineCutsOffCleanly` — same shape as #6, named for the scenario (`stopAll()`'s real trigger); confirms the same `voiceCutOff` path handles it without a separate code path.
9. `testNoNegativeDelayFromAClockChange` — `voiceStarted`/`translationReady` timestamped *before* `phraseSpoken`'s `endAt` (simulating a backwards clock jump): the resulting delay is floored at 0, never negative, and is still finite/added (distinguishing this deliberately from `WordLagTracker.testNegativeLag`, which keeps negative values as a diagnostic signal for a different purpose — documented in a comment why this one floors and that one doesn't).
10. `testBoundedMemoryOverALongSession` — 10,000 `phraseSpoken` calls where most instances are abandoned (never finished/cut off): the tracker's internal open-instance storage never exceeds its fixed cap (mirrors `EarCenter`'s existing `speakers.count > 200` eviction test shape).
11. `testMaxIsTheTopOfThePercentileHistogram` — `voiceStartDelay`'s reported `max` equals `value(at: 1.0)` on the underlying histogram (proves reuse rather than a second max-tracking mechanism, and pins the approximation).
12. `testRepeatCount...` — exact assertions depend on the `repeat-count-meaning` decision above; written once that's answered.

`Packages/CaptionCore/Tests/CaptionCoreTests/BetaFeedbackTests.swift` additions:

13. `testOldStoredConversationWithoutEarDelayDecodesCleanly` — a hand-built JSON blob shaped like a pre-this-ticket `StoredConversation` (no `earDelay` key at all) decodes successfully via `FeedbackStore`'s `JSONDecoder`, with its other fields (rating, lag, etc.) intact and `earDelay` `nil` — this is the "stale state" / "a person's mistake" (upgrading mid-beta) test and the one most likely to have been missed by a design that made the new field non-optional.
14. `testProductionRecordsNothingForEarDelay` — `BetaEnvironment.production.featuresOn == false` already covered generally (`BetaFeedbackTests.swift:16`); add a direct check that `ConversationRecorder.earPhraseSpoken`-equivalent path is only reachable when `isOn` (exercised at the `BetaFeedbackCenter` level conceptually; at the `CaptionCore` level this is "the report's `earDelay` is `nil` when no event was ever recorded," already implied by #13's shape).
15. `testEarDelayReportFieldsRoundTripThroughJSON` — `ConversationReport` with a populated `earDelay` encodes and decodes losslessly (matches the existing `FeedbackReport`/`ConversationReport` round-trip coverage style).

**Untested by `swift test` (stated plainly, per the playbook):** the real `AVSpeechSynthesizer` delegate timing (`EarCenter`'s new `onVoiceEvent` calls actually firing at the right moments on device), the real `Translation` framework's `translate()` call feeding `earTranslationReady`, and the live readout's look — none of these run outside a real device/Translation session. The pipeline's own app-build and look-proof stages are the check for "it's wired up"; they cannot verify the *numbers* are right on real audio, only that nothing crashes and the readout matches an approved mock-up.

---

## Task List

**Data side (CaptionCore + plumbing — proceeds now):**
1. Add `EarDelayTracker` (`Packages/CaptionCore/Sources/CaptionCore/EarDelayTracking.swift`): three `PercentileHistogram`s (translate delay, voice-start delay, behind-by), bounded open-instance tracking, `phraseSpoken`/`translationReady`/`voiceStarted`/`voiceFinished`/`voiceCutOff`/`translationFailed`, delay-flooring at 0, `repeats`/`translationMisses`/`voiceCutOffs` counters (per the Decisions above), and an `EarDelayReport` value with `{p50, p95, max, samples}` per metric reusing `value(at:)`.
2. Write tests 1–12 above against `EarDelayTracker` directly (no app-layer code needed yet).
3. Add `earDelay: EarDelayTracker?` (optional, for safe decode of pre-existing stored conversations) to `ConversationRecorder` in `BetaFeedback.swift`, plus the six forwarding mutating methods, and include `earDelay: EarDelayTracker.report` in `entry(now:)`.
4. Add `earDelay: EarDelayReport?` to `ConversationReport`, with its own `CodingKeys`/`encode(to:)` entry (matching the manual-encode style already there).
5. Write tests 13–15 above.
6. Update `docs/beta/metrics-schema.md`: new `earDelay` block in the shape example and the field table, marked additive/still schema 1, `null` for conversations recorded before this build (matching the `#288`/`captionLanguage` row's wording style).
7. Add the six new event methods to `BetaFeedbackCenter.swift` (`earPhraseSpoken` returning an instance ID, `earTranslationReady`, `earVoiceStarted`, `earVoiceFinished`, `earVoiceCutOff`, `earTranslationFailed`), each a thin `isOn`-gated forward into `ConversationRecorder`, matching `captionUpdate`/`audioLevel`'s existing shape.
8. `EarCenter.swift`: add `instanceID: Int` to `Queued` and as a parameter to `speak(_:translation:instanceID:)`; add `var onVoiceEvent: ((Int, VoiceEvent, Date) -> Void)?` fired in `speakNext()` (started), `finished(_:)` (finished), and from `stopAll()` for whatever was `current` or still `queue`d (cut off) — matching the existing `onCheck` injection pattern.
9. `TranslationCenter.swift`: at both `ear.take()` sites (`demoFill` and `run(_:)`), capture the phrase-end `Date` (`arrivalDate − lagSeconds`, threaded from `ContentView.onUpdate` the same way `speakers[phrase.lineID]` is already threaded in `EarCenter.take`), call the new `BetaFeedbackCenter` methods around `session.translate(...)` and `ear.speak(...)`, and get the live `ConversationSession` via an injected closure (matching `idleStopSetting`'s existing pattern) rather than a stored copy.
10. `ContentView.swift`'s `onUpdate`: compute and pass along the phrase-end `Date` derived from `u.lagSeconds`.
11. Build-verify (`swift test` + the app-build stage); state plainly that the real on-device timing and the Translation-framework round trip remain untested by this attempt.

**Gated, separate (owner approval required before wiring, not before this PR exists):**
12. Mock-up PR for the live readout ("ear 1.8 s · behind 0.4 s" or whatever it becomes) with Decisions, matching the `#238`/`#255` mock-up-first precedent — no live wiring until approved.
13. Once approved: wire the readout to read `earDelay`'s live, in-progress numbers (not the finalized report) under the captions while "Speak it in my ear" is on, TestFlight builds only.