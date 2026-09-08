# 0001 — Transcription engine choice, and own-voice filtering strategy

## Status

Accepted (2026-09-08)

## Context

The app's one hard requirement is fully offline, real-time speech captioning on iPhone 17, for a
deaf user, by 2026-10-25. The user also asked for a second feature: filtering her own speech out
of the caption stream, originally framed as "accessing Siri voice recognition files."

## Decision

**Transcription engine: Apple's `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26), not
`SFSpeechRecognizer`.** Confirmed via research (2026-09-08): both the newer and older frameworks
can run fully on-device, but `SFSpeechRecognizer` caps a session at ~1 minute, which is unworkable
for continuous conversation. `SpeechAnalyzer` has no such cap, is built on `AsyncSequence` for a
concurrency-native Swift API, and benchmarks show it's meaningfully faster and comparably accurate
to `SFSpeechRecognizer`/Whisper alternatives. It requires downloading an on-device language asset
via the system (still zero network calls from the app itself, and no dependency on a live
service).

**Own-voice filtering: no OS-level API exists for this.** Confirmed via research (2026-09-08):
Apple does not expose a user's Siri/personal voiceprint to third-party apps under any public API.
"Reading Siri voice recognition files" is not possible on stock iOS. The only realistic path is
building speaker identification ourselves: a one-time in-app voice enrollment, followed by an
on-device speaker-embedding model run locally to classify each utterance as "primary user" or
"other" in real time.

**Because of that, own-voice filtering is being treated as a fast-follow candidate, not a locked
v1 requirement.** It's a real speaker-diarization subsystem — meaningfully more engineering risk
than the core transcription path — and the deadline (2026-10-25) is fixed and non-negotiable (it's
a birthday). Plan: prototype the enrollment + on-device speaker-embedding approach early (this
week), and only fold it into the v1 scope if the prototype proves solid well before the deadline.
The fallback if it doesn't make it in time is a v1 that captions everyone including the primary
user — which is still a real improvement over the status quo (no offline captioning at all) and
matches how comparable tools (Otter, Live Captions) already behave by default.

## Consequences

- Core v1 scope: on-device real-time captioning via `SpeechAnalyzer`, no own-voice filtering,
  fully offline. This is the must-ship path for 2026-10-25.
- Own-voice filtering gets its own throwaway prototype pass before it's allowed into the real
  task list, specifically to avoid discovering feasibility problems late in the schedule.
- Distribution is a personal install via the paid Apple Developer Program, not TestFlight or the
  App Store — avoids App Store review timeline/risk for an accessibility-adjacent app on a fixed
  deadline. Requires Gil to complete Apple Developer Program enrollment himself (not automatable).
