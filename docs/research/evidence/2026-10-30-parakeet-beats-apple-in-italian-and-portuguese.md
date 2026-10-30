# Parakeet Ultra beats Apple in Italian and Portuguese too

- **Source:** our own measurement, [docs/perf/language-accuracy-comparison.md](../../perf/language-accuracy-comparison.md)
  (#234; method in [language-accuracy-design.md](../../perf/language-accuracy-design.md), "#234"). FLEURS test splits at
  dataset commit `70bb2e8`, every clip: Italian `it_it` 865 clips (3.5 h, 346 sentences), Portuguese `pt_br` 919 clips
  (3.2 h, 349 sentences); #158's scorer with the same rules in Italian and Portuguese, accents kept; 95% CIs from a
  bootstrap over sentences; M4 Mac mini, macOS 26.5.1, one run per clip, 2026-10-30. Which languages to test: the
  overlap of Parakeet v3's 25 European languages (E14) and Apple's `SpeechTranscriber.supportedLocales` on the M4
  (E27), less the ones #145 and #158 already measured.
- **What we took:** Parakeet Ultra via FluidAudio (the published Core ML build #158 used) made the fewest word errors
  in both: **Italian 2.2% (1.8–2.5%) vs Apple 3.6% (3.1–4.1%); Portuguese 3.9% (3.3–4.5%) vs Apple 5.3%
  (4.7–6.0%)**, about 39% and 26% fewer errors, with intervals that don't overlap. Apple's two locales gave identical
  text on every clip in both languages (it-IT and it-CH; pt-BR and pt-PT), so each language is one Apple model, as
  Spanish was. With Spanish, French and German (E19), Parakeet now wins **every language both engines caption**.
  Parakeet's other 19 languages have no Apple engine to compare against.
- **Confidence:** Ours. Strong for the ranking (non-overlapping intervals); read speech, not conversation, so real-use
  WER will be higher for every engine (#145); Mac, not iPhone; FLEURS Portuguese is Brazilian, so European Portuguese
  is inferred, not measured. The ONNX (Android) builds weren't run for these two.
- **Drives:** #234: `CaptionEngineRouting` sends Italian and Portuguese captions to Parakeet (with Spanish, French and
  German from #158); Apple keeps Japanese, Korean, Chinese and Cantonese. ADR 0029 decision 2's Parakeet group.
- **Public use:** Careful ("on a public set of read sentences, in our test, Parakeet made fewer word errors than Apple's
  built-in engine in every language both offer: Spanish, French, German, Italian and Portuguese").
