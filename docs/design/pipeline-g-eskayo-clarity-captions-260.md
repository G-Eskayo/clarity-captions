Confirmed: PR #254's only comment is the decisions comment itself, at exactly the timestamp the ticket cites, with no later commits or comments — nothing to reconcile.

## North-star fit

Reuses the exact "move a spike into the app" pattern already in this codebase: `Packages/CaptionCore/Sources/CaptionCore/VoiceCoverage.swift` (comment: "Moved from the #233 spike (Packages/EarSpike, PR #237) so the app can use it") — `SpeakerVoice.swift`'s pure types (`PitchTracker`, `SyllableRate`, `TextSyllables`, `SpeakerProfile`, `CalibrationPoint`, `VoiceCalibration`, `MatchedVoice`, `VoiceMatch`) get the same treatment: moved into CaptionCore essentially verbatim, no redesign. Per-speaker attribution of raw audio reuses `SpeakerAligner.speaker(start:end:segments:)`'s overlap style (`Packages/CaptionCore/Sources/CaptionCore/SpeakerAligner.swift:20`) instead of inventing a new matching rule, and "only change voice on a settled label" reuses `SpeakerLabelSmoother`'s existing slot/display-number semantics (`Packages/CaptionCore/Sources/CaptionCore/SpeakerLabelSmoother.swift`) rather than building a second stability mechanism.

Simplest sufficient approach: no new SwiftUI, no new Package.swift resource target (the project notes forbid touching package dependencies), no new AVFoundation surface inside CaptionCore. The shipped calibration table ships as a small Swift literal (`VoiceCalibrationTable.swift`), not a bundled resource — "a few hundred bytes per voice" per the spike's own write-up. `EarCenter` (`Apps/Spike/Sources/EarCenter.swift`) stays thin: it only calls the already-public, already-pure `VoiceMatch.match` and sets three AVFoundation properties; all new decision logic (which raw diarizer slot gets which buffer, when a profile is "ready") lives in CaptionCore as small pure types with unit tests, per this repo's rule that "the unit tests are the only automated check of behavior."

Tokens spent: porting ~450 lines of already-written, already-tested spike logic, plus genuinely new routing logic (`SpeakerVoiceTracker`, ~60–100 lines) and its tests. Tokens saved: reusing `VoiceMatch.match`'s existing nil/empty-calibration fallback paths instead of writing new gating code, and avoiding a Package.swift/XcodeGen resource-bundling detour.

Phone-OS direction: a one-way ear-translation that now sounds like the actual person speaking is a step toward Jarvis-grade presence, not toward passivity — it's pure backend quality, nothing for the user to operate.

Leaves the user more capable: translated speech in her ear becomes attributable by ear (not just by reading), closer to how a hearing person follows a room — without adding a single new control to learn (none shipped yet; see below).

**One north-star-driven design call, stated plainly rather than guessed:** Decision *setting* (B) explicitly says "a mock-up first" for the new "Sound like the speaker" row, and this repo's owner gate says a look change is never built on the executor's own judgment without an approved mock-up on the ticket — which #260 doesn't carry (the decision only fixes *behavior and placement*, not pixels). Decision *wire* (A) was chosen over "always on" (A for *setting*) precisely so a toggle would exist — so unconditionally turning matched-voice on everywhere the moment "Speak it in my ear" is on would contradict the owner's own choice on *setting*, not honor it. Resolution: wire the whole feature end-to-end, but gate it behind a new `UserDefaults`-backed flag (mirrors `EarCenter.onKey`'s existing pattern) that defaults to **off** and has no UI yet. This is "dark launch," not "half done" — it satisfies *wire* (A) fully and defers only the pixels *setting* (B) itself asked to be deferred. The mock-up becomes its own task below, attached to the PR for approval; the actual toggle row becomes a small, low-risk follow-up once approved.

## Tests to write first

All in `Packages/CaptionCore/Tests/CaptionCoreTests/`, run via `swift test --package-path Packages/CaptionCore`.

1. **`SpeakerVoiceTests.swift`** — ported from `origin/feature/247-voice-match:Packages/EarSpike/Tests/EarSpikeKitTests/VoiceMatchTests.swift` (31 cases), adapted to live in `CaptionCoreTests`:
   - `PitchTracker`: tones at 8–48 kHz, silence, noise, clipping, NaN and out-of-range samples.
   - `SyllableRate`/`TextSyllables`: pauses, steady hum, no-vowel scripts (Hebrew/Arabic) returning nil.
   - `SpeakerProfile`: fed in small chunks (as the app's audio arrives), a laugh, bounded memory (`maximumPitchFrames`, `rememberedSpeechSeconds` caps hold under a very long session — **huge input**).
   - `VoiceMatch.match`: no voices (empty calibration table — **a dependency with nothing to give**), broken numbers (NaN/∞ traits — **malformed input**), more speakers than voices, two very similar speakers (minimum-semitones-apart clash resolution), catch-up rate layered on top.

2. **`SpeakerVoiceTrackerTests.swift`** (new routing type, CaptionCore):
   - Empty `segments` at session start → `feed` is a no-op, `traits(forSlot:)` is nil, no crash (**a dependency — the diarizer — not ready yet**).
   - A buffer whose time window isn't covered by any segment (diarizer lag) → sample dropped, no misattribution (**stale state**).
   - Audio for two speakers arriving in rapid alternating buffers → each profile stays isolated, no cross-contamination of pitch/pace (**repeats and wrong order**).
   - A diarizer that reports far more distinct raw slot indices than Sortformer's stated 2–4-speaker ceiling (CONTEXT.md) in one session → the tracker's profile map stays capped, not unbounded (**a misbehaving dependency / adversarial input, memory bound**).
   - `addLine` fed an empty string, a string with no countable syllables, or non-positive `speechSeconds` → ignored, no crash (**bad/empty/malformed input**).
   - The same buffer fed twice (a caller bug) → no crash, no NaN/∞ in the resulting traits (**a person's/caller's mistake**).

3. **`SpeakerLabelSmootherTests.swift`** (extend existing file):
   - New `currentSlot` accessor after `label()` matches the raw slot actually chosen, including through an existing "tentative hold" scenario in that file — confirms a voice never switches on an unsettled flicker.
   - `currentSlot` is nil whenever `label()` itself returns nil.

4. **`EarVoiceMatchWiringTests.swift`** (new, using the existing fake-engine/replay pattern seen in `CaptionSessionControllerTests.swift` / `SpeakerModelComparisonTests.swift`):
   - A `CaptionUpdate` with `speaker == nil` always has `speakerTraits == nil` (never leaks a guess for an unattributed line).
   - Face-to-face pieces (`makeFaceToFaceStream`) never populate `speakerTraits` — explicit scope boundary (ear translation is one-way only, per CONTEXT.md).
   - A synthetic two-speaker replay ends with two distinct, non-nil `SpeakerTraits`, each nearer its own synthetic pitch than the other's.

5. **`VoiceCalibrationTableTests.swift`** (new) — guards the hand-transcribed shipped table against a transcription mistake: every entry has a non-empty voice id, and non-empty, usable rate/pitch curves (**a person's mistake**, the realistic risk in a hand-copied data table).

**Explicitly untested, stated plainly:** `EarCenter.swift`'s three AVFoundation property assignments (`utterance.voice`, `.pitchMultiplier`, `.rate`) and the dark-launch flag's default-off behavior — `Apps/Spike` carries no XCTest target; this is exactly as untested today as the rest of `EarCenter`. Covered indirectly by the CaptionCore tests above, by the app-build (xcodebuild) verify step, and by the spike's own still-open V1–V3 steps on a real phone (AirPods A/B, two-speaker turn-taking, a downloaded premium/enhanced voice) — none of which this executor can run.

**No N/A gaps left silent:** "wrong permissions" and "wrong machine" don't apply — this adds no new permission surface (mic/headphone handling is already covered by `EarRoute`/`MicSessionSetup`) and no new target.

## Decisions

None needed — all three options were already chosen by the owner on PR #254 and the PR is unchanged since. The one thing a fresh model would be tempted to ask about (how to sequence *wire*=A against *setting*=B's "mock-up first") is resolved above as a design call, not a question, because the owner gate already dictates the answer (never build the look change without an approved mock-up) — asking would just restate a rule already given.

## Task List

1. Port `SpeakerVoice.swift` (pure types) from `origin/feature/247-voice-match:Packages/EarSpike/Sources/EarSpikeKit/SpeakerVoice.swift` into `Packages/CaptionCore/Sources/CaptionCore/SpeakerVoice.swift`, mirroring `VoiceCoverage.swift`'s "moved from the spike" header comment. Port its 31 tests into `SpeakerVoiceTests.swift`.
2. Add `currentSlot` to `SpeakerLabelSmoother` (`SpeakerLabelSmoother.swift`) and its tests.
3. Add `SpeakerVoiceTracker` (new file, CaptionCore): owns `[Int: SpeakerProfile]` keyed by raw diarizer slot, with a capped slot count; `feed(samples:sampleRate:at:segments:)` attributes a buffer to the dominant covering segment (reusing `SpeakerAligner`'s overlap style); `addLine(...)` forwards to the right slot's profile; `traits(forSlot:)` reads it back. Write `SpeakerVoiceTrackerTests.swift` first.
4. Wire `TranscriptionEngine.swift`: own one `SpeakerVoiceTracker`; feed it inside `processBuffer` (next to the existing `diarizer.feed(samples)` call, line ~473) and inside `makeResultStream` (next to `labels.label(...)`, line ~519) for finished pieces only; add `speakerTraits: SpeakerTraits?` to `CaptionUpdate`, populated only in `makeResultStream`, left nil in `makeFaceToFaceStream`. `EarVoiceMatchWiringTests.swift` covers this.
5. Extend `ear-spike voice-match` (`Packages/EarSpike/Sources/ear-spike/main.swift`) to also serialize the measured `[VoiceCalibration]` to a JSON file; run it on this Mac for the Spanish voices already measured in the spike; commit the raw output as `docs/perf/ear-translation/voice-calibration-es.json` (evidence).
6. Hand-transcribe that output into `Packages/CaptionCore/Sources/CaptionCore/VoiceCalibrationTable.swift` (`VoiceCalibrationTable.calibrations(for:)`, returning `[]` for any language not yet measured — stated honestly as Spanish-only for now). Write `VoiceCalibrationTableTests.swift` first.
7. Wire `EarCenter.swift`: add the dark-launch `UserDefaults` flag (default off, mirroring `onKey`); cache `[Int: SpeakerTraits]` as `CaptionUpdate`s arrive; in `speakNext()`, when the flag is on and a translation target is set, call `VoiceMatch.match` for the phrase's speaker and apply the result's `voiceID`/`pitchMultiplier`/`rate(catchUp:)` in place of today's single fixed voice and flat rate; otherwise unchanged. No new SwiftUI.
8. Run `swift test --package-path Packages/CaptionCore` (full suite) and the app-build verify step; record pass counts.
9. Build the "Sound like the speaker" mock-up (new `docs/design/mocks/round5/` following `round3`'s `build.mjs`/README pattern) showing the on/off row under "Speak it in my ear," matching `EarSettingsRows`'s existing two-pill visual language. Attach the rendered PNG(s) to the PR for owner approval. **Do not build the real SwiftUI row** — stop at the mock-up, per the owner gate, and say so plainly in the PR.
10. Reply on PR #254 with the `<!-- marvin:decisions-addressed -->` marker: what was carried out for each of the three decisions (*wire*=A built and dark-launched behind a flag; *setting*=B's row deferred to an attached mock-up pending approval, with the reasoning above; *timbre*=A parked, no code change), link to the new PR, and state the screenshot situation plainly ("N/A for this PR — no look change; the mock-up for the follow-up toggle is attached separately for approval").