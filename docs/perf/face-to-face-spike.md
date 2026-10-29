# Face to face: can Seal route each voice to one language engine? (#60 spike)

Measured 2026-10-29 on the Mac mini (Apple M4, 16 GB, macOS 26.5.1), release build, real-time pace.
Code: `Packages/CaptionCore/Tests/CaptionCoreTests/FaceToFaceSpikeTests.swift`
(`CAPTION_F2F_SPIKE=1 swift test -c release -Xswiftc -enable-testing --filter FaceToFaceSpike`).

The owner chose **voice first** on #60: the speaker sorter (Sortformer diarizer) tells the two people apart, each
person is matched to a language once, and from then on their speech goes only to that language's engine (Parakeet
for English, Apple's SpeechTranscriber for other languages, ADR 0025), so one engine works at a time.

## Audio

- **Conversation:** 8 alternating turns at a ticket counter, 36.8 s, 0.5 s between turns. Spanish by the macOS voice
  Paulina (es-MX), English by Samantha (en-US). Synthetic: two very different voices in a quiet "room", so the
  diarizer's job here is easier than at a real table.
- **Language check clips:** 20 real recorded Spanish sentences (FLEURS es_419 test, already on the Mini from #158),
  plus short and long lines by 3 English and 2 Spanish macOS voices (45 clips). There was no real recorded English
  on the Mini.

No speech was transcribed by anything but Seal's own engines.

## 1. How soon does the diarizer name the new speaker?

Fed live in 0.1 s chunks, polled after each chunk.

| | median | p95 | max |
|---|---:|---:|---:|
| Turn start → the right speaker covers 0.3 s into the turn | 0.71 s | 0.76 s | 0.76 s |
| Turn start → the right speaker holds 80% of the turn's first 1.5 s | 1.63 s | — | 1.76 s |

7 of 8 turns were named. The English voice's **first** turn was never named on its own in that run (its start sat
under the Spanish voice's segment); in the routed run (part 3) the same turn got its own speaker. 1 of 9 final
segments overlapped the other voice's turn by more than 0.3 s.

## 2. Can the engines tell the languages apart by how sure they are? No. By the words' language? Yes.

**Confidence does not separate the languages.** Parakeet Ultra transcribes Spanish nearly perfectly (it is
multilingual; #158 measured 2.8% WER on FLEURS Spanish), and Apple's Spanish engine writes English as English.

| Spoken | Parakeet confidence (median, min) | Apple es confidence (median, min) | Parakeet − Apple (min, max) |
|---|---|---|---|
| English (15) | 0.97, 0.73 | 0.82, 0.00 | +0.05, +0.87 |
| Spanish (30) | 0.99, 0.47 | 0.97, 0.45 | −0.12, +0.07 |

**The language of the words they write does.** Apple's NaturalLanguage recogniser, limited to the two languages,
on both engines' words together:

| Line length | clips | P(the language really spoken): min · 5th pct · median | on the wrong side |
|---|---:|---|---:|
| any | 45 | 0.33 · 0.68 · 1.00 | 1 |
| 2+ words | 40 | 0.33 · 1.00 · 1.00 | 1 |
| 4+ words | 38 | 0.33 · 1.00 · 1.00 | 1 |

- Every one-word line ("Hi.") scored 0.68 or less: too short to decide.
- The one wrong line is a synthetic voice (Mónica) that both engines garbled into nonsense.
- Every real FLEURS Spanish sentence scored 1.00.

So the match uses the language of the words, needs a few words, and must stay correctable.

## 3. Routed vs one-way caption lag

Lag = wall clock when a word first shows minus when it was said (`WordLagTracker`, volatile and final, ADR 0012).
Routed: the diarizer's latest speaker decides which engine hears the audio, a voice with no language yet goes to
both, and when the diarizer names a speaker whose engine wasn't listening, that engine first gets the turn so far
from a short buffer. In the spike the language locked once both engines had 4 words in the voice's first turn.

| | English (Parakeet) median · p95 | Spanish (Apple) median · p95 |
|---|---|---|
| One-way: one engine hears everything | 0.65 s · 1.26 s | 0.17 s · 0.18 s |
| Routed: each engine hears its own speaker | 0.55 s · 1.11 s | 0.54 s · 0.55 s |

- Turn start → the right engine has the turn's audio: **median 0.28 s, max 0.44 s** (6 switches).
- Language locked **3.2 s** into each voice's first turn (both voices), with both engines running until then.
- English is no slower routed. Spanish is about **0.37 s** slower, because each Spanish turn now starts on the
  switch. Both stay under the ~1 s a reader notices (ADR 0015).

## Verdict

Voice first is feasible on the Mac: the diarizer is fast enough to route by voice, and the first lines can be matched
in about 3 s. Not measured here, and still needed on an iPad: a real two-person table (room noise, similar voices,
talking over each other), battery and heat, and Apple's Translation (the Mac test has none).
