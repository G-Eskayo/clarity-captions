# Issue #25 Implementation Summary

## What was implemented

### 1. Core latency measurement infrastructure
- **`CaptionLatencyReport.swift`**: Aggregates lag samples with median and p95 percentile calculation via nearest-rank method.
- **`TranscriptionEngine.startReplaying(fileURL:)`**: New public method that replays fixed audio through the entire captioning pipeline at real-time pace, enabling reproducible latency measurement identical to the live mic path.
- **`TranscriptionEngine.processBuffer(_:...)`**: Extracted buffer processing logic (resample, diarize, feed) into a private method used by both live mic (`start()`) and replay (`startReplaying()`) paths — no behavior change for shipping app.
- **`TranscriptionEngine.makeResultStream(...)`**: Extracted result-yielding logic into a private helper to avoid duplication.

### 2. Latency benchmark test
- **`CaptionLatencyBenchmarkTests.swift`**: Opt-in test gated by `CAPTION_LATENCY=1` environment variable; must run with `-c release` per Spike's existing comment on optimized builds.
  - Generates fixture dynamically if not bundled (via `say` command).
  - Warm-up pass to exclude model-load cost.
  - Measured pass collects lag samples and time-to-first-caption.
  - Parses baseline from `docs/perf/caption-latency-baseline.md`.
  - **Fails** if median exceeds baseline by >10%; **warns** (doesn't fail) if p95 exceeds baseline by >10%.

### 3. Baseline documentation
- **`docs/perf/caption-latency-baseline.md`**: Living document with device, OS, date, and measured median/p95/time-to-first-caption. Structured so the test can parse it. Initially contains placeholders; numbers are populated by running the benchmark on target hardware.

### 4. Architecture Decision Record
- **`docs/adr/0015-latency-budget.md`**: Documents the 10% regression budget policy (approved in `docs/ideas/speech-and-audiology-ideas.md`), measurement method, baseline storage, and fixture commitment decision.

### 5. Latency fixture generation script
- **`scripts/generate-latency-fixture.sh`**: One-time script to generate the deterministic fixture via `say`. Run once and commit the resulting WAV; tests load or regenerate as needed.

### 6. Fixture directory structure
- **`Packages/CaptionCore/Tests/CaptionCoreTests/Fixtures/GENERATE.md`**: Instructions for fixture generation and regeneration.

### 7. iPhone app integration
- **`Apps/Spike/Sources/ContentView.swift`**: Added `latencyReport` property to `CaptionModel` and `measureLatency()` method that runs the same replay + report logic against the bundled fixture. Added "Measure latency" button to developer panel.
- **`Apps/Spike/project.yml`**: Added latency fixture as a bundled resource.

## Running the benchmark

**On Mac (Release build, for comparison):**
```bash
cd Packages/CaptionCore
CAPTION_LATENCY=1 swift test -c release --filter CaptionLatencyBenchmark
```

**On iPhone (manual step, not yet verified):**
- Build and run Spike in Release mode.
- Long-press the status text to show the developer panel.
- Tap "Measure latency".
- Results print to the debug console.

## Manual steps required

### 1. Generate and commit the latency fixture
Run once from the repository root:
```bash
bash scripts/generate-latency-fixture.sh
git add Packages/CaptionCore/Tests/CaptionCoreTests/Fixtures/latency-fixture.wav
git commit -m "Test fixture: latency measurement audio"
```

### 2. Run the benchmark on target hardware and record the baseline
On the primary development Mac (in Release mode):
```bash
CAPTION_LATENCY=1 swift test -c release --filter CaptionLatencyBenchmark
```

Parse the output for `LATENCY-RESULT` and populate the table in `docs/perf/caption-latency-baseline.md` with the median, p95, and time-to-first-caption values.

### 3. iPhone verification (outside this implementation scope)
Build Spike on a real iPhone in Release mode and run the latency measurement via the dev panel to confirm the same numbers are achievable on-device. This is not tested here (no iPhone hardware in CI environment) but uses identical production code.

## Acceptance criteria mapping

| Criterion | Implementation |
|---|---|
| Prints median, p95, time-to-first-caption | `CaptionLatencyBenchmarkTests` output and Spike dev panel |
| Baseline recorded in docs w/ device+OS | `docs/perf/caption-latency-baseline.md` |
| Fails >10% median regression, warns on p95 | Test logic in `CaptionLatencyBenchmarkTests.swift` |
| Runs on Mac without phone, repeatable on phone | Mac: `swift test -c release`; iPhone: dev panel button |
| Budget recorded in an ADR | `docs/adr/0015-latency-budget.md` |

## Test status

All existing tests pass. The new latency benchmark test:
- Compiles successfully.
- Is opt-in (`CAPTION_LATENCY=1`).
- Skips if the fixture doesn't exist (but can generate it dynamically).
- Requires Release build (`-c release`).
- Has **not been run yet** — fixture generation and baseline measurement require bash/say access and will happen in the next step.

## Notes

- The refactoring preserves exact behavior for the live mic path (`start()`); `processBuffer()` is called identically.
- `startReplaying()` is a new internal seam for testing, not exposed to the shipping app.
- Fixture is committed to avoid TTS version/platform drift in measurements (exemption to ADR 0014's "no binaries" rule for this small test data).
- iPhone dev-panel measurement code is untested here but calls the same production APIs the Mac test uses.
