# Our 6-bit Sortformer build (93 MB) scores within fp16's confidence interval on real voices

- **Source:** our own measurement, [docs/perf/speaker-scoreboard.md § Step 2](../../perf/speaker-scoreboard.md#step-2-compressed-builds)
  (#271 step 2): the shipped fp16 Sortformer v2.1 rebuilt from its MIL (bit-identical), the speaker head palettized
  data-free at 8 and 6 bits, one build per bit width chosen on six AMI calibration meetings, then scored through the
  app's live speaker path on AMI test (16 meetings) and CHiME-6 eval (31 windows), twice each, on a Mac mini M4, with
  95% bootstrap CIs and a paired build-minus-fp16 bootstrap.
- **What we took:** pal6 (92.6 MB, 60% smaller than fp16's 229.4 MB) scores DER on screen 24.5% (20.4–28.4) on AMI and
  42.2% (38.5–45.9) on CHiME-6 against fp16's 24.0% and 42.5%; paired differences +0.55 (−2.44 to +4.24) and −0.27
  (−1.29 to +0.66) points; line first-label latency unchanged (0.62 s / 0.63 s). pal8 (120.1 MB) is the same within
  noise. Neither is faster. int8 linear crashes at load in Metal's graph compiler. Palettization with k-means is not
  repeatable from run to run, so only the scored files are the measured build.
- **Confidence:** Moderate-to-strong for these recordings on the Mac: both builds pass the ticket's ship rule on both
  sets, but the AMI paired CI can't exclude a loss of up to about 4 points, and nothing has run on an iPhone yet.
- **Drives:** #271's decision that pal6 is the build to ship once it can be distributed and checked on a device; ADR
  0014's step 2 section. Same pattern as Parakeet at 6 bits (#150).
- **Public use:** Citable as our measurement on public corpora (AMI CC BY 4.0, CHiME-6 CC BY-SA 4.0), aggregate scores
  only.
