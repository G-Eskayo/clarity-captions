# In room noise, build 10's Parakeet holds up better than 1.0's Apple engine

- **Source:** our own runs, #273 (PR #274), 2026-11-10: the 40 EdAcc test conversations from evidence
  `2026-11-09-build-10-vs-1-0-whole-system-replay`, mixed into DEMAND room noise (Thiemann, Ito, Vincent,
  [Zenodo 1227121](https://zenodo.org/records/1227121); restaurant, cafeteria, living room, car) at 10 dB and 0 dB
  SNR, replayed through 1.0 (5) and 1.1.0 (10) on the M4 Mac mini. Results: `docs/perf/whole-system-replay-results.md`.
- **What we took:** build 10's mic path minus 1.0: −1.6 points at 10 dB (CI −3.3 to +0.2), −3.8 at 0 dB (CI −5.5
  to −1.9). Build 10 on Apple's engine gives 1.0's text word for word. Both are poor in a loud restaurant (0 dB:
  77% vs 69% WER). Build 10's finished-line lag p95 rises from 2.0 s to 4.3 s at 0 dB.
- **Confidence:** Ours (Mac, mixed noise rather than a live room, one phone-like channel; not the phone's mic).
- **Drives:** #273: room noise doesn't explain the owner's demo report; next is the device run and the owner's
  session data.
- **Public use:** Internal.
