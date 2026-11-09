# The shipped fp16 Sortformer scores 24% DER on screen on AMI and 42% on CHiME-6

- **Source:** our own measurement, [docs/perf/speaker-scoreboard.md](../../perf/speaker-scoreboard.md) (#271 step 1):
  the app's live speaker path (`SpeakerPathReplay`: LiveDiarizer + SpeakerLabelSmoother) over the frozen test split,
  AMI test (16 meetings, 9.1 h, Array1-01) and CHiME-6 eval (31 ten-minute windows, 5.2 h), each run twice on a Mac
  mini M4, 95% CIs by bootstrap over recordings.
- **What we took:** DER on screen 24.0% (20.4%–27.3%) on AMI and 42.5% (38.5%–46.3%) on CHiME-6; a line's first label
  0.62 s / 0.63 s median after it starts; long monologues split across two labels 38% / 65%; about 22× real time; about
  120–135 MB while streaming. The bare model's segments are deterministic, but the labels shown are not (#275), at
  0.01 points of DER.
- **Confidence:** Strong for these recordings and this config. Not a like-for-like comparison with published DER (no
  collar, word-level reference, the app's FIFO 40 streaming config), so it's the baseline for our builds, not a claim
  about the model in general.
- **Drives:** step 2 of #271. A compressed build ships only if its DER-on-screen CI overlaps these on both sets and its
  line first-label median is at most 0.68 s (AMI) / 0.69 s (CHiME-6). Also #275's tie-break fix.
- **Public use:** Citable as our measurement on public corpora (AMI CC BY 4.0, CHiME-6 CC BY-SA 4.0), aggregate scores
  only.
