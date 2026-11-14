# 0014 — Speaker-diarization models ship inside the app

## Status

Accepted (2026-10-02).

## Context

[[0001]]/CONTEXT.md promise zero network after the system's own speech-model install. FluidAudio's
default is to download its models from Hugging Face on first use, which would make first launch
network-dependent and contradict that promise.

## Decision

1. The Sortformer model ships as a **pre-compiled `.mlmodelc` folder in the app bundle**, loaded
   from a URL the app passes in. `TranscriptionEngine` requires that URL (no default), so there is
   no code path that quietly falls back to a download.
2. `ModelHub.offlineMode` is turned on whenever a diarizer is created, so any download that still
   gets attempted throws instead of reaching the network.
3. **Variant and precision: `fastV2_1`, fp16 (~241 MB).** Chosen over palettized (~97 MB, about 0.9
   points worse diarization error) because separating voices in noisy rooms is the product's
   point ([[0012]]) and a 241 MB app is acceptable on Wi-Fi. Switching is two lines: the script's
   `PRECISION` and the config in `LiveDiarizer`. The config must match the shipped files.
4. **Binaries are not committed** to this public repo. `scripts/fetch-diarizer-models.sh` downloads
   them into a gitignored folder with size and sha256 verification, and the project generator
   fails if the folder is missing, so a model-less build cannot happen quietly.

## Consequences

- A fresh clone must run the script once before generating the project.
- Each platform app bundles its own copy ([[0010]]); the shared core only needs a URL.
- If the model is missing at runtime the user sees a plain message, never a download attempt.

## Measured (2026-10-02)

- Release `.app` for iOS: **247 MB** with the fp16 model bundled (the model itself is ~241 MB).
- Clean-audio test with `ModelHub.offlineMode` on and the model loaded from disk: two synthetic
  voices separated correctly (speaker 1 at 0.0-5.0 s and 12.5-17.4 s, speaker 2 at 5.4-11.9 s and
  18.0-24.4 s).
- Not yet verified: first launch on a real phone with networking off.

## License re-check (2026-10-05)

### FluidAudio

- **Pinned revision:** `0b1f46289fe27d95b5e66ad8be46e64f5ee02ae7` (v0.17.5), stored in `Packages/CaptionCore/Package.resolved`.
- **License:** Apache 2.0 — verified by reading its `LICENSE` file in `.build/checkouts/FluidAudio/LICENSE`.
- **Bundled dependencies:** The library compiles fastcluster (BSD-style, © Daniel Müllner / Google) and VBx (Apache 2.0, © BUT Speech@FIT) as native code linked into the binary; both are now documented in the repo's `NOTICE.md`.

### Sortformer (via FluidAudio)

- **Base model identifier:** `nvidia/diar_streaming_sortformer_4spk-v2.1` (Hugging Face).
- **License:** ~~CC BY 4.0 — as stated in the issue description.~~ Wrong: see the correction below (2026-11-09).
- **Conversion:** Converted to CoreML format by FluidInference.
- **Note:** Did not independently re-fetch the model card from Hugging Face this session (no network access in this environment), so the `cc-by-4.0` license is accepted on the issue's authority. The open-source Sortformer base model is documented in `NOTICE.md`.

### Subsequent work

- `scripts/fetch-diarizer-models.sh` currently pulls from Hugging Face's `main` branch, not a pinned commit. Because this environment has no network access, a fixed commit SHA could not be verified. A follow-up task for a future session with network access: pin the model fetch to a specific known revision (by commit SHA) in the script so that the exact artifact being used is permanently recordable.

## License correction (2026-11-09, #271)

The 2026-10-05 re-check took CC BY 4.0 from the CoreML conversion's README without reading NVIDIA's card. NVIDIA's
model card for `nvidia/diar_streaming_sortformer_4spk-v2.1` licenses it under the **NVIDIA Open Model License** (on
every card revision from 2025-12-01; evidence `2026-11-09-sortformer-v2-1-is-under-nvidia-open-model-license`). The
owner chose (on #271): credit it correctly and keep shipping the fp16 model.

- `NOTICE.md` (shown in the app as the full license texts) carries the agreement's text and the Notice line
  "Licensed by NVIDIA Corporation under the NVIDIA Open Model License".
- `Licenses/Sortformer/NOTICE.txt` is the "Notice" text file the agreement asks for, bundled in both apps beside the
  model.
- The Credits page line reads "The voice model. NVIDIA Open Model License."
- A compressed build (#271 step 2) is a Derivative Model under the same agreement: the same notice applies, and
  NOTICE.md must say what was changed.
- The fetch is still unpinned (above): the model we score and ship is identified by its Hugging Face revision and
  tree hash in the #271 scoreboard, not by the script.

## Our own compressed builds, measured (2026-11-09, #271 step 2)

The 2026-10-02 comparison above used FluidAudio's published palettized build on synthetic voices. #271 rebuilt the
shipped fp16 model ourselves (bit-identical), compressed it at 8 and 6 bits, chose one build per bit width on AMI
calibration meetings, and scored both through the app's live speaker path on real voices (AMI test, CHiME-6 eval).
Full numbers: [docs/perf/speaker-scoreboard.md § Step 2](../perf/speaker-scoreboard.md#step-2-compressed-builds).

| Build | Size on disk | DER on screen, AMI | DER on screen, CHiME-6 | Line first label (AMI / CHiME-6) | Ship rule |
|---|---|---|---|---|---|
| fp16 (shipped) | 229.4 MB | 24.0% (20.4–27.3) | 42.5% (38.5–46.3) | 0.62 s / 0.63 s | baseline |
| pal8 | 120.1 MB | 24.5% (19.3–29.2) | 42.3% (38.5–46.1) | 0.62 s / 0.63 s | passes |
| pal6 | 92.6 MB | 24.5% (20.4–28.4) | 42.2% (38.5–45.9) | 0.62 s / 0.63 s | passes |
| int8 | 120.4 MB | | | | excluded: crashes at load |

**Decision:** by the ticket's rule (smallest build whose DER CI overlaps fp16's on both sets, first label within 10%),
**pal6** is the build to ship. Until it is in the app, fp16 stays. The swap needs the exact scored files distributed
(k-means isn't repeatable, so a rebuild is a different, unscored build), a run on a real iPhone, and NOTICE.md
describing the change, since a compressed build is a Derivative Model under the NVIDIA Open Model License.

## Text-processing opt-out (2026-11-13, #32)

Clarity Captions uses only speaker diarization from FluidAudio; the text-processing-rs engine (NeMo Text Processing
binary, ~8 MB per slice) and TTS features (LuxTTS lexicon, models, and tokenizers) are bundled but unused.

### Measured impact

Per FluidAudio's documentation ([PostProcessing.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/PostProcessing.md)):
- NemoTextProcessing xcframework: ~29 MB per iOS architecture slice
- Linked static library after stripping: ~8 MB per slice
- A universal iOS app bundles 4 slices (arm64 device, arm64 simulator, x86_64 simulator, requires measurement on real build)

### Decision

**Opt out of text-processing with `traits: []` in Package.swift.** The feature is only available in Swift 6.2+, which this project uses. Added to FluidAudio dependency on 2026-11-13:

```swift
.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5", traits: []),
```

### Consequences

1. **Size**: Expected ~32 MB saving on a universal iOS app (~8 MB × 4 slices), pending measurement on a real build.
2. **Licensing**: Removes the orphaned NeMo Text Processing and LuxTTS lexicon dependencies. No licensing debt.
3. **Function**: Zero impact. The app doesn't use `TextNormalizer`, Inverse Text Normalization, or TTS. When `traits: []` is active:
   - `TextNormalizer.isNativeAvailable` reports `false`
   - Every normalization call is a no-op (returns input unchanged)
   - TTS features unavailable (not used anyway)
4. **Future use**: If ITN (Inverse Text Normalization) is ever needed for ASR post-processing, the text-processing trait can be re-enabled independently.

### Removed credits

- `ThirdPartyNotice.swift`: removed "nemotextprocessing" entry
- `CreditsEntry.swift`: removed "nemotextprocessing" from `coveredByFullLicenseTexts`
- `NOTICE.md`: removed "NemoTextProcessing", "NVIDIA NeMo Text Processing", "rustfst", "flate2", and "Other Rust dependencies" sections

### Testing

Added `TextProcessingOptOutTests.swift` (regression test) to verify:
- `TextNormalizer.isNativeAvailable` is `false` when traits are disabled
- Normalization is a no-op (returns input unchanged)
