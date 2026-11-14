# Battery and thermal load: 60-minute live captioning sessions on iPhone SE and iPhone 17 Pro, Seal 1.1.0

**Source:** Our own measurement. Lab protocol: 60-minute table session with live captions running, speech played from a speaker at 1 meter distance, both engines (Parakeet Ultra PAL6 and Apple SpeechAnalyzer) measured on the same build, same device, same start charge and matched room temperature (within 2 °C), screen on, no Low Power Mode. Thermal state recorded via Instruments Power template. Component breakdown (Screen, Mic, Caption engine, Speaker labels, Sound labels) is measured via delta runs: baseline with all features, plus separate runs with diarization disabled and ambient-sound detection disabled, allowing direct attribution of CPU cost to each feature. See `docs/perf/battery-2026-11-13.md` §7 C4 for the full protocol, delta-run procedure, and invalidation checklist.

**What we took:** TBD — to be filled in once the physical measurement runs complete. Expected outputs: battery drop per hour for each device/engine pair, component breakdown (screen, mic, caption engine, diarization, sound labels), highest thermal state observed, validation against the beta report's real-world field measurements.

**Confidence:** Ours.

**Drives:** ADR 0025 check C4 (battery and thermal pass criteria for the Parakeet engine switch); ticket #141 acceptance criteria AC1–AC3 (the actual % numbers for the four device/engine pairs, the identification of the single biggest cost, and the beta-report comparison); the optimization roadmap for candidate fixes (diarization cadence, decode hop, redraw rate).

**Public use:** Careful — cite the component breakdown by name (screen, mic, caption engine, diarization cost) and the per-hour battery drop for each device, with the caveat that these are lab numbers, not real-world (field measurements in beta reports may differ due to app usage patterns, network, and ambient thermal state).
