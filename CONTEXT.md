# Clarity Captions — Context Glossary

Domain terms only. No implementation details beyond naming the frameworks involved — see
`docs/adr/` for decisions and rationale.

## Core concept

- **Caption stream**: the live, scrolling transcript shown on screen as people speak nearby. The
  app's entire reason to exist.
- **On-device only**: the whole captioning path — audio capture, transcription, and (if built)
  own-voice filtering — runs locally on the phone. No network call anywhere in that path, ever.
  This is a hard requirement, not a preference: the reference app (Otter) requires a live service
  connection, and that's exactly the failure mode this app exists to avoid.
- **Own-voice filtering**: showing only *other* speakers' words in the caption stream, suppressing
  the primary user's own speech. Requires the user to have done a one-time in-app **voice
  enrollment** first (see below) — there is no OS-level API that exposes an existing voice profile
  to third-party apps (confirmed 2026-09-08, see [[0001]]).
- **Voice enrollment**: a one-time setup step where the primary user records themselves speaking
  so the app can build an on-device speaker profile to distinguish their voice from other
  speakers'. Only needed if own-voice filtering ships.
- **Speaker embedding**: a numeric vector representation of a short stretch of speech, positioned
  so that embeddings from the same speaker sit close together (by cosine similarity) and
  embeddings from different speakers sit farther apart. What own-voice filtering is actually built
  on: compare a live utterance's embedding to the stored enrollment embedding, threshold on
  similarity — see [[0002]].

## Transcription engine

- **SpeechAnalyzer / SpeechTranscriber**: Apple's iOS 26 on-device speech-to-text framework,
  successor to the older `SFSpeechRecognizer`. Runs the whole transcription pipeline locally, no
  network call, no 1-minute session cap (the old API's dealbreaker for real conversations). The
  chosen transcription engine — see [[0001]].

## Own-voice filtering engine

- **FluidAudio**: the Apache-2.0, CoreML-native, Neural-Engine-optimized Swift library chosen to
  extract speaker embeddings for own-voice filtering, rather than building an embedding model from
  scratch — see [[0002]]. Provides embeddings/diarization primitives; the enroll-and-threshold
  logic on top is this app's own code.

## People

- **Primary user**: Gil's mother — deaf, the person this app is built for and will use it daily.
  Already owns an iPhone 17.
