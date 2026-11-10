# Speaker scoreboard: design (#271)

The test every Sortformer build must pass before it can replace the shipped fp16 model. It replaces the synthetic
`say` voices of [speaker-model-comparison.md](speaker-model-comparison.md), which can't resolve a half-point DER change.
Results: [speaker-scoreboard.md](speaker-scoreboard.md). Corpus choice and licences: evidence
`2026-11-09-speaker-test-corpora-and-their-licences`.

## What is scored: the app's path, not the bare model

`SpeakerPathReplay` (CaptionCore) streams a recording through the real `LiveDiarizer` in the app's buffers (4096
frames at 48 kHz = 1365 samples at 16 kHz, about 85 ms) and labels every caption result with a session
`SpeakerLabelSmoother` against the segments the diarizer had at that moment, the same call
`TranscriptionEngine.makeResultStream` makes. Same schedule as `SpeakerStabilityReplayTests` (#91): a live result
for the line being spoken every 0.5 s, its final 1.0 s after the line ends. The plain-overlap slot from
`SpeakerAligner` (what face to face uses) is recorded beside it.

The captions themselves come from the reference, not a speech engine, so the score is the speaker path alone (the
engine's own timing is #273's whole-system replay). The screen shows one line at a time, so the reference becomes
one stream of lines (`speaker_eval/reference.py`): a speaker's speech joined across pauses under 0.5 s; whoever
started talking most recently holds the line; lines over 10 s are cut into equal parts. Someone talking underneath
another person's line has no line of their own, so even perfect labels miss overlapped speech: the **floor** row
gives every line its true speaker and shows how much of the DER only the one-line screen causes.

engine-eval runs one process per recording, so peak memory is per recording. The diarizer is drained after every
buffer (labels from a diarizer that keeps up); the per-buffer time shows whether it would.

## Corpora and the split (fixed once, before any result)

`scripts/engine-eval/speaker_eval/speaker_split.json`. Calibration recordings are only for calibrating compressed
builds in step 2. The scorer refuses them (`CalibrationLeak`), and `phrases` only writes lines for test recordings,
so they can't be run by the driver either.

| Set | Test (scored) | Calibration (never scored) | Why |
|---|---|---|---|
| **AMI**, Array1-01 far-field mic, CC BY 4.0 | 16 test meetings, 9.1 h, 4 people (one meeting 3) | 18 dev meetings | Standard benchmark, real overlap, long presentations; dev and test share no speakers; Sortformer trained on AMI train only |
| **CHiME-6**, one Kinect array per window, CC BY-SA 4.0 | eval sessions S01, S21 as 31 ten-minute windows, 5.2 h | dev sessions S02, S09 (27 windows) | Dinner parties in real homes: the noisy room; not in Sortformer's training data |

The two sets are scored separately and never pooled: AMI's reference is word-level (pyannote `only_words`),
CHiME-6's is utterance-level, so their DER levels don't compare. Builds compare with builds within a set.

CHiME-6 windows: each session is cut into 600 s windows (a remainder under 300 s joins the last), each replayed as
its own app session. A window is heard by channel 1 of the array CHiME-6 names as the reference for most of its
utterances (the room most of the talking is in). Talk in other rooms stays in the reference as missed speech, as in
the CHiME-6 diarization track. Only 8 people across the test windows: the CI is over windows, not people, so it is
narrower than a people-level CI would be.

## Measures

- **DER on screen** (primary): missed + false alarm + confusion over reference speech, overlap counted per speaker,
  no collar, 10 ms frames, best one-to-one label mapping (`speaker_eval/der.py`). Hypothesis: each line's final
  label over the line's span. Also for the plain-overlap slot, the bare model's segments and the floor.
- **Speaker-count error**: labels left in the transcript against people who spoke; mean absolute and exact matches.
- **Monologue split rate** (#91): a speaker's own speech joined across pauses under 2 s spanning at least 20 s
  (backchannels from others don't break it); split if its lines carry two or more labels.
- **Time to first label**: per line, audio time of its first labelled result minus the line's start (median, p90);
  and the session's first label. Audio time, so it reflects the model's context, not the Mac's speed.
- **Speed and memory**: real-time factor, per-buffer processing time (85 ms of audio each), the kernel's lifetime peak
  physical footprint (model load included; Neural Engine memory held by system daemons is not counted), load time.
- **Determinism**: every recording runs twice; the report counts runs whose labels and segments differ.

95% CIs: percentile bootstrap over recordings (meetings for AMI, windows for CHiME-6), 1,000 resamples, seed 271:
the #145/#150 method with the recording as the resampled unit.

## Step 2 decision rule (from the ticket, applied later)

A compressed build ships only if its DER-on-screen CI overlaps fp16's on **both** sets and its line first-label
latency is within 10% of fp16's. Because every build runs on the same recordings, step 2 also reports a paired
bootstrap of the DER difference (build minus fp16, same resamples), which is tighter than comparing two intervals.

## Running it

```bash
# 2012 mini (Kali): AMI audio + reference, CHiME-6 tarball + transcripts (see the evidence entry), then cut windows:
python3 -I chime6-cut.py ~/chime6-eval/dl/CHiME6_eval.tar.gz ~/chime6-eval/windows.json ~/chime6-eval/windows
# M4 Mac mini, from a worktree with the model fetched (scripts/fetch-diarizer-models.sh):
EVAL_REPO=$PWD MODEL=$PWD/Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc LABEL=fp16 SET=ami scripts/engine-eval/m4-speakers.sh
cd scripts/engine-eval && python -m speaker_eval.cli score --set ami --model fp16 --rttm-dir ~/ami-eval/rttm \
  --uem-dir ~/ami-eval/uem --results ~/ami-eval/results --meta ~/ami-eval/report/meta-fp16.json \
  --out-md ~/ami-eval/report/fp16.md --out-json ~/ami-eval/report/fp16.json
```
