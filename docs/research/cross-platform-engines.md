# Cross-platform engines: what could run Seal Speak's features on Android too

First pass, 2026-10-26, for [[0026]]. A map of candidates and open questions, not results: every row still needs
the comparison test in its ticket. Confidence follows the evidence log (E14–E17).

## Summary

| Feature | Apple engine (now or v1) | Cross-platform candidates | Biggest open question |
|---|---|---|---|
| Captions, English | Parakeet Ultra via FluidAudio (1.1) | Same Parakeet weights in ONNX via sherpa-onnx (already run in #145, Parakeet v2) | Ultra in ONNX on an Android phone: speed and memory |
| Captions, other languages (1.2) | `SpeechAnalyzer` (about 25 languages incl. Asian and Indian) | **Parakeet Ultra itself: 25 European languages**, language detected automatically | Is Ultra's non-English accuracy good enough, and how do we cover non-European languages? |
| Translation (1.3) | Translation framework (`TranslationSession`) | Google ML Kit Translation (iOS and Android), OPUS-MT / Bergamot (Marian) | Apple shows a system download sheet; quality vs ML Kit; model licences |
| Speaker labels | Sortformer via FluidAudio (Core ML) | Sortformer in ONNX (community exports), sherpa-onnx diarization | Which Sortformer checkpoint and licence; streaming on Android |
| Sound labels | `SoundAnalysis` (`SNClassifySoundRequest`) | YAMNet (TFLite / LiteRT, 521 AudioSet classes) | Do the classes we show (laughter, applause, doorbell) score as well? |

## Captions in other languages (1.2)

- **Parakeet Ultra is multilingual.** It is Moondream's post-training of NVIDIA Parakeet TDT 0.6B v3, which covers
  25 European languages and detects the language itself. Its model card reports a 25-language FLEURS WER of
  9.55% (v3: 11.62%) and English Open ASR 5.80% (v3: 6.26%). (E14, Moderate: read from a mirror of the card, as the
  Moondream page didn't load; confirm on `moondream/parakeet-ultra`.)
- This contradicts the risk row in `docs/design/parakeet-engine-switch.md` ("Ultra is English-tuned; non-English
  locales use Apple"). That row should be revisited after the language test, not before.
- Not covered by Parakeet: Japanese, Korean, Mandarin, Cantonese, the Indian languages. Those stay on Apple's
  engine on iPhone; Android would need another engine (sherpa-onnx lists SenseVoice, Zipformer and Whisper models).
- **Test to run:** FLEURS (and Common Voice where FLEURS is thin) for Spanish, French and German: Apple vs Parakeet
  Ultra (FluidAudio) vs Parakeet in ONNX (sherpa-onnx). Same harness as #145.

## Translation (1.3)

- **Apple's Translation framework** downloads each language through a system sheet
  (`prepareTranslation()` "asks for permission to download translation languages"). That breaks the Seal design
  rule of no system pop-ups. A forum report says the sheet sometimes fails to show on first use. (E15, Strong for
  the sheet; Weak for the bug.)
- **Google ML Kit Translation** runs on both iOS and Android, 50+ languages, about 30 MB per language, downloaded
  and deleted by the app's own code (no system sheet). It pivots through English for non-English pairs and Google
  calls it "for casual and simple translations". Licence and terms still to read. (E16, Strong for features.)
- **OPUS-MT / Bergamot (Marian)**: open models and an MIT engine used by Firefox's offline translation. Model
  licences not yet confirmed; no ready-made iOS or Android library found yet.
- **Ruled out: NLLB-200** (all sizes) is CC BY-NC 4.0, non-commercial. (E16, Strong.)
- **Test to run:** FLORES-200 sentences plus our own caption-style transcripts, English to Spanish first; score with
  chrF (and COMET if it runs locally); measure speed per caption line on iPhone.

## Speaker labels

- Sortformer, the model behind FluidAudio's diarizer, has community ONNX exports (4-speaker streaming, about
  470–480 MB, unofficial). Their licence claims disagree: CC BY 4.0 vs the NVIDIA Open Model License, and the older
  offline v1 is CC BY-NC. Read NVIDIA's own card for the exact checkpoint first. (E17, Weak.)
- sherpa-onnx has its own diarization with prebuilt Android demos.
- **Test to run:** the speaker-stability set from `docs/perf/speaker-label-stability.md` (#91), FluidAudio vs an
  ONNX Sortformer vs sherpa-onnx.

## Sound labels

- YAMNet (MobileNet v1, AudioSet, 521 classes) runs through Google's LiteRT task library on Android and iOS. Licence
  believed Apache 2.0, unverified. (E17, Moderate.)
- **Test to run:** clips for the labels Seal shows (laughter, applause, doorbell and so on), Apple vs YAMNet, at the
  same confidence threshold; false alarms per hour of speech.

## Sources

- Parakeet Ultra card (mirror): https://huggingface.co/matenek/parakeet-ultra ; Spokenly on Parakeet v3: https://spokenly.app/blog/parakeet-models
- Apple `TranslationSession`: https://developer.apple.com/documentation/translation/translationsession ; Kodeco, Translation API: https://www.kodeco.com/ios/paths/apple-ai-models/49307459-translation-framework/01-meet-the-translation-api/03
- ML Kit Translation: https://developers.google.com/ml-kit/language/translation ; iOS guide: https://developers.google.com/ml-kit/language/translation/ios
- NLLB-200 model card: https://huggingface.co/facebook/nllb-200-distilled-600M
- Bergamot: https://browser.mt/
- Sortformer ONNX: https://huggingface.co/soniqo/Sortformer-Diarization-4spk-ONNX , https://huggingface.co/TalkBar/ultra-sortformer-8spk , https://huggingface.co/Recogment/sortformer-4spk-v2-onnx
- YAMNet / LiteRT audio classifier: https://ai.google.dev/edge/lite/libraries/task_library/audio_classifier
