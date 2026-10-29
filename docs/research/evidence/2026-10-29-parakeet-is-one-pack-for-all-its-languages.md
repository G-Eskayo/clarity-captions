# Parakeet is one pack for all its languages

- **Sources:** E14 (Parakeet Ultra is a post-training of Parakeet TDT 0.6B v3, 25 European languages, language
  detected automatically); our size measurement (`docs/perf/install-size-2026-10-29.md`: 498 MB, of which the encoder
  ≈461 MB); the FluidAudio checkout the app builds against, read 2026-10-29 (the Parakeet v3 path takes no language
  argument; its single-language Parakeets, such as Japanese, are separate full models).
- **What we took:** one encoder, decoder, joint network and vocabulary serve all 25 languages, so there's no
  per-language piece to split off: a "German Parakeet pack" would be the same 498 MB as the English one. One shared
  pack means a second Parakeet language costs nothing; per-language copies would double it. The app can't pin
  Parakeet to a language; it picks the engine by language and Parakeet follows the audio.
- **Confidence:** Strong for the sizes and the shared weights (ours and the model card); Moderate for "no language
  setting" (read from FluidAudio's source, not documented by NVIDIA).
- **Drives:** ADR 0029 point 3 (one shared Parakeet pack), the design doc §6.
- **Public use:** Internal.
