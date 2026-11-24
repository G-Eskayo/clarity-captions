# Car-call test set, first score: Parakeet Ultra vs Apple SpeechAnalyzer (#303, part of #302)

**Date:** 2026-11-23 · **Host:** M4 Mac mini, silent file processing only · **Set:** 30 pairs, 210 clips, 44 min
of audio · **Codec:** G.711 μ-law (this ffmpeg has no AMR-NB) · **Seed:** 303 · **How:**
[`scripts/engine-eval/car_call/`](../../../scripts/engine-eval/car_call/README.md)

## What was measured

There are 30 caller clips, one per speaker, each 6–15 s with at least 12 words. They come from EdAcc shard 001,
the accuracy set the engine scoreboard uses, with its references. Each caller is paired with an in-car talker:
a 2.5–6 s clip from a different conversation, never reused. Each pair is heard seven ways: the caller's clip
untouched (`clean-far`), the in-car clip untouched (`clean-near`), the caller through the call and car speaker
only (`phone`), and the full scene at 20, 10, 5 and 0 dB SNR. The full scene is the call, a 0.4 s pause, then
the in-car talker answering 6 dB louder, all over synthetic road noise. SNR is caller over road noise at the
phone's mic, so the in-car talker is always 6 dB cleaner than the caller.

Each engine transcribes every scene in one pass, on the bare engine with whole files (`engine-eval run`). The one
hypothesis is aligned against both references, and each error is charged to the voice it hits. Every condition
has 837 reference words for the caller and 387 for the in-car talker. Brackets are 95% bootstrap intervals over
pairs.

## Results

Word error rate. **Far** is the caller, the voice she lost. **Near** is the person in the car.

| Condition | Apple far | Apple near | Parakeet Ultra far | Parakeet Ultra near |
|---|---|---|---|---|
| clean (baseline) | 13.0% (9–18) | 23.5% (15–34) | **9.2%** (6–13) | 17.6% (11–26) |
| phone line + car speaker, quiet | 20.0% (15–26) | – | **13.7%** (10–18) | – |
| + road noise 20 dB + in-car talker | 21.9% (17–27) | 24.3% (16–34) | **15.5%** (11–21) | 22.0% (14–32) |
| 10 dB | 26.3% (20–32) | 26.1% (17–37) | **19.7%** (14–26) | 19.4% (12–29) |
| 5 dB | 30.5% (24–38) | 26.9% (18–37) | **18.9%** (14–25) | 19.9% (12–29) |
| 0 dB | 34.4% (27–41) | 27.1% (19–37) | **21.6%** (17–27) | 25.1% (16–36) |

The baseline row's "near" is the in-car clips heard on their own (`clean-near`). Those are short clips, which
is why their WER is higher than the callers'.

Where the caller's errors come from (substitutions / deletions / insertions, out of 837 words):

| Condition | Apple | Parakeet Ultra |
|---|---|---|
| clean | 69 / 30 / 10 | 50 / 15 / 12 |
| phone | 124 / 35 / 8 | 85 / 12 / 18 |
| 20 dB | 118 / 50 / 15 | 92 / 26 / 12 |
| 10 dB | 146 / 54 / 20 | 113 / 27 / 25 |
| 5 dB | 166 / 75 / 14 | 121 / 20 / 17 |
| 0 dB | 187 / 83 / 18 | 130 / 32 / 19 |

## What it suggests

1. **The phone line alone costs about half again.** Narrowband plus a car speaker, with no noise and no second
   talker, takes Parakeet Ultra from 9.2% to 13.7% and Apple from 13.0% to 20.0%. Hypothesis 1 in #302
   (narrowband) is real for both engines, and it's mostly substitutions: words heard wrong, not dropped.
2. **Road noise and the second talker take the caller to 22% (Parakeet) and 34% (Apple) at 0 dB**, about 2.3x and
   2.6x their clean rates. Apple's deletions almost triple (30 to 83): it drops the caller's words, and missing
   words are the worst failure for her.
3. **Parakeet Ultra beats Apple on the caller in every condition.** The intervals overlap at 20 dB and separate
   from 10 dB down. The in-car talker is about the same on both engines (around 20–27%), with Parakeet slightly
   ahead.
4. **The simulation is gentler than what happened.** 16–22% WER for Parakeet is poor, but it's not "couldn't stay
   connected". Things this set leaves out probably account for the rest: AMR-NB instead of μ-law, real speaker
   distortion and cabin noise, the two talking over each other, the app's live streaming path and speaker labels
   (#273), and a possible silent switch to Apple's engine after a memory warning (#284). At 0 dB, Apple's numbers
   (34%) are much nearer "couldn't follow" than Parakeet's.

**Next step (no fix chosen yet):** check #284 against the session first. If her phone was on Apple's engine, the
gap between the two columns explains a lot. Then make the real consented recording (#302 step 3) and score it on
the live path. To this set, add overlapping speech and an AMR-NB build of ffmpeg, so the synthetic numbers can be
checked against that recording. Telephone-band training for the fine-tune (#272) waits until those numbers are in.

## Limits

- This is the bare engine on whole files, not the app's live path. Speaker-label accuracy (Sortformer) isn't
  scored here.
- The noise, car speaker and cabin are synthetic, and the codec is G.711 μ-law, not AMR-NB, so these numbers are an
  optimistic bound for a narrowband call. HD Voice isn't modelled. The talkers take turns and never overlap.
- There are 30 pairs, all from one shard. Only the large gaps are firm.

## Sources and credit

Speech: EdAcc (Edinburgh International Accents of English Corpus), the clips and references the engine accuracy
comparison already uses (`docs/perf/engine-accuracy-design.md`). Road noise, car speaker and cabin response are
generated by `car_call/chain.py`. No recorded noise or impulse responses were used. Transcription ran on our own
engines only: Parakeet Ultra through FluidAudio, and Apple SpeechAnalyzer (macOS 26.5.1).

To reproduce: `CC_REPO=<worktree> scripts/engine-eval/car_call/run.sh`.
