# A phone call heard through car speakers roughly doubles caption errors, more on Apple's engine

- **Source:** our own measurement, [`docs/testing/results/2026-11-23-car-call-synthetic.md`](../../testing/results/2026-11-23-car-call-synthetic.md)
  (#303). It uses 30 EdAcc callers, put through a synthetic 8 kHz phone line (G.711 μ-law), a car speaker and
  cabin, road noise at 20–0 dB SNR and a louder second talker in the car, and scores the bare engines on files.
- **What we took:** the phone line and car speaker alone raise caller WER from 9.2% to 13.7% on Parakeet Ultra and
  from 13.0% to 20.0% on Apple. With noise and the second talker, 0 dB gives 21.6% vs 34.4%. Apple drops far more
  of the caller's words (deletions 30 → 83 of 837). Parakeet Ultra wins the caller in every condition.
- **Confidence:** Ours. The set is synthetic, μ-law not AMR-NB, 30 pairs, bare engine, not the live path.
- **Drives:** #302 (which engine to route the car-call scenario to; first check #284, the memory-warning
  switch to Apple), and whether telephone-band training goes into #272.
- **Public use:** Careful. It's a synthetic simulation, so cite it as such until the real recording (#302 step 3)
  confirms it.
