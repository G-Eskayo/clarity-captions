# E20. Translation engines for 1.3: licences, terms and how each gets its model onto the phone

- **Source:** [ML Kit Terms](https://developers.google.com/ml-kit/terms) (modified 2025-05-14) and the
  [ML Kit Translation guidelines](https://developers.google.com/ml-kit/language/translation/translation-terms);
  [ML Kit Translation overview](https://developers.google.com/ml-kit/language/translation); Hugging Face model cards
  for [`Helsinki-NLP/opus-mt-en-es`](https://huggingface.co/Helsinki-NLP/opus-mt-en-es) and its fr, de and tc-big
  siblings; [mozilla/firefox-translations-models](https://github.com/mozilla/firefox-translations-models) LICENSE;
  [`Unbabel/wmt22-comet-da`](https://huggingface.co/Unbabel/wmt22-comet-da); FLORES-200 (CC BY-SA 4.0) and
  [WMT24++](https://huggingface.co/datasets/google/wmt24pp) (Apache 2.0). All read 2026-10-26 for #159.
- **What we took:** every engine tested is usable in a paid app. **ML Kit** is free, but its translation guidelines
  require Google's Cloud Translation attribution and branding in the app, it may only ship on phones, tablets and
  computers, its models may not be reverse engineered, and **the SDK sends usage and performance metrics to Google**
  (our harness saw ML Kit keep a growing `datatransport` event database, 2.7 MB after one language), which the app
  must disclose. ML Kit downloads languages with the app's own code and no system UI. **OPUS-MT** models are Apache
  2.0 (en-es, en-fr) or CC BY 4.0 (en-de, tc-big), credited like Parakeet; the app owns download and storage.
  Firefox's Bergamot models are MPL 2.0. **Apple's** Translation framework downloads languages only through a
  system sheet or Settings (E15). NLLB-200 stays out (CC BY-NC). The reference-free CometKiwi metrics are
  non-commercial, so scoring uses the Apache 2.0 `wmt22-comet-da`.
- **Confidence:** Strong (official terms and model cards).
- **Drives:** the 1.3 engine choice (#159), the privacy label if ML Kit is used, the credits screen.
- **Public use:** Internal.
