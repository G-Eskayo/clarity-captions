# Apple's speech engines on 26 and 27: the same 23 languages stay dictation-only, and Hindi is probably the one new caption language

- **Sources:** our probe on the M4 Mac mini, macOS 26.5.1, 2026-10-30
  ([`apple-speech-locales-macos-26.5.1.json`](../apple-speech-locales-macos-26.5.1.json), from
  `scripts/speech-locales/probe.swift`); developer measurements on macOS 27.0.1:
  [skilli #80](https://github.com/nomdelasociete/skilli/pull/80),
  [EnviousWispr #4105](https://github.com/saurabhav88/EnviousWispr/issues/4105),
  [scrawl #51](https://github.com/kitlangton/scrawl/issues/51); Apple's
  [Speech updates](https://developer.apple.com/documentation/updates/speech) (June 2026) and
  [DTS on device lists](https://developer.apple.com/forums/thread/802863). Notes:
  [`languages-batch/apple-27.md`](../languages-batch/apple-27.md).
- **What we took:** on 26.5.1, `SpeechTranscriber` supports 30 locales in 10 languages and `DictationTranscriber` 54 in
  33; the extra 23 (Arabic ar-SA only, Catalan, Czech, Danish, Greek, Finnish, Hebrew, Hindi, Croatian, Hungarian,
  Indonesian, Malay, Norwegian, Dutch, Polish, Romanian, Russian, Slovak, Swedish, Thai, Turkish, Ukrainian, Vietnamese)
  are dictation-only. On 27.0.1 `SpeechTranscriber` has 45 locales and `DictationTranscriber` 54, and two independent
  reports name the same 23 dictation-only locales, minus hi-IN: so Hindi is very likely the one new language, and
  the rest are regional variants. Apple added no language detection or vocabulary API on 27 and publishes no accuracy
  by language. Persian, Bengali, Urdu, Swahili, Serbian and the other big languages get nothing on either version.
- **Confidence:** Strong for the 26.5.1 lists (read from the APIs). Moderate for the 27 counts and dictation-only list
  (developers, not Apple; three agree). Weak for "Hindi is new" (inferred; no source prints the 45).
- **Drives:** #236's gap table and first batch (`docs/research/languages-batch.md`); Hindi moves to a second batch.
- **Public use:** Careful ("Apple's main on-device caption engine covers about ten languages; Seal adds its own").
