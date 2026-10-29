# E28. Face to face: routing each voice to one language engine (#60 spike)

- **Source:** our own measurement, [docs/perf/face-to-face-spike.md](../perf/face-to-face-spike.md) (Mac mini M4,
  2026-10-29). Synthetic two-voice conversation (Spanish and English macOS voices) and 20 real FLEURS Spanish clips.
- **What we took:** the diarizer names a new speaker about 0.7 s into their turn (max 0.76 s), so voice-first routing
  works; routed English captions are no slower than one-way (median 0.55 s vs 0.65 s) and Spanish about 0.37 s slower
  (0.54 s vs 0.17 s). Engine confidence does **not** tell the languages apart (Parakeet Ultra writes Spanish almost
  perfectly); the language of the words they write does (4+ words: 37 of 38 lines right at P ≥ 0.99).
- **Confidence:** Ours, Moderate: synthetic voices in a quiet room, Mac not iPad.
- **Drives:** #60's speaker-to-language match by the words' language (lock at P ≥ 0.95 over 4+ words), with a
  correction when later lines say otherwise.
- **Public use:** Careful ("measured on a Mac with synthetic voices").
