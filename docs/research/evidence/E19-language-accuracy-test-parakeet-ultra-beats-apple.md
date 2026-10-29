# E19. Language accuracy test: Parakeet Ultra beats Apple in Spanish, French and German

- **Source:** our own measurement, [docs/perf/language-accuracy-comparison.md](../perf/language-accuracy-comparison.md)
  (#158; [design](../perf/language-accuracy-design.md)). FLEURS test splits, every clip: Spanish 908 (3.1 h), French
  676 (2.0 h), German 862 (3.2 h); per-language normalizer that keeps accents; 95% CIs from a bootstrap over sentences;
  M4 Mac mini, macOS 26.5.1, one run per clip.
- **What we took:** Parakeet Ultra via FluidAudio (the 1.1 English engine, which detects the language itself) made
  the fewest word errors in all three languages: **Spanish 2.8% (2.4–3.3%) vs Apple 4.0% (3.4–4.5%); French 4.5%
  (3.9–5.1%) vs Apple 7.5% (6.7–8.3%); German 4.4% (3.8–5.0%) vs Apple 7.2% (6.5–7.9%)**: roughly 30 to 40% fewer
  errors, with intervals that don't overlap. Our figures sit close to the Ultra card's (2.72, 4.32, 3.61; E14,
  different normalizer). Apple's es-MX, es-US and es-ES gave identical text on all 908 clips, so its Spanish is one
  model. Apple's de-DE model put a stray "you" at the start of 76 of 862 German clips; without it Apple would be 6.8%,
  still well behind. On the Android path (sherpa-onnx, CPU), Parakeet v3 int8 scored 3.9% / 7.0% / 6.6% and a community
  Ultra int8 export 3.2% / 6.2% / 5.3%: the Ultra weights in ONNX beat Apple in every language, and in Spanish
  match Ultra on Core ML, but lose 1.0 to 1.7 points in French and German. Speed: Ultra on Core ML 98–114x real time,
  Apple 91–104x, sherpa-onnx 14–20x on CPU (the Mac was heavily loaded; indicative only).
- **Confidence:** Ours. Strong for the ranking (non-overlapping intervals in all three languages); read speech, not
  conversation, so real-use WER will be higher for every engine (#145); Mac, not iPhone; the Ultra ONNX result is
  one unofficial export.
- **Drives:** #158's recommendation, **Parakeet** for Spanish, French and German in 1.2; retires the "Ultra is
  English-tuned" risk row in the engine-switch design; under ADR 0026 the same weights are the Android candidate; ADR 0029's best engine per language, Parakeet for Spanish, French and German (#200).
- **Public use:** Careful ("on a public set of read sentences, in our test, Parakeet made about a third fewer word
  errors than Apple's built-in engine in Spanish, French and German").
