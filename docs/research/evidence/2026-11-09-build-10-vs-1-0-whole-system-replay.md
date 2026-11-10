# Build 10 vs 1.0 through each build's own live path, on the same recorded conversations

- **Source:** our own runs, #273 (PR #274), 2026-11-09: 40 EdAcc test-split conversations (37.0 min, 58 speakers,
  CC BY-SA 4.0) replayed in real time through 1.0 (5) `4e7f55a` and 1.1.0 (10) `be128a5`, release builds, M4 Mac
  mini; scored with #145's normaliser, 95% CIs resampling conversations. Results:
  `docs/perf/whole-system-replay-results.md`.
- **What we took:** on clean audio build 10 is not worse than 1.0 (mic path +0.1 points, CI −1.2 to +1.6); build 10
  on Apple's engine gives 1.0's text word for word; the live path costs Parakeet 2.6–3.4 of its 3.9-point lead over
  Apple; a memory-pressure warning silently switches a session to Apple (8 of 40 sessions on this Mac, under heavy
  swap). The owner's "very inaccurate" demo is not explained by the app's code on clean audio.
- **Confidence:** Ours (Mac, recorded audio with digital silence between turns; not the phone, its mic or a noisy
  room).
- **Drives:** #273's next steps: a noise test and the device run, and separate fixes for the live path's chunking
  loss and the silent memory-warning switch.
- **Public use:** Internal.
