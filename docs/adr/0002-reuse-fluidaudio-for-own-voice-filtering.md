# 0002 — Reuse FluidAudio for own-voice filtering instead of building embeddings from scratch

## Status

Accepted (2026-09-08). Partially supersedes [[0001]]'s framing of own-voice filtering.

## Context

[[0001]] treated own-voice filtering as requiring a from-scratch on-device speaker-embedding
model, and demoted it to a fast-follow rather than a v1 requirement mainly because of that
assumed cost. A resource survey (`docs/research-existing-resources.md`) found this assumption was
wrong: mature, permissively-licensed, actively-maintained on-device speaker-embedding/diarization
libraries already exist for Swift/iOS, and at least one (FluidAudio) has already been demonstrated
paired with our exact transcription engine (`SpeechAnalyzer`/`SpeechTranscriber`) in a working
reference app (`swift-scribe`).

## Decision

Use **[FluidAudio](https://github.com/FluidInference/FluidAudio)** (Apache-2.0, CoreML-native,
Neural-Engine-optimized, iOS-supported) to extract speaker embeddings from live audio, rather than
building or training an embedding model ourselves.

FluidAudio does not ship a turnkey "enroll one person, verify against them" API — only raw
embeddings plus clustering. The app-specific layer we still build:
1. One-time enrollment: record the primary user speaking, extract her embedding via FluidAudio,
   store it locally on-device.
2. Per-utterance classification: extract each live utterance's embedding, compare via cosine
   similarity against the stored enrollment embedding, threshold to classify "primary user" vs.
   "other speaker."
3. Tune the similarity threshold against real recordings.

This is meaningfully smaller than what [[0001]] assumed. Own-voice filtering may be realistic for
the v1 (2026-10-25) scope now, not just a fast-follow — but [[0001]]'s planned early prototype
still stands: the threshold-tuning/accuracy question is unverified and untested, it's just a much
smaller unknown now than "does a viable on-device embedding model exist at all."

## Consequences

- New dependency: FluidAudio (Apache-2.0 — permissive, no redistribution restrictions that would
  block personal use or the App Store later).
- Reference material for integration: `swift-scribe` (MIT, study/adapt, not a live dependency —
  its own maintainers call it AI-generated and unmaintained) and
  `ios26-speechanalyzer-live-mic` (MIT, small and current, documents the `AVAudioConverter`
  buffer-format gotcha for `SpeechTranscriber`).
- The early prototype from [[0001]] is still required before locking own-voice filtering into the
  real v1 task list — this ADR reduces the size of the unknown, it doesn't eliminate the need to
  validate it.
