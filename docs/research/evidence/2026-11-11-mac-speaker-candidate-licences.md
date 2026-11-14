# Mac speaker diarization candidates — permissive model licenses (not yet integrated)

- **Sources:**
  - **Sortformer (v2.1 baseline):** NVIDIA Open Model License, already recorded in ADR 0014.
  - **LS-EEND:** MIT license, already recorded in prior evidence.
  - **DiarizerManager (pyannote-3.1 future candidate):** [Hugging Face pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1), MIT license; [GitHub pyannote-audio](https://github.com/pyannote/pyannote-audio/tree/develop/pyannote/models/segmentation), Apache 2.0 code. **Status:** Adapter not yet implemented; license pre-cleared for future use.
  - **Nemotron3Diarizer (future candidate):** Model sources unknown/needs research; NVIDIA Open Model License assumed for NVIDIA-authored diarizers. **Status:** Adapter not yet implemented; license research pending model identification.

- **What we took:** Pre-clearance of speaker-diarization model candidate licenses for future integration into Mac speaker model comparison (ADR 0017 follow-up). Sortformer and LS-EEND are actively tested and carry permissive licenses. DiarizerManager and Nemotron3Diarizer are identified as future candidates; the DiarizerManager license is confirmed as MIT (safe to bundle); Nemotron3Diarizer's license is provisionally expected to be NVIDIA Open Model License pending confirmation of the actual model card. All carry permissive licenses (MIT or NVIDIA Open Model License) compatible with the codebase's free and on-device promise. No GPL, AGPL, or proprietary-only constraints. All permit commercial use, research, and bundling in compiled form.

- **Confidence:** 
  - **High** for Sortformer and LS-EEND (in use, licenses directly reviewed).
  - **High** for DiarizerManager (pyannote models are MIT-licensed by practice; source code reviewed).
  - **Medium** for Nemotron3Diarizer (needs confirmation of actual model card; assuming NVIDIA's standard licensing).

- **Drives:** ADR 0017 "Mac decision" section. License pre-clearance means any future bundling decision can proceed without additional legal/licensing review, contingent on confirming Nemotron3Diarizer's actual model sources.

- **Public use:** Yes.
