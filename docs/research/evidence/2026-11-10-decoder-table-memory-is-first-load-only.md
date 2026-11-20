# Compressed decoder costs extra memory only on a model's first load

- **Source:** our measurement, 2026-11-10, M4 Mac mini, macOS. `phys_footprint` around Core ML loads of the Parakeet
  Ultra decoder and joint (`scripts/engine-eval/coreml-memprobe.swift`) and the 60-clip `engine-eval memory` run.
  Numbers in `docs/perf/engine-accuracy-comparison.md` (#272, step 3).
- **What we took:** the 6-bit decoder and joint (22 MB smaller download) peak at 94–96 MB on a first load against
  60–73 MB for the shipped fp16 ones. Once Core ML has cached its device copy, both peak at 56–61 MB.
- **Confidence:** Ours (macOS on the M4; not yet repeated on an iPhone).
- **Drives:** the decoder question on #272 (compress the decoder and joint or not).
- **Public use:** Internal.
