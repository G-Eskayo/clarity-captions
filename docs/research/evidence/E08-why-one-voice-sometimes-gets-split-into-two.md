# E8. Why one voice sometimes gets split into two speakers

- **Source:** our own replay measurements, [docs/perf/speaker-label-stability.md](../perf/speaker-label-stability.md) (#91, PR #94).
- **What we took:** the speaker model itself reassigns one voice after pitch or pace changes; smoothing cut live
  relabels (e.g. 8.1 → 4.5 per minute) without slowing real turn-taking; a full fix needs a voice-recognition model.
- **Confidence:** Ours (synthetic voices; real-device check pending).
- **Drives:** SpeakerLabelSmoother (#94); open decision on adding a speaker-embedding model.
- **Public use:** Careful (good "how we measure" story; don't overstate accuracy).
