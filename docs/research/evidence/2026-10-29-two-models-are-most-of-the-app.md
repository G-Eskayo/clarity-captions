# Two models are 96.5% of the app

- **Source:** our own Release build of 1.1 build 7, Mac mini M4, 2026-10-29 (#200):
  [`docs/perf/install-size-2026-10-29.md`](../../perf/install-size-2026-10-29.md).
- **What we took:** the app is 765 MB on disk (717 MB zipped). Parakeet Ultra is 498 MB and Sortformer 241 MB;
  code, every string and the fonts are 26 MB. English UI text is 12 KB. The models barely compress (3–8%).
- **Confidence:** Ours. An unsigned build; the App Store's per-device numbers will differ somewhat.
- **Drives:** splitting the models into packs and shipping every UI language in the app (ADRs 0029, 0030, design
  `docs/design/smallest-install-and-language-packs.md`).
- **Public use:** Careful ("the app itself is about 26 MB; the speech models download for the languages you use", once built).
