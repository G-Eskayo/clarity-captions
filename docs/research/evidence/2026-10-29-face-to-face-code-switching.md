# Face to face: growing confidence and the matching numbers, on recorded code-switching (#208)

- **Source:** our own measurement, [docs/perf/face-to-face-code-switching.md](../perf/face-to-face-code-switching.md)
  (Mac mini M4, 2026-10-29), on the [Bangor Miami corpus](https://bangortalk.org.uk/speakers.php?c=miami) (GPL v3):
  56 recorded Spanish-English conversations, about 25 hours of speech, with human transcripts tagged by language per
  word. The transcripts went through the real matcher and Apple's NaturalLanguage; no audio was transcribed.
- **What we took:** #199's "2 sure lines in a row move a voice" put 9.35% of lines on the wrong half and made 397 wrong
  moves. A confidence that grows with each confirming line (cap 12) put 3.03% there, with 27 wrong moves, and still
  followed a really swapped voice in about 40 s. Locking at 99% beat 95% (fewer wrong moves, no slower).
- **Confidence:** Ours, Moderate: real code-switched speech, but human transcripts (no engine errors), a perfect
  diarizer outside the two scenarios that break it on purpose, and mostly English-first speakers.
- **Drives:** `LanguageMatchPolicy` defaults: lock at 4+ words and 99%; correct by confidence, cap 12, moved at −2.
- **Public use:** Careful ("tested on recorded bilingual conversations, transcripts only"). Don't quote corpus text.
