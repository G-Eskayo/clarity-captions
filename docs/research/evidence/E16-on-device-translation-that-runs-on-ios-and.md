# E16. On-device translation that runs on iOS and Android, and what licences rule out

- **Source:** [ML Kit Translation](https://developers.google.com/ml-kit/language/translation) and its
  [iOS guide](https://developers.google.com/ml-kit/language/translation/ios); [NLLB-200 model card](https://huggingface.co/facebook/nllb-200-distilled-600M).
- **What we took:** ML Kit translates 50+ languages offline on both platforms, about 30 MB per language, downloads
  managed by the app, pivots through English, aimed at "casual and simple" text. NLLB-200 is CC BY-NC 4.0, so it is out
  for a paid app.
- **Confidence:** Strong (official docs). ML Kit's terms not yet read.
- **Drives:** ADR 0026; the 1.3 translation comparison test (Apple vs ML Kit vs OPUS-MT/Bergamot).
- **Public use:** Internal.
