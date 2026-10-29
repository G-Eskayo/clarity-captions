# E27. Which languages Apple can caption, and which of those it can translate

- **Source:** our own reading of Apple's APIs on the M4 Mac mini, macOS 26.5, 2026-10-28 (#171):
  [`SpeechTranscriber.supportedLocales`](https://developer.apple.com/documentation/speech/speechtranscriber) and
  `installedLocales`, and [`LanguageAvailability`](https://developer.apple.com/documentation/translation/languageavailability)
  `supportedLanguages` and `status(from:to:)`.
- **What we took:** the speech engine supports **30 locales in 10 languages** (German, English, Spanish, French,
  Italian, Japanese, Korean, Portuguese, Cantonese, Chinese). Translation supports 38 languages, which covers every
  caption language **except Cantonese** (`yue-CN` → English: unsupported). `SpeechTranscriber` is created for one
  locale and has no language detection, so the language people are speaking has to be chosen before captions start;
  Translation can identify the language of text, but only after it's been captioned in the right language.
- **Confidence:** Strong for the lists on this Mac (read from the APIs); an iPhone or iPad may report a different
  set, so the app reads them on the device. Moderate for "no detection" (no such API in the SDK as of 26.5).
- **Drives:** the caption language list (#37), translation's From row next to Into (#53, PR #171), and saying
  plainly that Cantonese can be captioned but not translated.
- **Public use:** Careful ("Seal captions 10 languages and translates 9 of them on the device").
