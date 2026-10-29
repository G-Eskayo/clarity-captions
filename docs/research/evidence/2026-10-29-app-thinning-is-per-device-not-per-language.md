# App thinning is per device, not per language

- **Sources:** Apple Developer, [Reducing your app's size](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)
  (read 2026-10-29 through its JSON page): the App Thinning Size Report gives sizes "for each variant", built for "all
  compatible device variants", and an exported IPA per variant contains "assets and binaries for only one variant".
  The owner's revised answers on PR #205 (2026-10-29). Our measurement: English UI text is 12 KB
  (`docs/perf/install-size-2026-10-29.md`).
- **What we took:** the store's variants are device variants; the page says nothing of slicing by language, so there's
  no store setting that ships only the phone's UI language. About 50 UI languages at about 12 KB each are about
  0.6 MB, against about 765 MB of models: shipping them all costs nothing that matters, and keeps iOS's per-app
  language switch working offline.
- **Confidence:** Moderate (official documentation, but it's silent on languages rather than saying "never"; the
  12 KB is ours).
- **Drives:** ADR 0030 point 1 (every UI language ships inside the app), Decision `ui-text` on PR #205.
- **Public use:** Internal.
