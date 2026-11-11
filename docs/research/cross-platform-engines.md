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
- **Measured (#158, E19):** on FLEURS, Parakeet Ultra beat Apple in Spanish (2.8% vs 4.0% WER), French (4.5% vs
  7.5%) and German (4.4% vs 7.2%). In ONNX on CPU (the Android path), v3 scored 3.9 / 7.0 / 6.6% and a community
  Ultra export 3.2 / 6.2 / 5.3%. Results: [`language-accuracy-comparison.md`](../perf/language-accuracy-comparison.md).

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

- Sortformer, the model behind FluidAudio's diarizer, has community ONNX exports, and they are **different
  checkpoints**. soniqo's export is v2.1, the weights the app ships, under the NVIDIA Open Model License, but its graph
  is fixed at 30 s chunks. Recogment's export is the older v2 under CC BY 4.0, with dynamic shapes. The offline v1 is
  CC BY-NC and stays out. NVIDIA's own AMI figures at 1.04 s latency: v2 31.3% DER, v2.1 20.6%. (Evidence
  `2026-11-09-android-speaker-engine-licences`, Strong for the licences.)
- sherpa-onnx has its own diarization with prebuilt Android demos (Apache 2.0; pyannote segmentation MIT, WeSpeaker
  embedding CC BY 4.0). It is offline: it needs the whole recording before it labels anyone.
- **Test (#160):** the #276 real-voice scoreboard (AMI and CHiME-6 test split, DER with CIs, calibration off-limits),
  run through a Python port of the app's live speaker path. The port matches the app's Core ML run on v2.1 weights
  (99.0% of frames, 46 of 47 final labels). It replaces the #91 clips in `docs/perf/speaker-label-stability.md`.
- **Result (2026-11-11):** Sortformer v2 ONNX is within the CI of the shipped v2.1 on AMI (−1.0 points, −3.2 to
  +1.0) and 2.3 points worse on CHiME-6 (+0.9 to +3.8). Untuned sherpa-onnx is far behind (about 65% DER). Phone speed
  not measured. `docs/perf/speaker-android-engines.md`.

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
