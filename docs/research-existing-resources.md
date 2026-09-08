# Research: existing resources we can build on (2026-09-08)

Scope: what's already out there — open source or reference code — for (1) real-time on-device
iOS captioning and (2) on-device speaker identification, so we don't rebuild solved problems.
Practical/implementation question, so source ladder used: official docs > GitHub
repos (verified directly via `gh api`, not just search summaries) > general web.

## 1. Real-time captioning with SpeechAnalyzer — reference implementations exist

- **[simplememofast/ios26-speechanalyzer-live-mic](https://github.com/simplememofast/ios26-speechanalyzer-live-mic)** —
  MIT. Minimal but working live-mic → `SpeechTranscriber` sample, actively updated (pushed same
  day as this research). Directly documents the sharp edges: audio buffers must go through
  `AVAudioConverter` first or transcription silently returns nothing, and how to handle
  volatile-vs-final result reporting.
- **[edmistond/SwiftCaptionTesting](https://github.com/edmistond/SwiftCaptionTesting)** — **no
  license file (all rights reserved by default)**. Useful to *read* for ideas, not to copy code
  from without asking the author.
- **[FluidInference/swift-scribe](https://github.com/FluidInference/swift-scribe)** — MIT, 315
  stars, active (pushed July 2026). A full example app combining `SpeechTranscriber` *with*
  speaker diarization (see below) and on-device summarization. Maintainers explicitly say it's
  AI-generated and not actively supported ("we do not actively maintain this repo") — treat as a
  reference to study/adapt from, not a dependency to pull in live.

**Finding**: Apple's `SpeechAnalyzer`/`SpeechTranscriber` (already chosen in ADR 0001) has real,
working, MIT-licensed reference code showing exactly how to wire it to a live microphone,
including the non-obvious gotchas.
**Confidence**: Established (multiple independent repos + Apple's own forum thread converge on
the same integration pattern and the same buffer-conversion gotcha).

## 2. On-device speaker diarization/identification — this is a solved problem, not a from-scratch build

ADR 0001 assumed own-voice filtering would need a speaker-embedding model built from zero. That
assumption doesn't hold up:

- **[FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)** — **Apache-2.0**,
  2,743 stars, pushed same day as this research (very active), 403 forks, CI running model-
  download and benchmark-regression checks. Swift-native, CoreML-only (runs on Apple's Neural
  Engine specifically, not just CPU/GPU), supports iOS and macOS. Ships speaker-diarization and
  speaker-embedding extraction directly — confirmed via its own docs: "Generate speaker embeddings
  for voice comparison and clustering, you can use this for speaker identification." It does
  **not** ship a turnkey "enroll one person, verify against them" API — you get raw embeddings and
  write your own comparison logic (cosine similarity + a threshold is the standard approach for
  this). That remaining piece is a thin layer, not a research project.
- **[argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)** — **MIT**, 6,356
  stars, pushed August 2026 (very active). Monorepo containing `WhisperKit` (on-device Whisper
  ASR) *and* `SpeakerKit` (on-device diarization built on Pyannote v4 models, ~10MB, benchmarked
  at ~1 second to diarize 4 minutes of audio on an iPhone). Same shape as FluidAudio: diarization/
  embeddings are there, "is this specific enrolled person" is a layer you add.
- **[soniqo/speech-swift](https://github.com/soniqo/speech-swift)** — Apache-2.0, 1,170 stars,
  actively pushed (Sep 2026). MLX+CoreML based, also covers ASR/diarization/VAD. A credible third
  option, less specifically iOS-Neural-Engine-optimized than FluidAudio in its own framing (leans
  MLX/Apple Silicon broadly) — noted but not chosen, see below.
- **Confirmed real-world pairing**: `swift-scribe` (above) already combines Apple's
  `SpeechTranscriber` *with FluidAudio* for diarization in one working app — i.e. the exact
  combination this project needs has already been demonstrated to work together, not just two
  libraries that theoretically could be combined.

**Finding**: A mature, permissively-licensed (Apache-2.0), actively-maintained, Neural-Engine-
optimized on-device speaker-embedding library (FluidAudio) already exists and has already been
paired with our chosen transcription engine in a working reference app. The actual remaining
build for own-voice filtering is: (1) a one-time enrollment recording, (2) store its embedding,
(3) cosine-similarity-compare each live utterance's embedding against it, (4) threshold to
classify "primary user" vs. "other." That's an integration task, not a modeling research project.
**Confidence**: Established for "the embedding/diarization engine exists and works on-device on
iPhone" (multiple independent, active, permissively-licensed repos, one with a confirmed working
integration alongside our exact transcription engine). Speculative/unverified for "the specific
enroll-and-threshold approach will hit acceptable accuracy for this use case" — that has not been
tested and should still be the subject of ADR 0001's planned early prototype, just with a much
smaller unknown (tuning a similarity threshold) instead of a much bigger one (building an
embedding model).

## 3. Comparable deaf/HoH-focused captioning apps

- Turned up mostly closed/commercial apps (Ava, Live Transcribe, Live Transcribe+, Capsion,
  Hearo) — none open source, so nothing directly reusable there, though worth a look for UX
  patterns (font size, speaker-turn indication, scroll behavior) during the design/grill pass.
- One open-source mention, **Listenr** (an iOS transcription app aimed at the hearing-impaired) —
  **could not verify it via GitHub's API** (the repo path from search results 404'd; owner name
  was reported inconsistently across sources). Flagging as a single unverified mention, not a
  finding to act on.
**Confidence**: Established that no notable open-source *app* (as opposed to library) exists to
adopt wholesale in this space — everything comparable is closed/commercial. Unknown re: Listenr
specifically (couldn't verify it exists as described).

## What this changes

- **Adopt directly**: `FluidAudio` (Apache-2.0) as the speaker-embedding/diarization engine for
  own-voice filtering, pairing it with `SpeechAnalyzer`/`SpeechTranscriber` the same way
  `swift-scribe` already has.
- **Study, don't copy**: `swift-scribe` and `ios26-speechanalyzer-live-mic` for integration
  patterns and the buffer-conversion gotcha; skip `SwiftCaptionTesting` as a code source (no
  license) but fine to read for ideas.
- **Genuine build-from-scratch gap, now much smaller**: the enrollment UX, the cosine-similarity
  threshold tuning, and the caption UI itself. This meaningfully de-risks ADR 0001's "own-voice
  filtering as fast-follow" framing — it may be realistic to attempt for v1 now rather than
  deferring it, pending the same early prototype ADR 0001 already called for.
