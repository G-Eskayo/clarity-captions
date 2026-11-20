# iPhone speech locale availability and caption language prioritization

## What this measures

The iPhone has the same speech recognition engines Apple provides on macOS:
- `SpeechTranscriber`: Apple's live caption engine
- `DictationTranscriber`: Apple's Siri dictation engine
- `SFSpeechRecognizer`: Apple's on-device speech recognition (older API)

Each engine has locales it **supports** (knows about) and **installed** (has downloaded language models for). Caption language choice depends on both: a supported locale with no installed model requires download before captions work. This document tracks what locales are available on real devices to guide prioritization (ticket #36).

## Measurement infrastructure

**On macOS**: `scripts/speech-locales/probe.swift` runs the four APIs and saves the result as JSON (see `docs/research/apple-speech-locales-macos-26.5.1.json` and similar).

**On iOS** (this PR): Developer panel button "Copy speech locales" in ContentView.swift's developer panel:
1. Gathers the same four lists + OS version from the live device
2. Wraps them in `SpeechLocaleReport` (a pure type, fully testable)
3. Serializes to the same JSON schema as the macOS probe
4. Copies to pasteboard for manual paste into docs/research/

**Schema** (matching `probe.swift`):
```json
{
  "date": "2026-11-14T12:00:00Z",
  "os": "iOS 18.2",
  "SpeechTranscriber.supportedLocales": ["en-US", "es-ES", ...],
  "SpeechTranscriber.installedLocales": ["en-US", ...],
  "DictationTranscriber.supportedLocales": ["en-US", "fr-FR", ...],
  "DictationTranscriber.installedLocales": [],
  "SFSpeechRecognizer.supportedLocales": [...]
}
```

## Known sizes

From Parakeet (Seal's bundled model for Hebrew, ticket #220):
- **Parakeet**: 498 MB, shared across all its languages (Hebrew, likely others in future)
- **Hebrew language pack**: 38.6 MB (when downloaded as a separate Apple speech model)

Apple's APIs expose **no per-locale asset size**. The only way to measure download cost is to attempt the download on a device with metered connectivity.

## Current locale counts

**macOS 26.5.1** (measured 2026-11-14):
- SpeechTranscriber supported: 98 locales
- SpeechTranscriber installed: 1 (en-US)
- DictationTranscriber supported: ~50 locales
- SFSpeechRecognizer supported: ~60 locales

(Full counts in `apple-speech-locales-macos-26.5.1.json`.)

## iPhone locales

**PENDING owner's on-device run of the "Copy speech locales" button**, then paste into `docs/research/apple-speech-locales-ios-<version>.json`.

Differences from macOS expected:
- Fewer locales on iPhone (smaller device, smaller app size budget)
- Different default installed set (may include more regional variants based on device language)

## Caption language prioritization — Tier A (launch), Tier B, Tier C

**Tier A (launch, #36 AC1)**: English (en-US), Spanish (es-ES starting here), French, German

**Tier B**: Additional European languages (Italian, Dutch, Portuguese), East Asian (Mandarin, Japanese, Korean)

**Tier C**: Other supported Apple languages (Cantonese, Thai, Vietnamese, Swedish, Polish, Turkish, …)

**Policy**: Tier A requires > 80% locale availability on both iOS and macOS (`SpeechTranscriber.supportedLocales`). Tier B ≥ 60%. Tier C ≥ 40%.

The policy is settled; **measurement of iPhone against it is pending** (owner's one run of the new button, ~2 minutes on device).

## References

- ADR 0007: Free and on-device (no cloud speech)
- ADR 0010: Platform-agnostic core
- Ticket #36: Speech locales measurement infrastructure
- Ticket #220: Bundled Hebrew caption engine
- `scripts/speech-locales/probe.swift`: macOS measurement
- `docs/research/apple-speech-locales-macos-26.5.1.json`: Sample macOS probe output
