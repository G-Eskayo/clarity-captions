# E23. Core Audio process tap captures another app's speech for the real caption engine on the Mac

- **Source:** our own measurement, #172 / PR #174, the app's `-CallAudioSelfTest process|all` on the owner's MacBook
  Pro (macOS 27.0.1), plus a live run of the app with a window snapshot (`docs/images/pr/172/live-run-light.png`).
  Apple's process tap API: [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
- **What we took:** a process tap on an `afplay` of `say` speech delivered 593,920 frames (peak 0.75) and the real
  engine wrote the sentence word for word; tapping every sound but our own gave the same words; the sandboxed build
  did too. Run from a test runner instead of the app, the tap delivered zero frames and stopping stalled ~190 s: the
  permission is asked for and granted per app.
- **Confidence:** Ours. Synthetic speech (`say`) through a local player, not a FaceTime call over a network; one Mac.
- **Drives:** ADR 0027 (process tap over ScreenCaptureKit; every sound but our own by default).
- **Public use:** Internal. Fine to say "the Mac app captions the sound of your call, on the Mac" once a real call is
  checked.
