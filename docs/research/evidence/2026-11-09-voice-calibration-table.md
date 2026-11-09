# Apple's voices measured once for "Sound like the speaker": 113 voices in 20 locales, shipped as a table

- **Sources:** our own measurement, PR #254 ("wire" A), 2026-11-09, MacBook Pro M1 (macOS 27), with
  `ear-spike calibrate` (renders to buffers only, nothing played): raw table in
  [`voice-calibrations-mac.json`](../../perf/ear-translation/voice-calibrations-mac.json), method as in
  [`voice-match-spike.md`](../../perf/voice-match-spike.md) (YIN pitch; pace as syllables from the text over speaking time).
- **What we took:** every installed, non-novelty voice in English, Arabic, German, Spanish, French, Hebrew, Italian,
  Japanese, Portuguese, Russian and Chinese, measured at rate 0.4 to 0.6 and pitch ×0.7 to ×1.4. 113 voices in
  20 locales; their own pitch runs from 70 to 308 Hz. Most locales have 8 or 9 voices (the eloquence set); Arabic,
  Hebrew, Russian, Portuguese (Portugal) and English outside the US and UK have one. Three compact voices (Kyoko, Tingting, Meijia) gave no
  steady pitch and were left out. Arabic and Hebrew have no pace curve (no written vowels to count), so their rate
  stays at Apple's default. A language's normal pace is its median voice at the default rate; English came out at
  3.70 syl/s against the spike's 4.58 (that one came from four mixed voices, two of them compact).
- **Confidence:** Ours, Mac only. Assumes iOS ships the same voice files (identifiers match: `com.apple.eloquence.*`,
  `com.apple.voice.compact.*`). Premium and enhanced voices weren't visible to the tool and aren't in the table. The
  English "normal" pace comes from Apple's voices, not people, so a person talking at a typical pace may be heard as
  somewhat quick; the rate is capped (0.42 to 0.6), and device step V2 checks it.
- **Drives:** the shipped table in `VoiceCalibrationData.swift`: a phone never measures or downloads a voice (owner's
  rule), and a language or voice missing from the table gets the usual single voice.
- **Public use:** Internal only.
