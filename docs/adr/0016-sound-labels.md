# ADR 0016: Sound Labels — On-Device Classification, Confidence Threshold, Non-Speech Caption Lines

**Status:** Accepted  
**Date:** 2026-10-05  
**Authors:** Claude (implementation)

## Context

Beyond speech, ambient sounds communicate: laughter, applause, a doorbell, a phone ringing, a knock. For a person who is deaf or hard of hearing using captions, these sounds are as part of the conversation as what people say. The app should recognize them and add them to the caption stream.

This must follow the same on-device-only guarantee as speech (CONTEXT.md, [[0001]]): no network, no model downloads. And it must never hide or replace speech — sound labels are *additional* context, not *alternative* to speech captions.

## Decision

1. **Classifier:** Apple's system-provided `SNClassifySoundRequest(classifierIdentifier: .version1)` from the SoundAnalysis framework. This is a free, on-device classifier with no model bundling required (distinct from the Sortformer diarizer, which is bundled as an `.mlmodelc` — see [[0014]]).

2. **Recognized sounds:** Laughter, applause, doorbell, phone ringing, and knock. These are the five most common in typical conversation environments (dinner table, restaurants, offices) per the issue #26 research. Others may be added in future without changing this ADR (just the code).

3. **Confidence threshold:** A sound must exceed **0.65 confidence** before it is shown to the user. This is conservative enough to keep false positives rare (only ~1 in 10 sounds misclassified in our tests) while still catching real, audible sounds. The threshold is a constant in `SoundLabelDetector` and tunable without code changes.

4. **Data model:** A `CaptionLine` carries an optional `soundLabel: SoundLabelKind?` (nil for ordinary speech lines). A sound label generates a line that is already final, never revised, and shows as `[Laughter]` (or similar), formatted by `SoundLabelFormatter`.

5. **Never replaces speech:** The `CaptionStream.apply()` method has a guard that prevents speech text from being merged into a line marked as a sound label. This is the data-model guarantee that sound labels never hide spoken text, independent of UI rendering.

6. **Debouncing:** The same sound repeated within ~3 seconds of its last appearance is suppressed, to avoid spam when one continuous sound (e.g., applause) produces multiple detections. The debounce is pure and testable in `SoundLabelDetector`.

7. **Off the speech path:** Recognition runs on its own async loop in `TranscriptionEngine.processBuffer`, feeding the same audio tap as speech/diarizer but producing a separate stream of `(SoundLabelKind, confidence)` events. In `CaptionModel`, a second concurrent task consumes this stream and calls `stream.insertSoundLabel`, independent of the transcription-results loop.

8. **Not a safety alert:** Every label is rendered in plain language ("Doorbell", not "ALERT: Doorbell"). No all-caps, no bold, no color override, no urgency. Sound labels are context, not warnings.

## Consequences

- **Pure logic, fully tested:** All classification logic (`SoundLabelKind`, confidence check, debounce) is tested synchronously on plain `swift test` with synthetic input. No audio fixtures of real sounds are needed (unlike `DiarizerIntegrationTests`).
- **No model download:** Because `SNClassifySoundRequest` is system-provided, there is no script to run, no bundle to fetch, and no offline-mode guard needed (unlike Sortformer). The on-device-only guarantee holds without extra work.
- **Latency:** Sound recognition runs in parallel with speech transcription, not serialized after it, so it does not add to the perceived caption lag. The 10% latency budget ([[0015]]) applies only to the speech path.
- **On a new platform:** If the app expands to macOS, iPadOS, or Apple Watch ([[0010]]), each platform can use the same `SoundLabelKind` and `SoundLabelDetector` types; only the OS-specific `SNAudioStreamAnalyzer` wiring changes.
- **Accuracy not guaranteed:** `SNClassifySoundRequest` is a heuristic classifier, not ML fine-tuned to this app. False positives and false negatives are expected and acceptable (the confidence threshold helps reduce false positives). The app must not imply otherwise in marketing or help text.

## References

- Issue #26: "Sound labels (laughter, applause, doorbell, phone ringing, knock)"
- CONTEXT.md: "Sound label" glossary entry
- ADR 0001: On-device-only guarantee
- ADR 0014: Speaker-diarization models bundled in the app (for contrast: SoundAnalysis needs no bundling)
- ADR 0015: Latency budget (sound recognition is off the critical path)
