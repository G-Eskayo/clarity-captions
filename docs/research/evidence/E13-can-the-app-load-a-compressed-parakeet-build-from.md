# E13. Can the app load a compressed Parakeet build from its own bundle?

- **Source:** our own spike (#150), recorded in [docs/design/parakeet-engine-switch.md](../design/parakeet-engine-switch.md)
  "Feasibility spike": FluidAudio 0.17.5 source (`AsrModels.loadLocal`, `ASRConstants.maxModelSamples`) and a run of
  the `ultra-pal6` folder on a MacBook with `ModelHub.offlineMode` on. Licenses re-checked on Hugging Face 2026-10-22
  (`moondream/parakeet-ultra`, `nvidia/parakeet-tdt-0.6b-v3`, `FluidInference/parakeet-ultra-coreml`: all CC BY 4.0).
- **What we took:** the pinned FluidAudio loads a local compressed folder with no network; the first load compiles for
  the device (35 s on the Mac, 0.17 s after); every decode pads to a 15 s encoder pass, so the decode rate, not the
  window, sets Neural Engine load.
- **Confidence:** Ours (Mac only; iPhone numbers come from the #150 phone checks).
- **Drives:** ADR 0025, the committed tail-window decoder and adaptive hop, the first-run load step.
- **Public use:** Careful (Mac numbers; say so).
