# Speaker labels on Android: engines on the #276 scoreboard (#160)

Speaker-label engines that also run on Android, scored on the same real-voice scoreboard as the shipped Core ML
model ([speaker-scoreboard.md](speaker-scoreboard.md), #276): the AMI test and CHiME-6 eval split, DER with 95% CIs,
calibration recordings refused by the scorer. The baseline is #276's own fp16 result files (rescored here, they give
exactly #276's numbers). Licences come first, from NVIDIA's own cards:
[evidence 2026-11-09-android-speaker-engine-licences](../research/evidence/2026-11-09-android-speaker-engine-licences.md).

| Engine | What it is | Licence |
|---|---|---|
| **Core ML fp16 (shipped)** | Sortformer v2.1 through FluidAudio | NVIDIA Open Model License |
| **recogment-v2** | `Recogment/sortformer-4spk-v2-onnx`: Sortformer **v2**, the earlier streaming checkpoint, ONNX | CC BY 4.0 |
| **sherpa-wespeaker** | sherpa-onnx 2.0.1 offline diarization: pyannote segmentation-3.0 + WeSpeaker VoxCeleb ResNet34 + clustering | Apache 2.0 / MIT / CC BY 4.0 |

Not scored: soniqo's v2.1 ONNX (graph fixed at 30 s chunks, about 2.6 s per streaming step on this CPU; used for the
port check below), TalkBar's 8-speaker fine-tune (owner: skip; these sets have at most 4 speakers), NVIDIA's offline
v1 (CC BY-NC, out for a paid app) and Rev's reverb-diarization (gated, own licence).

**How it runs.** On the 2012 Mac mini (i7-3615QM, CPU only, ONNX Runtime 1.31.1), through a Python port of the app's
live speaker path (`SpeakerPathReplay`, `SpeakerLabelSmoother`, `SpeakerAligner`) and of FluidAudio's Sortformer
streaming host, at the app's config (fastV2_1: chunk 6, left 1, right 7, FIFO 40, speaker cache 188). Code:
`scripts/engine-eval/speaker_onnx/`, driver `scripts/engine-eval/box-speakers.sh`, scoring
`box-speakers-score.sh`.

**The port is checked against the app.** soniqo's v2.1 ONNX (the shipped weights) through the port, against #276's
Core ML fp16 run on EN2002a's first 110 s: the same 256 caption requests at the same moments, 99.0% of 10 ms frames
the same (99.1% on speech), 46 of 47 final labels the same. So a gap below is the engine, not the port. One known
difference: the port breaks an exact overlap tie deterministically, where Swift's order is random (#275, measured at
0.01 points of DER).

## Results

95% CIs: percentile bootstrap over recordings, 1,000 resamples, seed 271. **Difference** = engine minus Core ML fp16,
from a paired bootstrap (both scored on the same resampled recordings), so it is much tighter than comparing the two
intervals. Negative is better. The sets are never pooled.

### AMI test, 16 meetings, 9.1 h

| Measure | Core ML fp16 (shipped) | recogment-v2 | difference | sherpa-wespeaker | difference |
|---|---|---|---|---|---|
| **DER on screen** | 24.0% (20.4–27.3) | **23.0%** (19.3–26.1) | **−1.0** (−3.2 to +1.0) | 65.2% (55.8–73.1) | +41.2 (+31.9 to +48.8) |
| missed / false alarm / confusion | 14.9 / 0.0 / 9.1 | 15.1 / 0.0 / 7.9 | | 15.0 / 0.0 / 50.2 | |
| DER, bare model segments | 36.2% (32.3–39.8) | 32.8% (28.8–37.1) | −3.4 (−5.0 to −1.6) | 69.6% (60.5–77.1) | +33.4 (+24.2 to +40.9) |
| Long monologue split across two labels | 37.6% (30.2–46.2) | 38.6% (32.3–45.3) | +1.0 (−3.0 to +5.3) | 84.1% (76.0–90.3) | +46.5 (+34.9 to +56.1) |
| Speaker count, mean abs error | 0.06 (0.00–0.19) | 0.06 (0.00–0.19) | | **40.2** (26.1–55.8) | |
| Line's first label, median / p90 | 0.62 s / 1.39 s | 0.62 s (0.60–0.63) / 1.39 s | | n/a (offline) | |
| Lines never labelled | 2.9% | 4.2% | | 2.6% | |
| Speed on the 2012 CPU / peak memory | (M4: 22×) | 0.30× real time / 843 MB | | 1.5× / up to 1.9 GB | |

### CHiME-6 eval, 31 windows, 5.2 h

| Measure | Core ML fp16 (shipped) | recogment-v2 | difference | sherpa-wespeaker | difference |
|---|---|---|---|---|---|
| **DER on screen** | 42.5% (38.5–46.3) | 44.8% (41.1–48.4) | **+2.3** (+0.9 to +3.8) | 64.7% (61.7–67.5) | +22.2 (+18.8 to +25.6) |
| missed / false alarm / confusion | 32.5 / 0.7 / 9.3 | 34.9 / 0.6 / 9.3 | | 34.0 / 0.7 / 30.0 | |
| DER, bare model segments | 42.4% (39.1–45.8) | 50.1% (46.1–54.1) | +7.6 (+5.6 to +9.9) | 66.1% (62.9–69.2) | +23.6 (+20.8 to +26.5) |
| Long monologue split across two labels | 65.4% (55.9–74.9) | 65.4% (55.6–74.7) | +0.0 (−6.6 to +4.9) | 80.4% (71.9–87.6) | +15.0 (+2.1 to +25.6) |
| Speaker count, mean abs error | 0.00 | 0.00 | | 3.0 (1.9–4.3) | |
| Line's first label, median / p90 | 0.63 s / 1.45 s | 0.64 s (0.63–0.66) / 1.47 s | | n/a (offline) | |
| Lines never labelled | 7.5% | 13.8% | | 9.7% | |
| Speed on the 2012 CPU / peak memory | (M4: 22×) | 0.25× real time / 842 MB | | 1.9× / 324 MB | |

**Repeats:** two CHiME-6 windows (S01w00, S21w03) run twice per engine gave identical labels and segments (2 of 2
each).

## Reading it

- **Sortformer v2 (CC BY 4.0) is close to the shipped v2.1 on what the screen shows.** On AMI the difference
  includes zero (−1.0, −3.2 to +1.0). On CHiME-6 it is 2.3 points worse (+0.9 to +3.8), mostly missed speech, and
  it leaves more lines unlabelled (13.8% vs 7.5%). Monologue splitting and first-label time are the same.
- **NVIDIA's 10-point gap between v2 and v2.1 does not show on this path.** NVIDIA reports AMI test DER 31.3% (v2) vs
  20.6% (v2.1) at 1.04 s latency; here the bare v2 model is *better* on AMI (−3.4) and worse on CHiME-6 (+7.6). Our
  setup differs (no collar, word-level reference, the app's FIFO 40 config, AMI's dev meetings held out), and we have
  not found why the order flips on AMI. Read it as "v2 is not clearly worse on meetings here", not "v2 is better".
- **sherpa-onnx, untuned, is not a candidate as run.** With its example clustering threshold (0.5) it finds about 44
  speakers in a 4-person AMI meeting (confusion 50 points) and 7 in a 4-person CHiME-6 window. That is a tuning
  problem, not proof the approach fails, but the threshold can only be set on the calibration recordings, which this
  comparison keeps off-limits. It is also offline: it needs the whole recording before labelling anyone, so its
  first-label time means nothing and it can't run live as it stands.
- **Speed and memory here say nothing about phones.** They are a 2012 desktop CPU shared with another job.
  Recogment's fp32 ONNX took about 0.9 s per 0.48 s step (0.25–0.30× real time) and 820–840 MB; real time on Android
  would need a quantised build or an NPU/GPU delegate, and a measurement on a phone. First-label times are not
  affected: the replay runs on audio time, so they measure the streaming config, not CPU speed.

Full numbers: `speaker-android-<engine>-<set>.json` (scores, per recording) and `.paired.json` (differences).
