# Live Translation in your ear: about 1 second from speech to voice, a voice for every translation language on iOS 26, and echo the mic must not hear

- **Sources:** our own measurement, #233, 2026-10-30, M4 Mac mini (macOS 26.5.1) and the iPhone 17 Pro simulator
  (iOS 26.5): [`ear-translation-spike.md`](../../perf/ear-translation-spike.md), raw numbers in
  [`ear-translation/`](../../perf/ear-translation/). EdAcc conversational English from the engine test (#145).
  Translation time per line from #159 ([translation-languages-results.md](../../perf/translation-languages-results.md)).
  Apple Newsroom, [Live Translation on AirPods expands to the EU](https://www.apple.com/ie/newsroom/2025/11/live-translation-on-airpods-expands-to-the-eu/)
  (Nov 2025), for Apple's own language list. Apple developer forums
  [741513](https://developer.apple.com/forums/thread/741513) and [784318](https://developer.apple.com/forums/thread/784318)
  for the built-in mic with AirPods output.
- **What we took:** from end of speech to a finished caption line is 859 ms median (p95 1157 ms, 87 lines, real-time
  feed). Translation adds about 55 ms and a warm voice starts in 8 to 61 ms, so a finished line can be heard about 1 s
  after the speaker stops, plus Bluetooth. A voice's first sentence is slower (up to 1 s on the simulator, once 10 s
  right after boot), so the voice is warmed up when the feature is turned on. The first 3 words of a line were already
  final a median of 2.0 s before the line finished, in 54 of 87 lines. All 38 translation languages on macOS 26 and
  iOS 26.5 have an on-device voice, Hebrew included. Serbian has no voice on iOS (49 voice locales). The caption engine
  hears the app's foreign voice as English-sounding nonsense, so all 60 test lines fed straight back became captions.
  A guard that matches what the app heard itself say catches 83 of 120 simulated echoes, with 1 false drop in 600
  real lines (tuned on the same set). Narrowing real speech to 8 kHz moves Apple's WER from 20.5% to 21.4%. Apple's
  AirPods Live Translation covers 9 languages on AirPods only.
- **Confidence:** Ours for the measurements: Mac and simulator, not iPhone. No microphone, so the echo way back is
  simulated, and no Bluetooth codec, headset noise suppression or output delay is included. Translation wasn't re-timed
  (pairs not installed on this Mac; the simulator can't translate). Moderate for Apple's language list. Weak (forum
  anecdotes) for the audio routing.
- **Drives:** #233's design. Speak finished lines (phrase-first is a Decision), warm the voice when the feature is
  turned on, keep the phone's mic and play over A2DP without the call profile (ADR 0021), use the echo guard with the
  own-voice fingerprint as a backup to headphones and voice processing, mark captions-only languages, and the
  real-device steps D1 to D6.
- **Public use:** Careful ("in our tests on a Mac, a translated line could be heard about a second after the speaker
  finished, before Bluetooth"; "every language Apple translates on iOS 26 has a voice"). Don't publish the echo
  numbers: they're simulated.
