# E22. Apple's Translation framework in every language it supports: FLORES-200 written text

- **Source:** our own measurement, [docs/perf/translation-comparison.md](../perf/translation-comparison.md), section
  "All languages Apple supports" (#159 "[E] Translation comparison test"); generated table in
  [docs/perf/translation-languages-results.md](../perf/translation-languages-results.md). All 19 English→X pairs that
  `LanguageAvailability` reported *installed* on the M4 Mac mini (macOS 26.5.1) after Gil installed every Translation
  language, each run on FLORES-200 devtest (1,012 sentences, English source). chrF with 95% bootstrap CIs over
  articles, COMET (wmt22-comet-da), ms per line on 760 EdAcc caption lines. Spanish, French and German reused from E21.
- **What we took:** COMET is 0.86 to 0.92 in 18 of 19 languages (Indonesian 0.920 highest), the range where Apple
  beat every other engine in E21. **Hindi is the weak one** (COMET 0.807). chrF ranges from 73.8 (Indonesian) to 32.6
  (Chinese, Traditional); Japanese, Chinese and Korean chrF runs low because of the metric (no spaces, character
  n-grams), not the translation, as COMET shows (Japanese 0.912). Asked for Simplified Chinese, Apple returned mostly
  Traditional characters in 2.9% of FLORES sentences and 2.0% of caption lines; never the reverse. Time per caption
  line is 51 to 59 ms median in every new language. Installed assets per pair, on disk: 154 to 291 MB, held by the
  system; languages in one family share most of it.
- **Confidence:** Ours. Written text only (Wikipedia-style prose), not conversation or caption-style input, and only
  Apple was run in these 16 languages, so there is no engine comparison for them. chrF isn't comparable across
  languages; COMET is closer to comparable but still varies by language. Mac, not iPhone.
- **Drives:** which languages 1.3 can offer for translation, which need a check first (Hindi), and whether the app
  must force Simplified script when Simplified Chinese is chosen.
- **Public use:** Careful ("in our test on a public written-text benchmark, Apple's on-device translation scored
  well in most of the languages it supports"). Don't publish per-language chrF without saying it isn't comparable
  across languages.
