# Speaker-label engines that run on Android: which checkpoint each is, and its licence

- **Sources:** NVIDIA's own model cards, read through the Hugging Face API on 2026-11-09:
  [`nvidia/diar_streaming_sortformer_4spk-v2.1`](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1)
  (revision `cd03eee`, `license: other`, "governed by the NVIDIA Open Model License Agreement"),
  [`nvidia/diar_streaming_sortformer_4spk-v2`](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2)
  (revision `84edd51`, "covered by the CC-BY-4.0"), [`nvidia/diar_sortformer_4spk-v1`](https://huggingface.co/nvidia/diar_sortformer_4spk-v1)
  (revision `2617bff`, `cc-by-nc-4.0`). The community ONNX exports and what each says it was made from:
  [`soniqo/Sortformer-Diarization-4spk-ONNX`](https://huggingface.co/soniqo/Sortformer-Diarization-4spk-ONNX) (`a7176b2`),
  [`Recogment/sortformer-4spk-v2-onnx`](https://huggingface.co/Recogment/sortformer-4spk-v2-onnx) (`f26a957`),
  [`TalkBar/ultra-sortformer-8spk`](https://huggingface.co/TalkBar/ultra-sortformer-8spk) (`aa03a9d`). sherpa-onnx
  ([PyPI 2.0.1](https://pypi.org/project/sherpa-onnx/), Apache 2.0) and its diarization models:
  [`pyannote/segmentation-3.0`](https://huggingface.co/pyannote/segmentation-3.0) (`license: mit`, gated) as converted in
  [`csukuangfj/sherpa-onnx-pyannote-segmentation-3-0`](https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0)
  (`9403a69`, ships CNRS's MIT `LICENSE`); WeSpeaker's VoxCeleb ResNet34 as sherpa-onnx's `wespeaker_en_voxceleb_resnet34.onnx`
  ([WeSpeaker's model licence](https://github.com/wenet-e2e/wespeaker/blob/master/docs/pretrained.md): "follows the
  license of its corresponding dataset", CC BY 4.0 for VoxCeleb; the [HF card](https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34) says Apache 2.0);
  [`Revai/reverb-diarization-v1`](https://huggingface.co/Revai/reverb-diarization-v1) (`license: other`, gated).
- **What we took:**
  - **The exports are different checkpoints, not one model in different formats.** soniqo is v2.1 (the weights the
    app ships through FluidAudio, NVIDIA Open Model License), traced at the 30 s high-context shapes only (a fixed
    3048-frame chunk). Recogment is **v2**, the earlier checkpoint, with dynamic shapes, under **CC BY 4.0** on
    NVIDIA's own v2 card. TalkBar is an 8-speaker fine-tune (`mago-ai/ultra_diar_streaming_sortformer_8spk_v1`,
    labelled Apache 2.0 by its authors) of v2.1, so NVIDIA's Open Model License flows through, as TalkBar's card
    itself says. None is the CC BY-NC offline v1, which stays out (ADR 0026: paid app).
  - Licences, for a paid app: v2.1 and the 8-speaker fine-tune are under the NVIDIA Open Model License (commercial use
    allowed; the owner already accepted those terms for the shipped model on #271). v2 is CC BY 4.0 (attribution
    only). sherpa-onnx (Apache 2.0), pyannote segmentation-3.0 (MIT) and the WeSpeaker VoxCeleb embedding (CC BY 4.0
    by WeSpeaker's own rule, the stricter of the two claims) all allow commercial use with attribution. Rev's
    reverb-diarization is gated under its own licence and was not run.
  - NVIDIA's own numbers for the two streaming checkpoints at the app's 1.04 s latency: AMI test single distant mic
    DER **v2 31.34% vs v2.1 20.57%**; DIHARD III ≤4 speakers 14.49% vs 15.09%. So v2's open licence costs about 10
    points on meetings by NVIDIA's measure; our scoreboard measures it on the same split as #276.
  - pyannote segmentation-3.0 was trained with AMI among its data (its card lists AMI's training set), as Sortformer
    was; the AMI *test* meetings are held out for both, so AMI test stays a fair test for each.
- **Confidence:** Strong for what each card and licence says (primary sources, pinned revisions); the claim that
  soniqo and Recogment are unmodified exports is each exporter's own (Weak), which the parity check on #160 tests for
  soniqo against the app's Core ML model.
- **Drives:** #160 (which Android-capable speaker engines are scored on the #276 scoreboard, and under which licence);
  the credits any Android build would need; ADR 0026's licence-first rule.
- **Public use:** Careful (licence summaries, not legal advice).
