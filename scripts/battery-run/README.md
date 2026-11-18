# Battery Profiling Tooling

Analyze battery drain and thermal state during a 60-minute captioning session, comparing Parakeet Ultra (6-bit) vs. Apple's SpeechAnalyzer engine on the owner's iPhone.

See `docs/perf/battery-2026-11-14.md` for the full measurement procedure, candidate-fix analysis, and how to validate lab results against field data.

## Scripts

### `record.sh` — xctrace capture wrapper

Captures an Energy Log + Core ML trace on the device.

```bash
./record.sh <device-udid> <output-name> [duration-seconds]
```

Manual steps:
1. Dev panel: set engine (Parakeet or Apple)
2. Settings: Idle Stop = Never
3. Start captioning; play speaker audio at 1m for the full duration
4. Script exports CSV when done

Output: `<output-name>.ctrace` (raw trace) and `<output-name>-export.csv` (parsed data).

### `parse-trace.mjs` — xctrace CSV parser

Extract battery drop, max thermal state, and component breakdown from an xctrace export.

```bash
node parse-trace.mjs <export.csv>
```

Output: JSON with `batteryDropPercent`, `maxThermalStateLabel`, and `componentSplit` placeholder.

**Note:** The component split (neural engine load per piece: Parakeet, Sortformer, sound-label) requires parsing the Core ML template output in Instruments, not just the Energy Log CSV. The script logs where to find that data.

### `parse-beta-report.mjs` — Beta report extractor

Extract battery metrics from `seal-feedback-*.json` reports (real users).

```bash
node parse-beta-report.mjs <report1.json> [report2.json ...]
```

Output: JSON array of conversations with `build`, `engine`, `device.model`, `battery`, `lag`, etc.

Filters to rows with battery data and matching engine.

### `compare.mjs` — Lab vs. field validator

Validate agreement between lab (Instruments) and field (beta reports) data.

```bash
node compare.mjs --trace <export.csv> --reports <report1.json> [...] --engine <engine> [--manifest <manifest.json>]
```

Runs 8 validation tests:
1. Lab data exists
2. Field data exists and matches engine
3. Manifest fields filled (end charge %, room temp, etc.)
4. Build matches between lab and field
5. Device model matches
6. Battery drop within ±2% (few-point rule)
7. Thermal state matches
8. Validity rules (no negative battery, no missing fields, no extreme outliers)

Output: JSON with test results and `passed: true/false`.

## Manifest

Template: `manifest.example.json`

One manifest per test run. Fields:
- `device`, `model` — iPhone identifier
- `build` — app build number
- `engine` — `parakeet-ultra-pal6` or `apple-speechanalyzer`
- `startChargePercent`, `endChargePercent` — battery %
- `roomTemperatureCelsius` — ambient temperature
- `screenLocked` — boolean (screen off counts as background, ADR 0020)
- `idleStopSetting` — must be `never` to run full 60 minutes
- `xtraceOutputPath`, `xtraceExportPath` — file paths

## Running the battery tests

### Unit tests (no hardware needed)

```bash
node --test scripts/battery-run/parse-trace.test.mjs
node --test scripts/battery-run/parse-beta-report.test.mjs
node --test scripts/battery-run/compare.test.mjs
```

### Integration test (requires xctrace, real device)

1. Prepare manifest: `cp manifest.example.json manifest-parakeet-2026-11-14.json` and fill in device/engine/settings
2. Start capture: `./record.sh <udid> capture-parakeet-2026-11-14 3600`
3. Parse lab data: `node parse-trace.mjs capture-parakeet-2026-11-14-export.csv > lab-results.json`
4. Get beta reports from Mini: (pull from `~/Library/Messages/Attachments/`)
5. Compare: `node compare.mjs --trace capture-parakeet-2026-11-14-export.csv --reports seal-feedback-11-*.json --engine parakeet-ultra-pal6 --manifest manifest-parakeet-2026-11-14.json > comparison.json`
6. Update `docs/perf/battery-2026-11-14.md` with results

## Decision pending: live-readout button (owner-gated, optional for 1.1 build 11)

If Gil chooses "Yes" to the decision on the ticket, add a dev-panel button that mirrors `measureLatency()` / `model.latencyReport`, reusing `ConversationRecorder.entry(now:)`'s existing computation.

See the implementation plan for the mockup and PR screenshots required before merge.
