# Install size and model sizes, measured (#200)

2026-10-29, Mac mini M4, Xcode 26.6, main at `db3642b` (1.1 build 7: Parakeet Ultra + Sortformer bundled).

## How it was measured

1. Models fetched and checked against their manifests (`scripts/fetch-asr-models.sh`, `scripts/fetch-diarizer-models.sh`:
   20 and 10 files verified).
2. `xcodebuild -scheme CaptionSpike -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
   (arm64, not signed, not App Store encrypted).
3. Sizes are the sum of file sizes in bytes, shown in MB (10^6 bytes). The ticket's "475 MB / 229 MB" are the same
   folders in `du -h` units (MiB of disk blocks).
4. "Compressed" is `zip -9` of the `.app` in a `Payload/` folder, which is what an `.ipa` is. It's an estimate of the
   App Store download, not the App Store's number: the store encrypts the binary (encrypted code doesn't compress) and
   thins per device.

## Results

| Part | On disk | Compressed (zip -9) | Share of the app |
|---|---|---|---|
| **Whole `.app`** | **765.0 MB** | **716.9 MB** | 100% |
| Parakeet Ultra 6-bit (`ParakeetUltra/`) | 498.0 MB | 484.1 MB | 65% |
| of which the encoder | ≈461 MB | | |
| Sortformer v2.1 fp16 (`Sortformer_v2.1.mlmodelc/`) | 240.6 MB | 220.4 MB | 31% |
| **Everything else** (code, strings, fonts, icons) | **26.4 MB** | **12.4 MB** | 3.5% |
| of which the app binary | 23.9 MB | | |
| English strings (`en.lproj`) | 12 KB | | |
| Fonts (Atkinson Hyperlegible, OpenDyslexic) | 0.5 MB | | |
| `latency-fixture.wav` (test audio, ships in Release today) | 0.6 MB | | |

The models barely compress (3% and 8%): they're already palettized or fp16 weights. Splitting them out is the only
lever that moves the install size. Code and strings are under 4% of it.

## Per device

- **iPhone and iPad:** one universal arm64 build, and the models aren't device-specific, so thinning changes little.
  Measured as above.
- **Mac:** not built in this run. `Apps/Mac/project.yml` bundles Sortformer and not Parakeet (the Mac app stays on
  Apple's engine in 1.1, ADR 0025), so expect about 241 MB of model plus its binary. **Not measured.**
- **App Store's own numbers** (download and install size per device model) are in App Store Connect under the
  build's App Store file sizes, and in an Xcode export's App Thinning Size Report. Neither was available unattended
  (it needs a signed export). The design doc (`docs/design/smallest-install-and-language-packs.md` §8) makes
  them the reported numbers from now on.

## Apple's language lists on this Mac (macOS 26.5.1)

Read from the APIs with a throwaway Swift probe (deleted afterwards):

| API | Locales | Languages | Hebrew |
|---|---|---|---|
| `SpeechTranscriber.supportedLocales` | 30 | 10 (de, en, es, fr, it, ja, ko, pt, yue, zh) | no |
| `SpeechTranscriber.installedLocales` | 20 | | |
| `DictationTranscriber.supportedLocales` | 54 | 33 | **he-IL** |
| `LanguageAvailability().supportedLanguages` (Translation) | 38 | 22 | **no** (`en→he` unsupported) |
| `AssetInventory.maximumReservedLocales` | 5 | | |

Serbian is in none of the four (`en→sr` unsupported). The owner's macOS 27.0.1 laptop reported 45 SpeechTranscriber
locales, 54 DictationTranscriber and 47 Translation languages including he↔en (#200), so Hebrew translation arrives
with OS 27. **Not checked on iOS 26 or 27:** there is no phone on the Mini, and the iOS Simulator reports every
Translation pair as unsupported (`TranslationCenter.swift`, 2026-10-28).
