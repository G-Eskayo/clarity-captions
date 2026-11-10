# Sortformer v2.1 is under the NVIDIA Open Model License, not CC BY 4.0

- **Source:** NVIDIA's model card for [`nvidia/diar_streaming_sortformer_4spk-v2.1`](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1)
  (metadata `license: other`, `license_name: nvidia-open-model-license`; the same on every card revision from
  2025-12-01 to 2026-09-23, read through the Hugging Face API on 2026-11-09) and the
  [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/).
  The CoreML conversion we download, [`FluidInference/diar-streaming-sortformer-coreml`](https://huggingface.co/FluidInference/diar-streaming-sortformer-coreml)
  (revision `ae9a27a`), labels itself CC BY 4.0.
- **What we took:** our `NOTICE.md` and ADR 0014 say CC BY 4.0, taken from the conversion's README and accepted
  in ADR 0014's 2026-10-05 re-check without reading NVIDIA's card. The upstream licence allows commercial use and
  derivative models (compressed builds are likely derivatives, and we own them). It requires distributing a copy of the
  agreement and a Notice file reading "Licensed by NVIDIA Corporation under the NVIDIA Open Model License". Rights end
  if we bypass the model's guardrails or sue NVIDIA over it, and NVIDIA may update the terms.
- **Confidence:** Strong for what the card and licence say (primary sources). How the licence applies to our app is
  the owner's call, possibly with legal advice; this entry is not legal advice.
- **Drives:** an owner decision on #271 (credit change, a lawyer, or a different model) before step 2's compressed
  builds ship, and the NOTICE.md / in-app credits / ADR 0014 text.
- **Public use:** Internal until decided.
