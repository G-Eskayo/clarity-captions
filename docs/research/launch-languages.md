# Speech locales available on Apple devices: what Seal supports at launch

2026-10-30, macOS 26.5.1 + 27.0.1 probed. Research documents in [`languages-batch/`](languages-batch/) and
[evidence](evidence/2026-10-30-apple-speech-locales-26-and-27.md).

## 1. Tiers: which engines at which quality

Three speech engines available on iOS:

- **`SpeechTranscriber`** (iOS 26+, the engine Seal uses): on-device, no session cap, no setup, fast. The chosen
  transcription engine ([[0001]]). macOS 26.5.1 has 30 locales; 27.0.1 likely has 45 (Hindi probably new).
- **`DictationTranscriber`** (system dictation, fallback for languages without SpeechTranscriber, including Hebrew and Arabic):
  Apple's fallback engine. Measured on Hebrew to be 4x worse than open models
  ([[evidence 2026-10-29-hebrew-engines-on-conversation]]).
- **`SFSpeechRecognizer`** (older API, session cap, setup required): deprecated by Apple, included in measurements above
  for completeness.

**Tier A (SpeechTranscriber):** 10 languages on macOS 26.5.1; 11 on 27 (German, English, Spanish, French,
Italian, Japanese, Korean, Portuguese, Cantonese, Mandarin, Hindi).

**Tier B (DictationTranscriber only):** 23 languages on 26.5.1; 22 on 27 (Hindi moved to SpeechTranscriber).
These are: Arabic, Catalan, Czech, Danish, Greek, Finnish, Hebrew, Croatian, Hungarian, Indonesian, Malay,
Norwegian, Dutch, Polish, Romanian, Russian, Slovak, Swedish, Thai, Turkish, Ukrainian, Vietnamese.
At launch, Seal will caption these using Apple's `DictationTranscriber` engine (no owned model required).

**Tier C (neither engine, need an owned model):** everything else. Candidates in order of reach and cost: Arabic
(411M L1 speakers), Persian (91M), Bengali (234M), Urdu (78M), Vietnamese (86M). See [[languages-batch]] §3–4 for the
full analysis.

## 2. macOS measurements

| Engine | Locales | Languages |
|---|---|---|
| `SpeechTranscriber` 26.5.1 | 30 | de, en, es, fr, it, ja, ko, pt, yue, zh (10) |
| `SpeechTranscriber` 27.0.1 | 45 | the 10 above plus hi, + regional variants (11) |
| `DictationTranscriber` both | 54 | SpeechTranscriber languages **plus** ar, ca, cs, da, el, fi, he, hi, hr, hu, id, ms, nb, nl, pl, ro, ru, sk, sv, th, tr, uk, vi (23 dictation-only on 26.5.1; 22 on 27 with hi moved to SpeechTranscriber; 33 total languages) |

**Source:** [`apple-speech-locales-macos-26.5.1.json`](apple-speech-locales-macos-26.5.1.json), read 2026-10-30 on this
Mac; macOS 27 list from [[evidence 2026-10-30-apple-speech-locales-26-and-27]].

**Confidence:** Established on 26.5.1 (direct read). Moderate for 27 (developer consensus from skilli #80 and
EnviousWispr #4105, not published by Apple). Three independent measurements agree.

## 3. iPhone: to be confirmed

The list above is from the Mac; Apple publishes no device support information. Developers report an empty
`SpeechTranscriber` list on A13 iPhones (iPhone 11 and SE 2), and the actual availability per model is **unknown**
until tested. **The app reads the list at launch on each device** ([[0030]]), so Seal's own language list may vary per iPhone.

**To confirm:** Long-press the status word until the developer panel opens (debug build only; Xcode builds only). Tap
"Speech locales", copy the JSON, paste it into
`docs/research/apple-speech-locales-iphone-<version>.json` (where `<version>` is the iOS version like `27.0`) on the branch.
One measurement per iOS version suffices. The owner will measure on her own devices.

## 4. Download sizes

Each language costs differently:

- **Apple engines (Tier A + B):** 0 MB per locale per ADR 0029 (system-provisioned, no download).
- **Parakeet multilingual pack** (6 core languages: English, Spanish, French, German, Italian, Portuguese; already shipped): 498 MB shared, downloaded once per app install.
  **Zero marginal cost per language.** The 13 Tier-B languages evaluated against Parakeet ([[#158]]) use DictationTranscriber at launch (no model needed).
- **Owned packs** (Tier C, if built): per-language Seal bundles, about 65–70 MB each at 4-bit compression for a 115–120M model
  (scaled from Hebrew's 38.6 MB from 66M parameters at 4-bit). Five such packs come to about 330 MB total. ADR 0029
  rules out bundling: every user downloads only what they actively caption in (see [[0029]]).

## 5. Proposed first batch at launch

**Tier A:** the 10 (26.5.1) or 11 (27.0.1) `SpeechTranscriber` languages. Seal captions them with no download, no on-device model.

**Tier B:** the 23 (26.5.1) or 22 (27.0.1) dictation-only languages. Seal captions them using Apple's `DictationTranscriber` engine (no owned model, no new download).

**Tier C (owned models):** deferred to 1.2.
- **Later batch:** Arabic, Persian, Bengali, Urdu and Vietnamese. Reach: 1.5B speakers across Middle East, South
  Asia and Southeast Asia. Every language needs measurement, conversion, compression and a credit entry. Planned
  tickets: see [[languages-batch]] §8.

## 6. Language detection: TBD

The app reads the device's locale at startup and captions in the primary user's language by default. Seal has no
built-in language detection; the primary user chooses a caption language once in Settings. For face-to-face mode, each
half's language is read separately as the engine detects it.

Code: [[0030]].

## Notes

- **iPhone device parity:** whether iPhones support the same `SpeechTranscriber` list as the Mac is **Unknown** (Apple
  publishes nothing, A13 data points to no; newer A-series chip parity is unstudied). This is why Seal reads the list
  on-device.
- **Hindi:** Apple's June 2026 Speech updates are audio-input helpers only, not language additions. So on 27, Hindi's
  most likely from a backend change, not a speech framework update. Whether it exists on iPhones is **Unknown**.
- **Hebrew:** Special case. macOS 26.5.1 has it only in `DictationTranscriber`, so Apple's engine there is dictation.
  At launch, Seal still captions Hebrew (and Arabic once built) via the open model, not Apple, because the open model
  is far better ([[evidence 2026-10-29-hebrew-engines-on-conversation]]).

