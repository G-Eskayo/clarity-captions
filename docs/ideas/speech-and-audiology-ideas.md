# Ideas from speech-language pathology and audiology

Status: **ideas, not decisions.** Nothing here is built. Each item says what it would take and
whether it fits the decisions already made. Not medical advice, and the app must never make health
claims (see `docs/app-store-compliance.md`).

## The question that started this (2026-10-05)

> If setup had the person say a few phonetically balanced sentences, what could that tell us?

**Short answer: much less than it seems, and it re-opens a settled decision.**

- ADR 0003 already designed exactly this (Harvard Sentences at setup). ADR 0008 then dropped
  enrollment because of latency, error asymmetry and the **hard requirement that the app behave
  identically for everyone with no per-user training** (CONTEXT.md, "Generalized, no per-user
  training"). Re-introducing a setup reading needs that requirement relaxed on purpose: "optional,
  skippable, never required" is the only version that could fit.
- **It cannot improve Apple's transcription of other people.** The speech framework offers no way
  to adapt its acoustic model from a user's voice sample. Phonetic coverage matters for training a
  recognizer; we do not train one.
- **For speaker labels it is only useful for naming known voices** (a voice fingerprint from
  roughly 10 to 30 seconds of ordinary speech, not a phonetically balanced script). Short
  utterances, noise and distance all hurt matching, which is why the earlier review rejected it.
- **For proximity**, a calibration moment ("say hello from where you usually sit") could set a
  loudness baseline per person, but any speech works for that, not a phonetic script.

## What does fit, and why (verified in the iOS 27 SDK where noted)

| Idea | Origin | Fits our decisions? | Notes |
|---|---|---|---|
| **Dim uncertain words** using the recognizer's per-word confidence | audiology: hardest sounds (s, f, th, sh) are also where recognizers err | Yes, it is "dim, don't dismiss" (ADR 0012) applied to words | `transcriptionConfidence` attribute exists in the SDK. Cheap. |
| **Custom vocabulary**: type the names of people and places she talks about | SLP: names and proper nouns are high-value and unpredictable | Yes, no voice enrollment, fully on-device | `AnalysisContext.contextualStrings` exists in the SDK. Setup step: "Who do you talk with most?" |
| **Sound labels** such as laughter, applause, a doorbell or a phone ringing, shown as non-speech captions | audiology: non-speech sound is lost context | Yes, on-device | `SoundAnalysis` (`SNClassifySoundRequest`) is in the SDK. Must not be marketed as a safety alert. |
| **Emphasis cues**: show louder or stretched words differently | SLP: prosody carries meaning that plain text drops | Probably | Needs the loudness timeline from the session-capture tool. |
| **"Say that again" replay**: a short in-memory rewind buffer to re-read or replay the last seconds | SLP/audiology: conversation repair | Needs the retention decision first | Keep it memory-only unless the design session says otherwise. |
| **Language and dialect choice** at setup (US, UK, Australian English and so on) | SLP: dialect affects recognition | Yes | Locale is already a parameter. |
| **Named speakers** for family ("Dad", "Gil") | the original enrollment idea | **Only if made optional** | Needs the "no per-user training" rule relaxed to "never required". Decide in the design session. |

## Open questions for the owner

1. Is an optional, skippable voice step acceptable, or does "no per-user training" mean none at all?
2. Which of the fitting ideas matters most to the first user?
3. "Phonetic alphabet" can mean the NATO spelling alphabet, the IPA, or a phonetically balanced
   passage (Harvard Sentences, the Rainbow Passage). Which did the owner mean?
