# Apple Speech framework on 27: locales, devices, system-wide ASR hints

Research date / all URLs accessed: **2026-10-30**. Read-only web research.
Tiers: **Established** (official Apple doc, or 2 or more independent sources), **Contested**, **Speculative**, **Unknown**.

## Bottom line

- No Apple source publishes the SpeechTranscriber locale list for 26 or 27. Apple doesn't publish device lists either. The full 45-locale list is **Unknown**: no source I found prints it.
- Two independent developer measurements on macOS 27 confirm the **count** (SpeechTranscriber 45, DictationTranscriber 54). One of them names the **23 DictationTranscriber locales whose language SpeechTranscriber has in no variant**: ar-SA ca-ES cs-CZ da-DK el-GR fi-FI **he-IL** hr-HR hu-HU id-ID ms-MY nb-NO nl-BE nl-NL pl-PL ro-RO ru-RU sk-SK sv-SE th-TH tr-TR uk-UA vi-VN.
- So on macOS 27.0.1 SpeechTranscriber still has **no** Arabic, Hebrew, Russian, Turkish, Polish, Dutch, Vietnamese, Thai or Indonesian. **Hindi is the only plausible new language.** The other new entries look like extra regional variants of languages it already had.
- WWDC26 added no SpeechTranscriber language, language-detection or vocabulary features. The only June 2026 Speech changes are audio-input helpers.

## 1. SpeechTranscriber / DictationTranscriber on 27

| Claim | Source (accessed 2026-10-30) | Tier |
|---|---|---|
| On macOS 27.0.1, measured 2026-10-27: "`SpeechTranscriber` 45 locales, `DictationTranscriber` 54, of which 23 in languages `SpeechTranscriber` has in no variant (ar-SA ca-ES cs-CZ da-DK el-GR fi-FI he-IL hr-HR hu-HU id-ID ms-MY nb-NO nl-BE nl-NL pl-PL ro-RO ru-RU sk-SK sv-SE th-TH tr-TR uk-UA vi-VN)". PR by jbronssin, merged 2026-10-28. | https://github.com/nomdelasociete/skilli/pull/80 | Established (count, together with the next row); single source for the 23-list |
| Probe dated 2026-10-25: "SpeechTranscriber supports 45 locales, DictationTranscriber 54"; "23 are dictation-only (ar, ca, cs, da, el, fi, he, hr, hu, id, ms, nb, nl-BE, nl-NL, pl, ro, ru, sk, sv, th, tr, uk, vi)". The macOS version isn't stated, but the issue mentions macOS 26 for the app. This second source agrees with the skilli PR. | https://github.com/saurabhav88/EnviousWispr/issues/4105 (opened 2026-10-26) | Established (agrees with skilli) |
| "on macOS 27, SpeechTranscriber lists 45 locales, including zh-TW, zh-HK, zh-CN and yue-CN" (issue opened 2026-10-20) | https://github.com/kitlangton/scrawl/issues/51 | Established (third report of 45) |
| FluidVoice locale-picker PR tested on "macOS 27.0.1", built from `SpeechTranscriber.supportedLocales`. It names only zh-CN/zh-HK/zh-TW/yue-CN/fr-FR and gives no full list. | https://github.com/altic-dev/FluidVoice/pull/1236 (opened 2026-10-24) | Established that the list is runtime-only; no list given |
| **Hebrew, Arabic, Russian, Turkish, Polish, Dutch, Vietnamese, Thai and Indonesian are NOT in SpeechTranscriber on macOS 27** (all in the 23 dictation-only list) | skilli #80 + EnviousWispr #4105 | Established (two independent dev measurements; not Apple) |
| **Hindi is probably new on 27.** Our 26.5.1 DictationTranscriber list (54) minus those 23 leaves 31 locales: the 30 SpeechTranscriber locales on 26.5.1 **plus hi-IN**. Because hi is not in the "no variant" list, SpeechTranscriber on 27 has Hindi in some variant (hi-IN and/or hi-Latn). This assumes the 54-entry Dictation list is the same on 27, which the matching count suggests but doesn't prove. | Inference from skilli #80 + our 26.5.1 dump | Speculative→Contested (inference; needs a runtime dump) |
| The remaining ~14 new locales must be extra **regional variants of languages SpeechTranscriber already had** (de/en/es/fr/it/ja/ko/pt/yue/zh/hi). The SFSpeechRecognizer-only extras en-AE/en-ID/en-PH/en-SA, es-419, es-CO, hi-Latn and wuu-CN are obvious candidates, but no source names them. | Inference | Speculative |
| The exact 45-locale list | Not found in any Apple doc, WWDC26 session, release note, forum post or news article | **Unknown** |
| DictationTranscriber on 27: still 54 (count unchanged from our 26.5.1 dump) | skilli #80, EnviousWispr #4105 | Established (count); membership changes Unknown |
| Apple doc for `SpeechTranscriber` / `supportedLocales`: all members are "iOS 26.0+". "This array is empty if the device does not support the transcriber." No locale list and no members new in 27.0. | https://developer.apple.com/documentation/speech/speechtranscriber.md ; https://developer.apple.com/tutorials/data/documentation/speech/speechtranscriber/supportedlocales.json | Established |
| Speech "updates" page, June 2026 (the 27 cycle): only `AssetInputSequenceProvider` / `CaptureInputSequenceProvider` (audio from file/asset/mic) and `AnalyzerInputConverter`. **No language detection, multilingual mode or new vocabulary API.** | https://developer.apple.com/documentation/updates/speech.md | Established |
| Custom vocabulary on 27 is still `AnalysisContext` plus the legacy `SFSpeechLanguageModel`/`SFCustomLanguageModelData` (no new type) | https://developer.apple.com/documentation/speech.md | Established |
| A third-party plugin reports that `AudioSource.asset` and `AnalyzerOptions.ignoresResourceLimits` "need version 27". This likely maps to the new input providers and a SpeechAnalyzer option, but it's not checked against Apple docs. | https://pub.dev/packages/apple_speech | Contested (single third-party) |
| iOS 27 and macOS 27 release notes have **no Speech-framework section**. iOS 27 notes, Dictation: "Dictation can now be powered by a new on-device model that boosts accuracy… toggle on 'Advanced Dictation Preview'" (178444388). This is keyboard dictation, not the Speech API. | https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes.md ; https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes.md | Established |
| Advanced Dictation Preview runs on an on-device Apple model and is off by default. Device requirements are disputed (17 Pro/Air only vs. M3 + 12 GB). No language list was found, and no evidence that DictationTranscriber uses it. | https://9to5mac.com/2026/06/12/ai-advanced-dictation-preview-ios-27-beta/ ; https://www.macrumors.com/2026/06/22/advanced-ai-dictation-not-enabled-by-default/ ; https://apple.gadgethacks.com/news/ios-27-advanced-ai-dictation-which-iphones-can-run-it/ | Contested (devices); Speculative for any link to the Speech API |
| WWDC26 has no Speech/SpeechAnalyzer session. The video index's only caption-related session is #256 "Discover generated subtitles and subtitle styles". | https://developer.apple.com/videos/wwdc2026/ | Established (as of the index page) |

**Caveat, an old list that conflicts:** Anton Gubarenko's guide (2025-07-28, iOS 26 beta, updated 2025-09-15) prints a 42-entry "SpeechTranscriber.supportedLocales" list that **includes he_IL, ar_SA, ru_RU, tr_TR, nl_NL, th_TH, vi_VN** and omits pt-PT. It conflicts with our 26.5.1 dump and with the 27.0.1 measurements. It was most likely a beta artifact or a mix-up with the dictation list. https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide. **Contested; don't rely on it.**

## 2. iPhone/iPad vs Mac; which devices support SpeechTranscriber

| Claim | Source | Tier |
|---|---|---|
| Apple doesn't publish device lists. DTS: "We typically do not publish such lists… use the isAvailable check at runtime, and design a fallback" (Oct 2025) | https://developer.apple.com/forums/thread/802863 | Established |
| Apple doc: "Use isAvailable or supportedLocales… If it does not [support], consider… using DictationTranscriber"; DictationTranscriber is "compatible with older devices" | https://developer.apple.com/documentation/speech/speechtranscriber.md ; https://developer.apple.com/documentation/speech.md | Established |
| `isAvailable == false` and `supportedLocales == []` on iPhone 11, 11 Pro, 11 Pro Max and SE (2nd gen), all A13 with an 8-core Neural Engine. iPhone 12 through 17 work. The poster's theory: a 16-core Neural Engine is required. M1/M4 Macs work (Mar 2026). The Simulator always returns false. | https://developer.apple.com/forums/thread/806765 | Contested (developer tests, not Apple; consistent across posters) |
| By that theory, iPhones running iOS 26 that support SpeechTranscriber = A14 and later (iPhone 12 and later, SE 3rd gen). iPads with A14/M1 or later. | Inference from above | Speculative |
| **Whether the locale *list* differs between iPhone/iPad and Mac on a supported device:** no source compares them. The Apple wording implies all-or-nothing per device (empty vs full list), not per-locale differences. | — | **Unknown** (Speculative: same list) |

## 3. System-wide hints (iOS 27 feature-availability page)
Source: https://www.apple.com/ios/feature-availability/ (iOS and iPadOS 27 page, accessed 2026-10-30). Read via a summarising fetcher, so exact list membership should be spot-checked.

| Feature | Languages (as listed) | Hebrew? | Tier |
|---|---|---|---|
| Accessibility: Live Captions (18) | yue (CN, HK); en (AU, CA, IN, SG, UK, US); fr (CA, FR); de-DE; ja; ko; zh (CN, TW); es (MX, ES, US) | No | Established (official) |
| Live Translation, Phone & FaceTime (12) / AirPods (11) | zh (Simplified, Traditional), en (UK, US), fr-FR, de-DE, it (+ it-CH for Phone), ja, ko, pt-BR, es-ES | No | Established |
| Live Translation, Messages (33, text) | includes da, nl, nb, sv, tr, vi, etc. | No | Established |
| Phone: Call Transcription (15) | yue-HK; en ×7; ja; ko; zh (CN, TW); pt-BR; es (MX, US) | No | Established |
| Live Voicemail / Call Screening (26) | yue, en, fr, de, ja, ko, zh, pt-BR, es variants | No | Established |
| Phone: Call Recording (32) | includes Arabic, Hebrew, Hindi, Russian, Turkish, Polish, Dutch, Vietnamese, Thai, Indonesian | Yes | Established that the list exists. It's **recording**, not transcription, so it is no evidence of ASR support (Speculative as an ASR hint) |
| Translate: System-Wide Translation (26) | includes Hebrew, Arabic, Hindi, Russian, etc. | Yes | Established (text translation, not ASR) |
| Translate app on iOS 27 adds 9 (Cantonese Traditional, Danish, **Hebrew**, Malay, Norwegian Bokmål, pt-PT, es-MX, es-US, Swedish), for 30 total. It says nothing about speech input for them. | https://9to5mac.com/2026/07/08/ios-27-adds-nine-new-languages-and-accents-to-apple-translate/ | Established (as reported); speech-input coverage Unknown |
| Generated subtitles (WWDC26 #256): "Starting in iOS and macOS 27, English subtitles can be generated from English audio… multiple subtitle languages can be generated from English subtitles". The ASR is English-only and the session does not name SpeechAnalyzer. | https://developer.apple.com/videos/play/wwdc2026/256/ | Established |

Reading: Live Captions' 18 locales are a near subset of the 26.x SpeechTranscriber list (they add zh-TW, which SpeechTranscriber has). That fits Live Captions running on the SpeechTranscriber-class model (**Speculative**). No system-wide *speech-recognition* feature on 27 lists Hebrew. Hebrew shows up only in text translation and call recording.

## 4. Published accuracy by language
Apple publishes no per-language WER/CER for SpeechTranscriber or DictationTranscriber. The WWDC25 session (#277), Apple's docs and the WWDC26 index have no figures by language. Only third-party benchmarks exist, mostly English (e.g. https://www.gigazine.net/gsc_news/en/20260714-apple-speech-analyzer-benchmark/), plus our own Hebrew DictationTranscriber FLEURS run (https://github.com/G-Eskayo/clarity-captions/pull/215, CER 16.5%). **Tier: Established that Apple publishes none** (absence across docs, release notes and sessions searched).

## Recommended next step
Dump `SpeechTranscriber.supportedLocales` and `DictationTranscriber.supportedLocales` on the MacBook (macOS 27.0.1) and on an iOS 27 iPhone. That's the only way to get the exact 45, and to confirm hi-IN and the new regional variants.
