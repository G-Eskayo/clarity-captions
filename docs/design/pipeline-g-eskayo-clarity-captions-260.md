## North-star fit

**Reuses:** `Packages/CaptionCore/Sources/CaptionCore/VoiceCoverage.swift` (header: *"Moved from the #233 spike (Packages/EarSpike, PR #237) so the app can use it"*) is the exact precedent for moving pure spike logic into `CaptionCore` unchanged; `Tests/CaptionCoreTests/EarVoiceCoverageTests.swift` is the precedent for moving its Swift-Testing (`@Test`) tests in unchanged, even though the rest of the suite is XCTest. `Packages/CaptionCore/Sources/CaptionCore/LiveDiarizer.swift` (`NSLock`-protected `final class ... : @unchecked Sendable`) is the concurrency pattern for a new tracker fed from the audio thread and read from the main actor. `TranscriptionEngine.swift:466-486` (`processBuffer`, which already feeds `diarizer`, `soundLabeler`, `faceToFace` from one place) is the hook point for feeding a new per-speaker voice tracker — no new audio path needed. `EarSettingsRows` (`Apps/Spike/Sources/EarViews.swift`) is the already-approved pill-row pattern for any future "Sound like the speaker" row. Everything here is wiring already-measured, already-tested logic into an already-existing feed loop; nothing new is invented.

**Simplest sufficient approach:** ship the Spanish calibration numbers from `docs/perf/ear-translation/voice-match-mac.json` as a small literal Swift table in `CaptionCore` (a few hundred bytes), not a bundled JSON resource — `CaptionCore`'s `Package.swift` has no resource-bundling precedent, and `VoiceMatch.match` already degrades safely to today's single voice when its calibration list is empty, so every other target language needs zero new code, just no data.

**Spends tokens on:** real per-speaker audio/text plumbing (new `SpeakerVoiceTracker`, a `speaker` field on `EarPhrases.Phrase`, a `speakerTraits` passthrough next to the existing `diagnostics` one) — this is genuinely new integration surface, not avoidable, because the owner's decision ("voice, pitch and pace per speaker") is the headline of #247 part 1.

**Phone-OS direction:** none directly; this is a one-app audio feature.

**User capability:** leaves the user more capable — a captioned conversation becomes easier to follow (who's talking, from the ear alone) without asking anything of them beyond an existing settings toggle; nothing is taken over that they used to do themselves.

**Checked against the ticket's stated fit:** the issue's own "What to build" doesn't restate a fit; PR #254's decisions ("wire: A", "setting: B", "timbre: A") are exactly what's below.

---

## What the three decisions require

- **wire: A** — per-speaker voice/pitch/rate, shipped calibration table, new speaker's first early phrase in the default voice (already how `VoiceMatch.match` degrades when a speaker has no traits yet).
- **setting: B** — a "Sound like the speaker" On/Off row under "Speak it in my ear", **"a mock-up first"** — Gil wrote that caveat into the option text itself.
- **timbre: A** — park part 2 (voice conversion); nothing to build, nothing to revert; the write-up already says this and needs no further action.

## Owner gate hit: the Settings row needs a mock-up before it's built

Per `docs/agents/pr-requirements.md` ("Tickets that change the look carry images... before they are built") and the playbook's owner gate ("Any look change: a mock-up on the ticket... unless the ticket already carries his approval, never do one on your own judgment"), and because Gil wrote "a mock-up first" into the chosen option's own text, I will **not** add the visible row in this PR. This repo's own precedent for exactly this situation is a dedicated `mockup/NNN-slug` branch/PR, screenshotted by the pipeline, reviewed before the real feature adds the wiring (`mockup/233-ear-translation` → PR #238; `mockup/246-translated-caption`). So:

- **PR #254's branch (`feature/247-voice-match`)** gets the full matching engine, wired into "Speak it in my ear", gated by a persisted on/off flag that **defaults off** (same default-off pattern as `EarCenter.onKey` today) and has **no visible row yet** — so this PR changes no pixel, needs no screenshots ("N/A, nothing visible changed," same wording the spike PR itself already used).
- A **new, separate PR** (`mockup/247-sound-like-the-speaker`), linked from #254, adds only the inert row (reusing `EarSettingsRows`' pill pattern verbatim) behind a demo flag, for Gil's look-approval. Once approved, a follow-up ticket wires the real row to the flag built here.

No Decisions-widget needed for this — it's a gate, not a choice, and the ticket allows making the conservative call myself and stating it.

**Other scoping calls I'm making myself (not asking, per "make the most reasonable call and note it"):**
- **Calibration data: Spanish only, for now.** The clicked option says "with our shipped calibration table" — the table we have, not a promise of new measurement. Every other target language gets no calibration entries, so `VoiceMatch.match` automatically falls back to today's single voice (already tested). Measuring more languages is its own spike-sized effort.
- **No on-device "measure a missing voice in Settings" step in this PR.** The write-up describes that as part of A's *full* shape, but the decision Gil actually clicked didn't ask for it, and it's a materially larger, riskier piece (rendering TTS to buffers at setup time, caching results) that deserves its own ticket rather than being folded in here unreviewed.

---

## Tests I will write first

**The issue's own break cases (process, not code):** both already checked during this planning pass — the Decisions comment's note is empty ("(no notes)"), so nothing contradicts a chosen option; PR #254's branch is unchanged since the decision apart from a routine `main` merge (`ea5fa0b`), confirmed by `git log`. Nothing to re-derive; stated here as satisfied.

**New adversarial unit tests, in `Packages/CaptionCore/Tests/CaptionCoreTests/`:**

1. `SpeakerVoiceTests.swift` (moved `VoiceMatchTests.swift` unchanged, 31 `@Test`s) — already covers: silence/noise/clipping/NaN/out-of-range audio, empty/broken input, laughter, pauses, chunked vs. whole, bounded pitch-frame memory, unknown speaker keeps the default, no voices or broken numbers, more speakers than voices reuses them, two similar speakers kept apart, catch-up on top of a matched rate, calibration-curve interpolation/inversion, non-Latin text (Hebrew/Arabic) falling back correctly. No new tests needed here — reused, not re-derived.
2. `EarTranslationTests.swift` — new cases for `EarPhrases.Phrase.speaker`: a line with `speaker == nil` (diarizer hasn't attributed it yet) yields a phrase with `speaker == nil`; a sound-label or face-to-face-laned line (excluded by `isSpoken`) never reaches `take(...)` at all, so it can't leak a stale speaker number.
3. New `SpeakerVoiceTrackerTests.swift`:
   - Concurrent feed (simulated audio queue) and read (simulated main-actor query) don't race or crash — mirrors `LiveDiarizer`'s lock.
   - A long synthetic session (many speaker turns, minutes of audio) keeps memory bounded — the tracker must evict/age out the same way `SpeakerProfile` already does, not grow per speaker forever.
   - A speaker who drops out and returns later in the same session keeps their accumulated profile (repeats), rather than being treated as a brand-new, unmatched speaker each time.
   - Switching the target language mid-session (stale state) rebuilds matches against the new language's calibration table and never applies a match computed for the old one.
   - A calibrated voice ID that `AVSpeechSynthesisVoice(identifier:)` can't resolve (OS removed/renamed it — a dependency failure) falls back to today's plain voice, never silently speaks with no voice and never crashes.
   - Toggling the on/off flag mid-conversation only changes the *next* spoken phrase, never interrupts one already playing or retroactively edits `spokenTranslations` (a person's mistake / UI timing case).
4. New `ShippedVoiceCalibrationTests.swift` — validates the literal Spanish table itself: every entry has a non-empty, unique `id`, and `rateCurve`/`pitchCurve` points are finite and strictly increasing in `input` (a bad hand-edit here would silently corrupt `CalibrationPoint.input(for:)`'s monotonic assumption without this check).
5. Existing `CaptionSessionControllerTests` / lifecycle tests must still pass unchanged (per `docs/agents/pr-requirements.md`'s rule on the live-captioning path) — run as-is, not modified, to prove the new feed doesn't disturb start/stop/restart.

**Explicitly untested by me:** `EarCenter.speakNext()`'s actual choice of `AVSpeechSynthesisVoice`/`pitchMultiplier`/`rate` at runtime, and the on/off `UserDefaults` flag's real behavior on device — `EarCenter` is deliberately thin, AVFoundation-heavy, `@MainActor` glue with no app-level test target (consistent with "keep the SwiftUI layer thin" in this repo's CLAUDE.md). I can only verify it compiles (`xcodebuild` app-build step) and reads correctly; whether it actually sounds different in someone's ear is unverified by this pass, same as the spike PR's own disclosure.

---

## Task List

1. Move `Packages/EarSpike/Sources/EarSpikeKit/SpeakerVoice.swift` into `Packages/CaptionCore/Sources/CaptionCore/SpeakerVoice.swift` unchanged, with a `// Moved from the #247 spike...` header (matching `VoiceCoverage.swift`'s convention).
2. Move `Packages/EarSpike/Tests/EarSpikeKitTests/VoiceMatchTests.swift` into `Packages/CaptionCore/Tests/CaptionCoreTests/SpeakerVoiceTests.swift` unchanged (keep `@Test`/Swift Testing style, per `EarVoiceCoverageTests.swift`'s precedent).
3. Add the shipped Spanish `[VoiceCalibration]` literal table (from `docs/perf/ear-translation/voice-match-mac.json`) plus `ShippedVoiceCalibrationTests.swift` validating its structural sanity.
4. Add `speaker: Int?` to `EarPhrases.Phrase` in `EarTranslation.swift`, populated from `CaptionLine.speaker` in `EarPhrases.take(from:now:)`; add the `EarTranslationTests.swift` cases for it.
5. Add `SpeakerVoiceTracker` (new file in `CaptionCore`, lock-protected like `LiveDiarizer`): `feed(_ samples: [Float], sampleRate:, segments:)` for pitch, `addLine(speaker:, text:, speechSeconds:, language:)` for text-based pace, `traits: [Int: SpeakerTraits]`. Add `SpeakerVoiceTrackerTests.swift` per the list above.
6. In `TranscriptionEngine.swift`: own a `SpeakerVoiceTracker`; feed it from `processBuffer` (line ~466-486, alongside `diarizer.feed`/`soundLabeler.feed`) using a lock-protected snapshot of the one-way path's speaker numbering (hoist `makeResultStream`'s local `SpeakerLabelSmoother` numbering to an instance property so `processBuffer` can read it); feed `addLine` from `makeResultStream`'s loop (line ~510-534) once a piece is final. Expose `speakerTraits: [Int: SpeakerTraits]` the same way `diagnostics` is already exposed (line ~578).
7. Thread `speakerTraits` up through `CaptionSessionController` the same way `diagnostics` already is, so the app layer can read it.
8. In `EarCenter.swift`: add a persisted, default-**off** `soundsLikeSpeakerOn` flag (same pattern as `onKey`); on each `speak(_:translation:)`, when the flag is on, compute `VoiceMatch.match(...)` from the current `speakerTraits` and the target language's shipped calibration (empty for non-Spanish, so it safely no-ops), look up the match for `phrase.speaker`, and set `utterance.voice`/`pitchMultiplier`/`rate(catchUp:)` in `speakNext()` instead of the single fixed `voice`; fall back to today's behavior whenever no match, no flag, or the resolved `AVSpeechSynthesisVoice(identifier:)` is nil.
9. Verify: `swift test --package-path Packages/CaptionCore` green, including every test from steps 2-5; confirm existing `CaptionSessionControllerTests`/lifecycle tests are unaffected; app-build (iOS Simulator) verify step green. State plainly in the PR that `EarCenter`'s runtime voice/pitch/rate selection is untested beyond compilation.
10. Update `CONTEXT.md` with the #247/#254 decision (wire: A, setting: B pending a mock-up, timbre: A parked).
11. Reply on PR #254 with the `<!-- marvin:decisions-addressed -->` marker: what shipped (the matching engine, default-off, no visible change), why the Settings row and any new-voice calibration measurement are deferred, and that screenshots stand as "N/A, nothing visible changed" for this PR.
12. Open `mockup/247-sound-like-the-speaker`: an inert "Sound like the speaker" row under "Speak it in my ear" reusing `EarSettingsRows`'s pill pattern, reachable via a debug launch argument/scene for the pipeline's own screenshot step, linked from PR #254, for Gil's look-approval before anything wires it live.