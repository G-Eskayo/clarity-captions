# Battery runtime per hour: Parakeet Ultra vs. Apple engine (build 11, 60 min session)

**Status: pending real hardware run.** This measurement requires a 60-minute cable-attached session on two iPhones (one per engine) running Instruments' Energy Log capture. The real hardware numbers will be filled in once available; placeholder values below allow the doc to build.

- **Source:** xctrace Energy Log capture + beta report comparison (see `docs/perf/battery-2026-11-14.md`). Measurement infrastructure in `scripts/battery-run/` for reproducible capture and validation.
- **What we took:** (pending run) the measured Neural Engine load split (screen / mic / Parakeet / Sortformer / sound-label process share) and confirmed agreement between lab (Instruments) and field (beta report) within the few-point rule (±2%).
- **Confidence:** Pending — will be "Ours" (our own measurement on the owner's device, one phone model, one scenario, not field-representative).
- **Drives:** ADR 0025 §7 Risks: confirms whether Parakeet Ultra's 30× re-encoding + diarizer contention justifies a hardware fallback (4-bit quantization, ADR 0025 C7) or targeted fix (diarizer cadence, silence gate, redraw rate). Result determines build 12+ roadmap.
- **Public use:** Pending — will be "Careful". Citation caveat: one phone model (iPhone 17, 128GB), one scenario (restaurant table, 1m speaker), one session. Real field distribution comes from beta reports once users hit limits.
