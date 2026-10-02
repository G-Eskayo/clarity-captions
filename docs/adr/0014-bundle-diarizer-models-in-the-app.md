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
