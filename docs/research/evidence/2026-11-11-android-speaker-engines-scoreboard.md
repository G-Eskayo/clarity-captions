# Speaker labels on Android: Sortformer v2 ONNX and sherpa-onnx on the real-voice scoreboard

- **Source:** our own measurement, #160, [`docs/perf/speaker-android-engines.md`](../../perf/speaker-android-engines.md)
  and its JSON files: AMI test (16 meetings, 9.1 h) and CHiME-6 eval (31 windows, 5.2 h), the #276 split and scorer,
  through a Python port of the app's live speaker path. The port was checked against the app's Core ML run on v2.1
  weights (99.0% of frames, 46 of 47 final labels the same). Run on the 2012 Mac mini CPU, 2026-11-10 to 11.
- **What we took:**
  - Sortformer **v2** ONNX (`Recogment/sortformer-4spk-v2-onnx`, CC BY 4.0) against the shipped v2.1 Core ML fp16, on
    what the screen shows (paired difference, 95% CI): AMI **−1.0 points** (−3.2 to +1.0), CHiME-6 **+2.3**
    (+0.9 to +3.8). Same monologue splitting and first-label time (0.62 s / 0.64 s median); more CHiME-6 lines left
    unlabelled (13.8% vs 7.5%).
  - NVIDIA's own 10-point AMI gap between v2 and v2.1 does not show on the app's path (bare model: AMI −3.4, CHiME-6
    +7.6). Not explained yet.
  - sherpa-onnx offline diarization with its example threshold: DER on screen 65.2% (AMI) and 64.7% (CHiME-6), with
    about 44 speakers found in 4-person meetings. Untuned, because tuning would need the calibration recordings, and
    offline only.
  - Speed on a 2012 desktop CPU (0.25–0.30× real time for v2 fp32 ONNX, about 830 MB) says nothing about phones.
- **Confidence:** Strong for the scores on these two sets (repeat runs identical, the baseline reproduces #276
  exactly, CIs on every number); Weak for anything about phone speed; Moderate that v2's accuracy carries to other
  rooms (two corpora, both meetings or dinner parties).
- **Drives:** #160 (which speaker engine an Android build would use, and under which licence); ADR 0026 ("Apple
  first, portable next").
- **Public use:** Yes (our own numbers on public corpora; name the corpora and that the speed is not a phone's).
