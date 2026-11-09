# Real-voice speaker test corpora and their licences

- **Sources:** each corpus's own licence page, read 2026-11-09:
  [AMI Meeting Corpus licence](https://groups.inf.ed.ac.uk/ami/corpus/license.shtml) (CC BY 4.0);
  [CHiME-6 on OpenSLR](https://openslr.org/150) and its `LICENSE.txt` (CC BY-SA 4.0, derived from CHiME-5);
  [AliMeeting on OpenSLR](https://www.openslr.org/119/) (CC BY-SA 4.0); [VoxConverse](https://github.com/joonson/voxconverse)
  ("available to download for research purposes under a Creative Commons Attribution 4.0 International License").
  What Sortformer was trained on: [NVIDIA's model card for `diar_streaming_sortformer_4spk-v2.1`](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1).
  Reference labels for AMI: [pyannote/AMI-diarization-setup](https://github.com/pyannote/AMI-diarization-setup)
  (Apache 2.0), commit `67c2d53`, `only_words` RTTMs, Full-corpus-ASR partition.
- **What we took:**
  - **AMI** (CC BY 4.0: commercial use allowed with attribution). 4 people per meeting (one test meeting has 3),
    real overlap, long presentations by one person, one far-field table microphone (Array1-01). Sortformer was
    trained on AMI's *train* meetings, so we score only the official *test* meetings and calibrate only on the *dev*
    meetings. Dev and test share no speakers (checked against the setup's speaker lists).
  - **CHiME-6** (CC BY-SA 4.0: commercial use allowed; ShareAlike binds only adaptations of the data we distribute,
    and we publish only aggregate scores). Dinner parties in real homes (kitchen, dining room, living room), 4
    people, constant overlap and household noise: the noisy-room case AMI lacks. **Not** in Sortformer's training
    list, so it is the cleanest test of the four. The 2018-era CHiME-5 commercial-licence route no longer applies; the
    OpenSLR release carries CC BY-SA 4.0.
  - **AliMeeting** (CC BY-SA 4.0): Mandarin, 2–4 people. Not used: Sortformer trained on it, and English first.
  - **VoxConverse** (CC BY 4.0 "for research purposes", audio from YouTube): not used. Sortformer trained on it,
    many recordings have more people than Sortformer's 4 slots, and the "research purposes" wording next to a
    licence that allows commercial use leaves the audio's terms unclear.
  - Published reference numbers to sanity-check our harness: NVIDIA's card gives AMI test, single distant mic, DER
    20.57% at 1.04 s latency (its own reference labels); FluidAudio's benchmark gives the same meetings 26.4% with
    its high-latency setting and a 0.25 s collar. Our scorer uses no collar and pyannote's reference.
- **Handling:** audio is kept on the 2012 Mac mini only, copied to the M4 one meeting at a time and deleted after
  the run; it never goes in the repo or on a public page. Only aggregate scores are published.
- **Confidence:** Strong for the licence terms (the corpora's own pages); Strong for the training-data overlap
  (NVIDIA's own card).
- **Drives:** #271 speaker scoreboard (AMI test + CHiME-6 eval as test, AMI dev + CHiME-6 dev as the calibration
  slice for compressed builds, never scored): `scripts/engine-eval/speaker_eval/`,
  [design](../../perf/speaker-scoreboard-design.md).
- **Public use:** Careful (cite the corpora and aggregate DER; never quote or play their audio; attribute AMI and
  CHiME-5/6 as their licences require).
