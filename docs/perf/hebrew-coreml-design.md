# Hebrew zipformer on Core ML: conversion, compression and scoring (#220)

Method behind [`hebrew-coreml-comparison.md`](hebrew-coreml-comparison.md). It follows #217
([`hebrew-accuracy-design.md`](hebrew-accuracy-design.md)), which found the ivrit.ai 66M streaming zipformer tied
with Parakeet-He on Hebrew conversation and about a quarter of Apple's character errors.

## What the owner asked (2026-10-30)

- Hebrew captions switch to Seal's own engine and ship bundled on every device (iPhone, iPad, Duo, Mac).
- Smaller than the 75 MB sherpa-onnx build: Core ML palettized 6-, 4-, 3- and 2-bit encoders, each scored on
  eval-d1 and eval-whatsapp with 95% intervals.
- Recommend the smallest build whose CER interval still overlaps int8's and still beats Apple by a wide margin, with
  its first-word and steady latency. The owner picks, as a Decision.

## The model

[`ivrit-ai/zipformer2-66m-streaming-he`](https://huggingface.co/ivrit-ai/zipformer2-66m-streaming-he) at `ee769a2`
(CC BY 4.0, developed by Yakov Kolani): an icefall Zipformer2 transducer, 66M parameters, 1,493 SentencePiece tokens,
causal, decoding 1.28 s chunks with 256 frames of left context. Its encoder takes 141 fbank frames per call (128 new
plus 13 the convolutional front end needs) and 98 state tensors, and returns 32 frames at 25 Hz.

## Converting without running icefall

coremltools no longer reads ONNX, and the PyTorch definition of the model lives in icefall. Running icefall's model
code on the Mini was refused (it is code downloaded from outside the repo), so the conversion does not use PyTorch at
all. `zipformer_coreml/onnx_mil.py` reads the repo's fp32 ONNX export as data and rebuilds it in Core ML's MIL:

- Every input shape is fixed (batch 1, one chunk, fixed-size states), so the export's shape arithmetic (`Shape`,
  `Gather` on shapes, `Range`, `ConstantOfShape`, ...) is computed once in numpy and only tensor maths becomes MIL ops.
  9,231 ONNX nodes, 34 op types.
- Every op also has a numpy implementation. Feeding real arrays for every input evaluates the whole graph in numpy,
  which is the reference the Core ML build is checked against.
- int64 becomes int32 (Core ML has no int64 inputs; every index and length here is far below 2^31).

Checks, from the bottom up:

1. Each op type: numpy vs a compiled Core ML model on random inputs (`tests/test_zipformer_coreml.py`).
2. The whole encoder on three chunks of real eval-d1 audio, every one of the 99 outputs: Core ML fp32 within 4e-5
   of the numpy reference (encoder output within 7e-6 on values up to 6.4).
3. The first 30 s of an eval-d1 recording: the Core ML fp16 transcript is word for word sherpa-onnx's from #217.
4. The whole of both sets: see the comparison (Core ML fp32 against #217's sherpa-onnx int8).

The decoder and joiner are converted the same way and stay fp16 in every build (about 3.6 MB together).

## Compression

Weight-only and post-training, no calibration audio (`zipformer_coreml/convert.py`):

- **int8:** linear, symmetric, per output channel. The Core ML counterpart of sherpa-onnx's int8 build.
- **palN:** k-means palettization to 2^N values, one lookup table per group of 16 output channels.

Only the weights of linear and conv layers are compressed. A few small weights whose channel count isn't divisible by
16 (191 and 383 channels) stay fp16; coremltools skips them and says so.

**Never compress the front end.** The first 4-bit and 2-bit builds emitted no words at all, on any audio, while
3- and 6-bit happened to work. Weights-only compression didn't fix it; a layer-by-layer bisection (4-bit everywhere
except a subset, transcribing a fixed sentence) found exactly the six 2-D convolutions that read the fbank (conv2d
subsampling and its ConvNeXt block, about 144k parameters). They stay fp16 in every compressed build (0.3 MB). The
numbers in the comparison are all from builds made this way.

**3-bit costs memory, not just accuracy.** On the app's path (the Swift backend in #222, CPU and GPU, one Hebrew
sentence) the 4-bit build held 157 MB while captioning and the 3-bit build 545 MB; fp16 held 238 MB. The Python
peaks show the same split (6- and 3-bit high, 4-bit low). This fits Core ML expanding lookup tables whose width isn't
4 or 8 bits to fp16 when it loads them, but that cause is inferred, not confirmed.

## Which build to ship

The owner's rule, applied by `zipformer_coreml/report.py`, picks **3-bit (30.4 MB)**: its CER intervals overlap
int8's on both sets and it stays far from Apple. It only just qualifies, though. On voice notes it makes 5.4% CER
against int8's 4.2% (intervals 4.7–6.2 and 3.6–4.8 touch at the edge), its WER interval (9.9–12.5%) no longer overlaps
int8's (7.6–9.6%), and it needs about 3.5 times the memory of 4-bit while captioning.

**4-bit (38.6 MB) is the recommendation:** no measurable loss against int8 on either set (2.4% and 4.3% CER, every
interval overlapping), the smallest memory of any build, and about half the size of the 75 MB the owner wanted to beat.
2-bit is unusable (35% CER on conversation). The owner picks on the PR.

## The Apple Neural Engine rejects this encoder

Loading the encoder with compute units "all" starts the ANE compiler, which ran for several minutes on the M4 and then
failed (`ANECCompile() FAILED`); Core ML then fell back to CPU and GPU. So every measurement here, and the app,
uses **CPU and GPU only**: asking for the ANE would cost minutes on the first Start and gain nothing. Why the
compiler fails (graph size, a particular op, the 98 state inputs) is not established. This needs checking on the
iPhone too (phone check P2 below).

## Scoring

The #217 harness, unchanged: the #202 normaliser, strict CER and WER, 95% bootstrap intervals over recordings. eval-d1
(17 recordings of one two-speaker podcast, 1.43 h) and eval-whatsapp (54 voice notes, 1.18 h), at the revisions
#217 pinned. Each recording is decoded the way live captions run: fbank over the clip plus #217's trailing silence,
then 1.28 s chunks through the streaming encoder, greedy search, at most one token per encoder frame. The sherpa-onnx
int8 and Apple rows are #217's result lines, scored again with the same code.

## Latency and memory

Measured on the M4 Mac mini (macOS 26.5.1), one build per process, the first 60 s of five eval-d1 recordings.

- **Compute per chunk:** encoder plus greedy search for one 1.28 s chunk, measured.
- **Steady latency:** with audio arriving in real time, a chunk's text is ready when its last sample has arrived plus
  that chunk's compute. A token the model places at encoder frame f of that chunk is therefore shown
  (chunk end − frame time) + compute after the model placed it. Median and 95th percentile over every token.
- **First word:** the same for the first token of each recording (median over recordings).
- **Load:** opening the three models, cold for the first build of a run.
- **Peak memory:** the scoring process's peak resident size. It includes Python, numpy and torchaudio, so it
  overstates the app by hundreds of MB and is only good for comparing builds. The app's number comes from the Swift
  integration test in #222 (physical footprint, what iOS counts against an app): see Compression.

These measure what Seal adds on top of the model's own emission delay (how long after a word is said the model
emits it), which needs word timings that these sets don't have. Heat could not be measured: `powermetrics` needs
root on the Mini.

## Parakeet-He

Not converted. The ticket asked for both, but on 2026-10-30 the owner chose the zipformer ("Hebrew captions switch to
Seal's own engine ... recommend the zipformer" unless it proved slow or broken on device, which it didn't), and
Parakeet-He's 2.5 GB checkpoint would not fit beside this work on the Mini's free disk. The accuracy tie in #217
stands; Parakeet-He would be about 500 MB once compressed like Parakeet Ultra.

## Every device

iPhone, iPad, the Duo and the Mac all run CaptionCore, so one Core ML build covers all of them. What differs:

- **Mac:** has no caption-language setting yet and always captioned US English on Apple's engine. #222 uses Hebrew
  when the Mac's first language is Hebrew (a Decision on that PR).
- **iPhone and iPad:** untested here. Phone checks below.

## Phone checks for the owner (an iPhone run is his)

- **P1** Hebrew captions on the phone: pick Hebrew in Caption language, Start, speak; words appear in order.
- **P2** First Start after install: how long until the first word (a Core ML load with no ANE compile should be a
  few seconds; minutes would mean the ANE is being tried).
- **P3** Ten minutes of Hebrew conversation: no fallback to Apple, the phone no hotter than with English captions.
- **P4** Memory: no memory warning during P3 (the developer panel shows fallbacks).

## Run it again

```sh
EVAL_REPO=$PWD ZC_PY=<python with coremltools 9, onnx, torchaudio, soundfile, pyarrow, rapidfuzz> \
  scripts/engine-eval/zipformer-coreml-driver.sh
```

It needs the eval-d1 and eval-whatsapp shards that `hebrew-driver.sh` cuts (gated: accept ivrit.ai's terms) and #217's
sherpa-onnx and Apple result lines for the reference rows. `ZC_DELETE=1` removes the ONNX download, the builds and the
audio afterwards. Everything runs locally; no cloud service or paid API.

## Complexity

Translation is O(nodes) time and memory. Decoding is O(audio) per build: one encoder call per 1.28 s and one joiner
call per 40 ms frame; memory is the 98 state tensors (about 3 MB) plus one window of features. Scoring adds #217's
O(words² + chars²) alignment per recording and the bootstrap.
