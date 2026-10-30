# In-ear voice matched to each speaker: within half a semitone of their pitch, no added lag

- **Sources:** our own measurement, #247 part 1, 2026-10-30, MacBook Pro M1 (macOS 27.0.1, load average 250 to 500):
  [`voice-match-spike.md`](../../perf/voice-match-spike.md), raw numbers in
  [`voice-match-mac.json`](../../perf/ear-translation/voice-match-mac.json). Pitch by YIN (de Cheveigné & Kawahara,
  [JASA 2002](https://doi.org/10.1121/1.1458024)); pace as syllable nuclei per second of speech after de Jong & Wempe
  ([Behavior Research Methods 2009](https://doi.org/10.3758/BRM.41.2.385)), with syllables counted from the caption text.
- **What we took:** four synthetic English speakers (two men, two women, slow to quick), Spanish target. Matched with
  Apple's own voices, the voice in your ear was 0.0 to 0.4 semitones from each speaker's pitch (today's single voice:
  1.4 to 9.1 off) and 4 to 11% from their relative pace (today: 11 to 36% off). All four got different voices, men's
  for the men and women's for the women; today all four get the same woman's voice. Setting pitch and rate added
  0.5 ms median to the first sound (40 lines, noise at this load). Profiling a speaker costs 2 to 2.6 ms per second of
  audio and is ready after 2 s of their speech; choosing the voice takes 28 µs. Counting syllables from audio alone
  was too noisy to calibrate rate; counting them from the caption text gave every voice a steady 1.75 to 1.97×
  speed-up over rate 0.4 to 0.6.
- **Confidence:** Ours. Synthetic speakers fed digitally, not people in a room; Mac, not iPhone; one target
  language; premium neural voices not measured.
- **Drives:** #247's Decision on wiring the matched voice into "Speak it in my ear" (#238), the shipped
  calibration table (no setup on the device), and the device steps V1 to V3.
- **Public use:** Careful ("in our tests, each speaker got their own voice, close to their pitch and pace, with no
  added delay"), with the synthetic-speaker caveat.
