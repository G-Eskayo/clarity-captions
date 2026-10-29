# E7. Building on existing on-device speech and speaker tools

- **Source:** [docs/research-existing-resources.md](../research-existing-resources.md): Apple SpeechAnalyzer reference
  code, FluidAudio (Apache-2.0), Sortformer (CC BY 4.0).
- **What we took:** transcription and speaker separation are solved problems on-device; reuse them, bundle the
  models, and never call the network at runtime.
- **Confidence:** Strong.
- **Drives:** ADR 0001, 0008, 0014.
- **Public use:** Yes (credit the open-source projects).
