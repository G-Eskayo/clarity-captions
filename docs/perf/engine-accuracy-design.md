# Engine accuracy test: design (#145)

Design for #145 "[E] Engine accuracy test on the Mac: compare speech engines on accented conversations with
checked transcripts". Results go in [`engine-accuracy-comparison.md`](engine-accuracy-comparison.md), which the
scorer regenerates after every cycle.

## Question

Does any on-device engine follow accented conversational English better than Apple's SpeechAnalyzer, and by how
much? Measured as word error rate (WER) per engine and per accent, with confidence intervals, plus speed.

## Patterns reused

- **Opt-in harness shape** from `SpeakerModelComparisonTests` / [`speaker-model-comparison.md`](speaker-model-comparison.md)
  (ADR 0017): the engine run is opt-in behind an environment variable (`CAPTION_ENGINE_EVAL=1`), never part of the
  default `swift test`; result lines carry a fixed prefix (`ENGINE-EVAL-RESULT`); the results doc lives in
  `docs/perf/`.
- **WER and targets** from `docs/testing/test-plan.md` §3 and the targets table: WER = (S + D + I) / N, 15% or less
  is good, 30% or less is acceptable.
- **Speech asset install**: the Apple engine installs its en-US model through CaptionCore's `SpeechModelInstaller`
  (the same AssetInventory path the app uses), and uses the app's `SpeechTranscriber` options (`fastResults`, no
  transcription options), taking only final results.
- **No shipping dependency**: WhisperKit and the engine runner live in a separate package, `Packages/EngineEval`,
  which the app project never references. FluidAudio is already a CaptionCore dependency (ADR 0002 / 0008).

The ticket suggested putting the engines behind `CaptioningEngine`. That protocol is shaped for the live
microphone (start/stop, sound labels, audio levels), so the harness uses a narrow file-input protocol,
`FileTranscriber` (`load()`, `transcribe(url) -> text`). The model is the same either way; files make runs
repeatable.

## Dataset

EdAcc (Edinburgh International Accents of English Corpus), Hugging Face mirror `edinburghcstr/edacc`, test +
validation splits: 19,137 segments, 32.7 hours, 32 accent groups, 122 speakers, human transcripts. License and
provenance are in the evidence log (E9). The audio is never committed (ignore rules in `.gitignore`) and never
appears on a public page.

Excluded before running: segments whose transcript is `IGNORE_TIME_SEGMENT_IN_SCORING` (123), and segments whose
reference is empty after normalization (1,485 tag-only or filler-only segments such as `<NO-SPEECH>`, `<DTMF>` or a
lone "mm"). That leaves **17,529 segments, 31.5 hours, 32 accents, 122 speakers**. Long segments (641
over 30 s, the longest 9 minutes) stay in: real conversations are long, and every engine handles long input.

## Machines and engines

| Machine | Holds | Runs |
|---|---|---|
| 2012 Mac mini (Kali, i7, 16 GB) | the whole corpus, every shard, all results | shard maker, **sherpa-onnx** (Parakeet TDT 0.6B v2, int8 ONNX, CPU), scorer, report |
| M4 Mac mini (macOS 26) | one shard at a time, the Apple-side models | **SpeechAnalyzer** (en-US), **Parakeet via FluidAudio** (v2 English and Ultra), **WhisperKit** (large-v3 turbo) |

FluidAudio 0.17.5 offers Parakeet v2 (English), v3, Redux, Ultra and Phonon-2, plus TDT-CTC-110M and Japanese. The
harness runs **v2** (FluidAudio's English recommendation; the same weights sherpa-onnx runs, so the pair also shows
how much the runtime matters) and **Ultra** (FluidAudio's recommended successor to v3).

## Shards

The shard maker decodes each segment (32 kHz WAV in the parquet files), resamples to 16 kHz mono 16-bit WAV
(polyphase, `scipy.signal.resample_poly`), and assigns segments to shards **stratified by accent**: within each
accent, segments are sorted by clip id and dealt round-robin across shards. Every shard is a small sample of the
whole corpus, so shard 1 already gives a (noisy) per-accent table. Shard count = ceil(total hours / target hours),
target 1 hour: **32 shards** of about 548 segments (about 115 MB of audio each).

Each shard is a directory: `audio/<clip_id>.wav` and `manifest.jsonl`, one line per clip:
`clip_id, file, split, speaker, accent, l1, gender, reference, audio_seconds`. Clip ids are
`<split>-<source file stem>` and must be unique; the shard maker refuses duplicates.

## Cycles (the M4 driver)

A sequential loop, never a timer that polls:

1. `rsync --checksum` the next shard from the 2012 box.
2. Run every Apple engine on every clip, `--repeats N` times (engine by engine, so one model is in memory at a time).
3. `rsync` the shard's result file back to the 2012 box.
4. The 2012 box re-scores everything so far and rewrites the report; the driver copies the report back.
5. Delete the shard's audio. Next shard.

sherpa-onnx runs the same shards on the 2012 box with its own sequential loop.

**Resumable.** Each run appends one JSON line per (clip, engine, repeat): `clip_id, shard, accent, engine, model,
engine_version, repeat, hypothesis, audio_seconds, processing_seconds, host, finished_at`. The line is flushed
before the next clip starts. On restart the runner reads the file, skips every (clip, engine, model, repeat)
already present, and ignores a corrupt or truncated last line (a crash mid-write). The scorer de-duplicates on the
same key (first line wins) and skips corrupt lines.

**Repeats.** Shard 1 runs 5 repeats on every engine and the report includes a determinism table: for each engine,
the share of clips whose raw text was identical across all repeats, and the WER spread across repeats. The owner
picks the repeat count for the remaining shards after seeing shard 1.

**Visibility.** The driver writes a status file (shard k of n, clips done, engine, ETA) after every clip, and a
Terminal window on the M4 tails it while the run is going. The run is started with `nohup` through a wrapper
script that exports its own environment, so it survives the session that started it.

## Scoring

**Normalizer**, applied identically to every engine's text and to the reference:

1. Unicode NFKC, lowercase (casefold), strip diacritics (the corpus has `Hạ LONG`, `CAFé`).
2. Drop EdAcc annotation tags (`<laugh>`, `<overlap>`, `<foreign>`, `<no-speech>`, `<dtmf>`, ...) and engine
   non-speech markers in brackets or parentheses (`[Music]`, `(laughs)`).
3. Symbols: `&` -> and, `%` -> percent, `$`/`£`/`€` amounts -> "N dollars/pounds/euros".
4. Numbers to words, because EdAcc spells numbers as spoken (`C FOURTEEN DASH P ONE`): integers, decimals
   ("point"), ordinals (`1st` -> first), letters glued to digits split (`c14` -> c fourteen). Four-digit numbers
   1100-1999 read as years ("nineteen ninety"); others as cardinals ("two thousand five").
5. Contractions: expand the unambiguous ones (`n't` -> not, `'re` -> are, `'ve` -> have, `'ll` -> will, `'m` ->
   am, `can't` -> can not, `won't` -> will not, `cannot` -> can not). Keep `'s` and `'d` (is/has/possessive,
   had/would are ambiguous), then drop all apostrophes on both sides.
6. Hyphens and other punctuation become spaces.
7. Filler words removed: um, umm, uh, uhh, uhm, er, erm, hm, hmm, hmmm, mm, mmm, mhm, mhmm. They are frequent in
   EdAcc (uh 5,906, um 3,637, mm 1,609, hmm 1,213) and engines differ in whether they write them; captions don't
   need them. "Oh", "ah", "yeah" stay (they carry meaning).
8. A short list of spelling and form variants mapped to one form (`ok` -> okay, `alright` -> all right,
   British -our/-ise/-re spellings -> US).

Known residual mismatches, accepted and small: "dash" spoken in the reference vs a hyphen written by an engine,
years like "twenty twenty" vs `2020`, "one hundred and five" vs `105`.

**WER** = (S + D + I) / N per engine x accent and overall, via word-level Levenshtein alignment, pooled (total
errors over total reference words, not a mean of per-clip rates). Parakeet via FluidAudio refuses clips shorter
than 1 s (4,868 of 17,529 segments, mostly "yeah" and "mm"), so the harness pads those with trailing silence to
1 s for Parakeet only; silence adds no words. Only clips that every engine finished are
compared, so every engine is scored on the same words. The primary score uses repeat 1.

**Confidence intervals**: 95% percentile bootstrap, 1,000 resamples, resampling **speakers** (not clips) within
each cell, because one speaker's segments are correlated. Cells with fewer than 3 speakers are flagged.

**Speed**: real-time factor = processing seconds / audio seconds over all repeats (lower is faster), also shown as
"x real time" (audio / processing). Processing time excludes model loading.

## Engines after shard 1

**WhisperKit was dropped after shard 1** (owner, 2026-10-21): it was the slowest (12x real time on the M4) and the
least accurate (23.5%, 19.8% with its no-speech filter off), and it is Apple-only, so it gives no path to Android.
Its shard 1 rows stay in the report, marked, and scored on shard 1 only; dropped engines never shrink the set of
clips the remaining engines are compared on. Counterpoint: Whisper was the only multilingual engine tested, so it
may come back for the non-English / live-translate work. That would be a separate test, with Parakeet v3 as the
other multilingual candidate. Shards 2-32 run Apple, Parakeet v2, Parakeet Ultra and sherpa-onnx, one run per clip.

**One clip sherpa-onnx can't take:** `test-EDACC-C34-9` (about 9 minutes, the longest segment) exceeds the offline
Parakeet ONNX model's maximum input length, so sherpa-onnx errors on it and the full comparison covers 17,528 of
17,529 clips. A chunked decode would fix it; one clip doesn't move any result.

## Live latency

Added 2026-10-21 at the owner's request: "how fast are the words correctly generating after they have been said?"
Real-time factor on files doesn't answer that, so a second, smaller run feeds audio as if live.

- **Sample:** shard 1 (already accent-stratified, about 1 hour), clips up to 30 s (the growing window below
  re-decodes the whole clip, and 30 s is Whisper's window). Not the full corpus.
- **Clock:** seconds since the clip's first sample was fed, the same reference as the app's `FedWallTime` /
  `CaptionUpdate.lagSeconds` (`TranscriptionEngine.swift`, `WordLagTracker`, `docs/perf/caption-latency-baseline.md`).
  The app's lag measures when the recognizer's own word end-times show up; this one also requires the word to be
  *right*.
- **Apple SpeechAnalyzer** streams natively: fed in real time in 100 ms buffers with the app's options
  (`volatileResults`, `fastResults`), model prepared before the first buffer (as the app does). The text on screen
  after each result follows the app's rule: finals accumulate, the latest volatile result replaces the tail.
- **Parakeet (FluidAudio) and WhisperKit** aren't streaming in a form the app would use. FluidAudio 0.17.5's
  `SlidingWindowAsrManager` only emits once 11 s of chunk plus 2 s of right context exist (a 13 s floor), so both
  use the **standard growing window**: re-decode all audio heard so far, starting the next decode as soon as the last
  one finishes and at least 0.5 s of new audio exists. This is simulated, not waited out: a decode starting at time t
  sees audio up to t and its text appears at t + the measured compute time (`GrowingWindow.simulate`, unit-tested).
  Fresh decoder state per decode.
- **When each word was said:** EdAcc gives segment bounds, not word times. Word times come from Parakeet TDT v2's
  offline token timestamps (TDT predicts token durations, so its times are acoustic, typically within one 80 ms
  frame), aligned to the reference words by minimum edit distance; reference words without a timed partner are
  spread evenly over the gap between their neighbours. Forced alignment with a separate aligner (e.g. wav2vec2/MMS)
  would be more neutral but adds a PyTorch stack for a small gain at this resolution. Caveat: Parakeet is measured
  against its own timing engine.
- **Metrics:** *time to correct word* = time of the first update in which the word is aligned correctly, minus the
  time it ended; only words that are right in the final text count. *Time to first text* = first non-empty update
  minus the end of the first spoken word. Median and p95 per engine.
- **Mac, not iPhone:** these run on the M4 Mac mini. The ranking should carry over; absolute numbers need a phone
  check later.
- **Load check:** midway through the Apple run the M4's engine processes were reniced to +15 so other work could
  run. Re-running Apple on the first 60 clips at nice +15 gave the same latency to the hundredth of a second (median
  0.655 s, p95 1.50 s in both runs), so the renice didn't change the numbers.
- **sherpa-onnx** runs the same growing window in Python on the M4 (`edacc_eval.latency.growing_window`, the same
  semantics as Swift's `GrowingWindow.simulate`, both tested), against the same reference word times and the same
  526 clips, with 8 threads.

## Sharing sherpa-onnx between the minis

sherpa-onnx is the slowest engine on the 2012 mini (real-time factor 0.37, about 12 hours per full pass), so the M4
can take sherpa-onnx shards once its own engines finish. Both machines can pull from one queue on the 2012 mini:
`claims/shard-NNN/` is created with `mkdir` (atomic), first come first served; a host restarting takes back its own
unfinished claim first; `done` marks completion (`linux-claim.sh`, `claims.py`, tested). Result lines record the host
and the speed table splits by machine.

**Cross-machine check (shard 1, 548 clips, repeat 1):** the same sherpa-onnx (1.13.8) and model (Parakeet TDT 0.6B
v2 int8) gave identical text on only 426 clips (77.7%; 93 differ after normalizing). Thread count is not the cause
(4 and 8 threads on the M4 are identical on all 548); the arm64 and x86-64 ONNX Runtime kernels round differently and
greedy decoding flips some words. The WER is the same to 0.04 points (16.34% M4, 16.37% 2012), so mixing would not
move the score, but the results are not bit-identical. Since the M4 also runs sherpa-onnx about 12 times faster
(31x real time with 8 threads, vs 2.7x), **the M4 runs all sherpa-onnx shards** and the 2012 mini keeps the corpus,
the shards, the queue and the scoring. The 2012 mini's shard 1 run is kept in `check/` as the x86 Linux reference
(deterministic across repeats, 2.7x real time on an Ivy Bridge i7), which also feeds #43's Android question.

## Size options (#150)

The published Ultra encoder is int8 linear per channel (FluidAudio / mobius recipe), so it is the 8-bit option.
Smaller builds re-compress the fp16 encoder exported with FluidInference/mobius (`export_encoder_fp16.py --name
ultra`, iOS 18 target) using `scripts/engine-eval/compress_parakeet.py`: data-free k-means palettization, per grouped
channel (group 16, iOS 18+), 6-bit and 4-bit, encoder only; the other components are the published ones and each
folder carries a NOTICE with the CC BY 4.0 attribution. FluidAudio's published small builds (v3 int4, Redux) run
alongside. Each build gets the full 32-shard accuracy run, the 526-clip latency sample and a process memory
footprint (`engine-eval memory`); sizes are whole folders on disk and deflate-zipped (`edacc_eval.sizes`).
`m4-compression.sh` chains it; the export needs about 10 GB of scratch disk, so it ran on the MacBook in a Python
3.12 env (the mobius Python 3.10 lock's scipy doesn't load on macOS 27) and the folders were copied to the M4.
k-means palettization with a worker pool crashed ("Pool not running"); one worker works (about 10 minutes per variant).

## Complexity

- Shard maker: one pass over the corpus, O(clips) time, streams one parquet file at a time (memory bounded by
  one file, about 700 MB).
- Runner: O(clips x engines x repeats) transcriptions; resume reads the shard's result file once, O(lines).
- Scorer: O(total result lines + words^2 per clip for alignment) per cycle; it rebuilds from all result files each
  cycle (32 cycles), which is a few seconds per cycle at this corpus size. Bootstrap is O(B x speakers) per
  cell over precomputed per-speaker error counts.
- Disk: 2012 box about 6.5 GB corpus + about 4 GB shards; M4 holds one shard (about 115 MB) plus models (about
  3 GB).

## Running it

Tests (no network, temp dirs only):

```bash
cd scripts/engine-eval && python3 -m pytest          # normalizer, WER, shards, resume, report
swift test --package-path Packages/EngineEval --filter EngineEvalKitTests
CAPTION_ENGINE_EVAL=1 swift test --package-path Packages/EngineEval --filter EngineAccuracySmoke  # opt-in, downloads models
```

The corpus run, once the shards exist on the 2012 mini (`python -m edacc_eval.cli build-shards`):

```bash
# M4 mini, from the repo worktree: Apple-side engines on shards 2..32 with N repeats, then sherpa-onnx on the
# same shards from the shared claim queue (nohup, nice +15, Terminal window, resumable)
EVAL_SHERPA=1 EVAL_SHERPA_FIRST=2 EVAL_SHERPA_LAST=32 EVAL_SHERPA_REPEATS=N scripts/engine-eval/m4-launch.sh 2 31 N
# Optional, not recommended (x86 text differs, see above): the 2012 mini also works the sherpa queue
~/edacc-eval/tool/linux-sherpa-launch.sh 2 32 N
# One shard's extras (cross-machine check, extra engines, latency sample)
EVAL_DRIVER=m4-shard-extras.sh scripts/engine-eval/m4-launch.sh K 1 1
```

Rerunning either command after a stop resumes where it left off. The live report is
`~/edacc-eval/report/engine-accuracy-comparison.md` on both minis; it is copied into the repo by a commit, never
written into a checkout by the drivers (that would block `git pull` on the M4). Progress: `~/edacc-eval/status.txt` and
`status-engine.json` on the M4, `~/edacc-eval/sherpa-status.json` on the 2012 mini; logs in `~/edacc-eval/logs/`.

## Not in this ticket

Picking the winner and the physical iPhone test follow the full run. Fine-tuning an engine on accented speech and
an accent picker are later tickets (#36, #37).
