# Seam-first accuracy: leftContext tuning and language hint

- **Source:** code investigation (#285): the FluidAudio `language:` parameter applied to Parakeet's
  token filter (TdtDecoderV3.swift:639 in the vendored source), and the window context
  (`TailCommitter.Config.leftContext`) available to the first open word after a forced commit on
  long sentences (>12 s without a pause). Local testing via `TailCommitterTests.swift` (10,000-session
  fuzz test, plus `testForceCommitLeftContextAfterTwelveSecondsBoundary`).
- **What we took:** The language hint is a cross-script guard only, not a same-script hallucination
  fixer. FluidAudio's token filter restricts to Latin-script tokens for the 6 Parakeet languages
  (en, es, fr, de, it, pt), all Latin already. It cannot fix English words appearing in Spanish
  speech. Raising `leftContext` from 1.0 s to 2.5 s gives the next open word after a forced commit
  ~1.5 s more audio context (from ~0.4 s to ~1.9 s) without exceeding the encoder's 14.5 s max
  window, because steady-state `(audioEnd - commitPoint)` is ~2-3 s, leaving >10 s of headroom.
- **Confidence:** Ours (code read and local test, not corpus evidence). The language hint is high
  confidence: simple token filter, no corpus needed. The leftContext raise is medium: the parameter
  tuning is sound, but the accuracy payoff is untested at scale. Local test proves the mechanism
  works (the window really does contain leftContext seconds of real audio), not whether it improves
  accuracy in the field.
- **Drives:** #285 (live-path accuracy on run-on sentences and speaker turns). The language hint is
  wired in `TranscriptionEngine` at both real-path decode sites. The leftContext increase is a local
  fix candidate until the Mac-mini corpus run can verify WER and lag impact at EdAcc scale.
- **Public use:** Internal. The language hint removes a source of confusion but does not fix the
  reported symptom (same-script hallucination). The leftContext tuning is unverified at corpus
  scale; the design document plainly states what is tested locally (infrastructure, mechanism) versus
  blocked on Mac-mini access (accuracy metrics at 40 conversations). Do not cite the leftContext
  change as an accuracy win until corpus results arrive.
