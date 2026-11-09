# Speaker scoreboard: results (#271)

How the bundled Sortformer speaker model scores on real voices, through the app's own live speaker path. Method,
corpora and the frozen calibration/test split: [speaker-scoreboard-design.md](speaker-scoreboard-design.md). Full
numbers, per recording: [AMI JSON](speaker-scoreboard-fp16-ami.json), [CHiME-6 JSON](speaker-scoreboard-fp16-chime6.json).

**Status (2026-11-09):** fp16 baseline scored (step 1). The 8- and 6-bit builds (step 2) wait for this baseline to be
merged, and the model-licence question on #271 is still open.

Build scored: the shipped `Sortformer_v2.1.mlmodelc` (FluidInference v3/fp16, Hugging Face revision `ae9a27ab45dc`,
tree sha256 `20fec6d02bf0764c`), 229.4 MiB on disk, 210.5 MiB zipped, app config `SortformerConfig.default` (= fastV2_1
streaming: chunk 6, right context 7, FIFO 40). Mac mini M4, each recording run twice, one process per run.

## fp16 baseline

95% CIs: percentile bootstrap over recordings (AMI meetings, CHiME-6 windows), 1,000 resamples, seed 271. The two sets
are never pooled: their references differ (word level and utterance level), so levels don't compare across sets.

| Measure | AMI test, 16 meetings, 9.1 h | CHiME-6 eval, 31 windows, 5.2 h |
|---|---|---|
| **DER on screen** (live path, final labels) | **24.0%** (20.4%–27.3%) | **42.5%** (38.5%–46.3%) |
| of which missed / false alarm / confusion | 14.9% / 0.0% / 9.1% | 32.5% / 0.7% / 9.3% |
| DER, plain-overlap slot (SpeakerAligner, face to face) | 23.9% (20.4%–27.1%) | 42.1% (38.1%–46.0%) |
| DER, bare model segments | 36.2% (32.3%–39.8%) | 42.4% (39.1%–45.8%) |
| Floor: every line given its true speaker | 14.6% (10.3%–18.8%) | 31.4% (27.5%–35.5%) |
| Speaker count, mean abs error / exactly right | 0.06 (0.00–0.19) / 15 of 16 | 0.00 / 31 of 31 |
| Long monologue (≥20 s) split across two labels | **37.6%** (30.2%–46.2%) of 383 | **65.4%** (55.9%–74.9%) of 153 |
| **Line's first label**, median / p90 after it starts | **0.62 s** (0.60–0.63) / 1.39 s | **0.63 s** (0.62–0.65) / 1.45 s |
| Lines never labelled | 2.9% | 7.5% |
| Session's first label, median / worst | 1.52 s / 10.4 s | 1.54 s / 11.3 s |
| Speed (audio ÷ wall time) | 22× real time (see below) | 22× real time |
| Per 85 ms buffer, worst recording's p95 / max | 183 ms / 2.0 s (busy machine, see below) | 41 ms / 385 ms |
| Peak memory while streaming / lifetime incl. load | about 120–135 MB / up to 287 MB | about 120–135 MB / up to 287 MB |

Step 2's ship rule, against these numbers: a compressed build's DER-on-screen CI must overlap **20.4%–27.3%** (AMI)
and **38.5%–46.3%** (CHiME-6), and its line first-label median must be within 10% of 0.62 s / 0.63 s (at most
**0.68 s** / **0.69 s**). Step 2 also reports the paired difference (build minus fp16 on the same resamples).

## Reading it

- **On screen beats the bare model on AMI because it can't raise false alarms.** The caption lines come from the
  reference (the score is the speaker path alone, not the speech engine), so the screen labels only speech that
  happened: false alarm is about 0 by design. Its error is mostly missed overlap (one line on screen at a time:
  someone talking underneath another person's line has no line of their own) plus confusion. The bare-model row is
  the model alone against every frame and is the row to compare with published numbers. Builds are compared with
  builds on the on-screen row.
- **The one-line screen sets a floor.** Even perfect labels leave 14.6% (AMI: overlapped speech) and 31.4%
  (CHiME-6: overlap, plus talk in other rooms that stays in the reference). Above the floor, the model and the smoother
  add about 9 points on AMI (24.0% − 14.6%) and 11 on CHiME-6 (42.5% − 31.4%).
- **Smoothing barely changes DER** (24.0% vs 23.9% plain overlap). It's there for labels that don't flicker while
  you read (#91), which DER doesn't measure. The monologue split rate is the measure for that, and it's the clearest
  weakness: one in three long AMI monologues, and two in three CHiME-6 ones, end up under two labels.
- **CHiME-6 is the hard room**, and not in Sortformer's training data (AMI's training meetings are). Most of its
  error is the floor (missed speech: 32.5 of 42.5 points). Its speaker-count row is perfect only because every window
  has four people in the reference and the model has four slots.
- **Sanity check against published numbers.** NVIDIA reports AMI test (SDM) DER 20.6% for Sortformer v2.1 at 1.04 s
  latency; FluidAudio's own benchmark of this CoreML conversion gives 26.4% on AMI SDM (streaming, high context,
  0.25 s collar) and 26.5% on IS1009a. Our bare-model 36.2% (IS1009a 29.1%) is higher, as expected: no collar (a
  0.25 s collar usually removes several points), the word-level reference, and the app's lower-latency FIFO 40 config.
  Same order, no sign the harness is broken; not a like-for-like comparison.

## Repeat runs and a labelling bug (#275)

The model itself is deterministic: its segments were identical in all 47 repeat pairs. The labels were not: every
pair differed somewhere. `SpeakerLabelSmoother` and `SpeakerAligner` pick a slot with `max` over a dictionary, and in
overlapped speech two slots cover a caption equally, so the tie goes to Swift's per-process random dictionary order.
Usually a few labels per recording; in three CHiME-6 windows an early tie renumbered two people for the whole session.
The effect on the scores is a rounding error: scoring repeat 2 instead of repeat 1 moves live DER by 0.01 points
(AMI 23.98% both, CHiME-6 42.49% vs 42.48%), against CIs about 7 points wide, so it doesn't blur step 2. It is still a
bug (the same audio should get the same labels), filed as #275 (Speaker labels: equal overlap is broken by random
dictionary order) with a fixed tie-break order. Not fixed here: it changes app behaviour, and this PR scores the app
as shipped. When it lands, rerun the baseline once (expected: 0 repeats differing, DER unchanged).

## Speed and memory notes

- **AMI speed:** the report's total is 13×, pulled down by IS1009c and IS1009d, which both ran at 3–4× real time
  back to back while the Mini was busy with other work (both repeats, about 35 minutes; every other meeting ran
  18–25×). Re-run alone on a quieter machine they took 80 s and 86 s (23×, labels the same apart from the #275 ties).
  With those two re-timed, AMI is **22×**, matching CHiME-6. The per-buffer worst cases (183 ms p95, 2.0 s max) come
  from the same busy window. Speed isn't in step 2's ship rule; step 2 runs fp16 again beside each build so speeds are
  compared under the same load.
- **Memory:** the kernel's lifetime peak includes a one-off spike while Core ML prepares the model (seen on some first
  runs: TS3003a 287 MB on run 1, 138 MB on run 2). While streaming, the footprint stays about 120–135 MB. Neural
  Engine memory held by system daemons isn't in the process footprint, so this understates the device's total.

## Follow-ups (not in this PR)

- #275: the tie-break fix above.
- The app runs Sortformer at FIFO 40 (fastV2_1); NVIDIA's published number is at 1.04 s latency. Whether a different
  streaming config buys DER for latency is a separate measured question, scored on this board.
- The licence question on #271 (NVIDIA Open Model License vs our CC BY 4.0 credit) is with Gil and blocks step 2's
  builds shipping, not the baseline.

## Reproduce

[speaker-scoreboard-design.md § Running it](speaker-scoreboard-design.md#running-it). Results land in
`~/ami-eval/results` and `~/chime6-eval/results` on the M4 Mini (`<recording>.fp16.r<n>.json`); the reports above come
from `speaker_eval.cli score` over repeat 1, with the repeats compared for the determinism row.
