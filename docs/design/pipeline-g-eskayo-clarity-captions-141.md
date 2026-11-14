## North-star fit

- **Reuses:** `docs/perf/caption-latency-baseline.md`'s pattern — a TBD measurement table plus an exact, repeatable, scriptable procedure, with an explicit `Status:` line instead of invented numbers — for the new `docs/perf/battery-<date>.md`. Reuses `BetaFeedback.swift`'s already-shipped `ConversationReport.Battery` (`dropPercentPer30Min`, `maxThermalState`) rather than inventing a new metrics model: the AC3 comparison is just reading a field that already exists (ADR 0023). Reuses the developer-panel `CaptionEngineChoice` toggle (`Apps/Spike/Sources/ContentView.swift:1747-1748`, ADR 0025) already built for exactly this A/B need, instead of adding a new engine switch. Reuses `docs/design/parakeet-engine-switch.md` §7 check C4's protocol (60 min, speaker at 1 m, screen on, 80–90% start charge, same room temperature) instead of inventing a new one — this ticket is C4, run twice (two phones) and compared against beta data. Reuses the `scripts/system-replay` / `scripts/check-evidence.mjs` convention of a small, testable, fixture-driven CLI with its own test file, for the new parsing/aggregation script.
- **Simplest sufficient approach:** don't build new on-device telemetry (it exists); don't guess a component split from coarse Instruments categories (CPU/GPU/Display lump the whole process together) — instead bracket the four named stages (mic, caption engine, Sortformer, sound labels) with cheap `os_signpost` intervals (none exist in the repo today — confirmed by search) so `xctrace`'s own export already carries the attribution, and write one small Python script to turn that export plus a beta-report JSON into the finished table. No new UI, no new user feature, no new network access.
- **Where this spends/saves tokens:** spends a little on the signposts + parser script (small, reusable for every future perf ticket — compounding leverage per the principles above); saves by not re-deriving BetaFeedback's existing battery math and not building a bespoke energy harness.
- **Capability vs. passivity:** this PR cannot make Gil more capable by doing the one thing only a human with two physical phones can do — it can only remove the arithmetic/write-up burden around it, so the hour with the phone in hand stays his.

**Plain statement, not a workaround:** acceptance criteria AC1–AC3 need a number that only exists after someone runs Instruments against two real, physically-held iPhones (SE-class and 17 Pro) for 60 minutes each, twice, with a speaker at 1 m — and compares against a real beta-report JSON that lands in `~/Library/Messages/Attachments/` on Gil's own Mac (ADR 0023), outside this repo and outside this sandboxed worktree. This headless session has no attached hardware, cannot drive Instruments' GUI or hold a phone against a speaker for an hour, and cannot read Gil's Messages. I looked for a prior attempt's PR (`gh pr list --search 141` and `--search battery`) and found none still open, consistent with the issue comment saying the last automated attempt failed code review after 3 iterations — the most likely failure mode for this exact ticket is fabricating or guessing the "measured" numbers, which this plan refuses to do. This mirrors the existing, accepted precedent in `caption-latency-baseline.md` (shipped with `TBD` and a `Status:` line, filled in later on real hardware) rather than being a new exception.

**What this PR *can* ship now (code, no real numbers):**
1. The exact repeatable protocol and `docs/perf/battery-<date>.md` skeleton with `TBD` cells for all 4 runs (2 phones × 2 engines).
2. `os_signpost` interval markers around the four named pipeline stages, so a real xctrace capture carries the component split the AC asks for.
3. A small, fully-unit-testable Python script (`scripts/battery-report/report.py`) that parses an `xctrace` export + a `seal-feedback-*.json` beta report and produces the filled-in table, the biggest-cost ranking, and the beta-vs-Instruments comparison — built and tested entirely against synthetic fixtures, no hardware needed.
4. **Not** the evidence file — writing `docs/research/evidence/...` with no real finding would be exactly the kind of unverified claim the north stars rule out; it's the last task, gated on a real run existing.

## Decisions

<!-- marvin:decisions -->
### hardware-run-owner: Who runs the four physical 60-minute captures (SE-class × 2 engines, 17 Pro × 2 engines), and when?
- [ ] Gil runs them himself on the Mac Mini with both phones attached, at his convenience; this PR ships protocol + tooling only and stays open/blocked until then
- [ ] Defer the whole ticket (park it) until both phones and 60+ minutes of uninterrupted time are available together
- [ ] Something else (say what)

### component-split-method: `docs/perf/parakeet-engine-switch.md` §7's C4 check and this ticket both want a split into screen/mic/caption engine/Sortformer/sound labels, but Instruments' Energy Log alone only gives per-process totals (CPU/GPU/ANE/Display), not per-internal-stage. Add `os_signpost` interval markers around the four stages (`ParakeetBackend`/`SpeechRecognizerBackend`, `LiveDiarizer`, `SoundLabeler`, `DeviceMicAudioSource`) so xctrace's export can attribute energy by time-overlap?
- [ ] Yes — add the signposts (small, Debug-and-Release-safe, no behavior change; this plan's default)
- [ ] No — report only Instruments' coarse per-process categories and call the per-stage split "not measurable this round"
- [ ] Something else (say what)

## Task List

1. Add `os_signpost` begin/end intervals (new `OSSignposter`, one subsystem/category e.g. `"com.sealspeak.battery"`) around: `DeviceMicAudioSource` capture loop, the active caption-engine backend's decode call (`ParakeetBackend.swift` / `SpeechRecognizerBackend.swift`), `LiveDiarizer`'s diarization step, `SoundLabeler`'s inference step. No behavior change — existing `CaptionCoreTests` for each must still pass unchanged (this is the regression check; the signposts' actual attribution correctness is the one thing this session cannot verify without a real Instruments capture — stated plainly as untested).
2. Write `scripts/battery-report/report.py` (+ `scripts/battery-report/tests/` with pytest, matching `scripts/system-replay`'s convention): parses an `xctrace export` XML/plist for a labeled 60-minute window and a `seal-feedback-*.json` beta report (schema per `docs/beta/metrics-schema.md`), and computes per-hour battery %, per-stage energy share, and a beta-vs-Instruments delta.
3. Tests for `report.py` first (fixtures, no hardware needed), covering:
   - Charging or Low Power Mode active at any point in the window → run discarded, not averaged (ticket's break-it #1).
   - `.serious`/`.critical` thermal transition inside the window (hop doubling) → reported separately, never folded into the headline number (break-it #2).
   - Start-charge outside 80–90%, or the two engine runs' start charge/room-temp fields disagreeing beyond a stated tolerance → comparison flagged invalid (break-it #3).
   - Display-energy near zero for a stretch inside the window (screen dimmed/locked) → run flagged invalid (break-it #4).
   - Malformed/missing/wrong-schema xctrace export or beta-report JSON → clear error, never a silent `0`/`null` treated as a real measurement (bad/malformed input).
   - An export spanning more than the labeled 60-minute window, or multiple conversations → script isolates only the labeled window, never averages across it (huge/oversized input).
   - Zero signpost intervals present (older build without instrumentation) → "component split unavailable," not an invented split (dependency failure).
   - Beta report present but every conversation's `battery.dropPercentPer30Min` is `null` → "no comparable beta data," not a false "they agree" (dependency failure).
   - Re-running the script twice on the same two inputs is idempotent (repeats).
   - xctrace file tagged Apple-engine paired with a beta report tagged Parakeet (via each file's own `engine` field) → refuses the mismatched pairing (wrong order / person's mistake).
   - Device-model string in either input doesn't match a known SE-3rd-gen or 17-Pro identifier → refuses silently-wrong pairing (person's mistake).
   - Running against an existing dated `docs/perf/battery-<date>.md` without `--force` never overwrites it (protects a prior real run).
4. Implement `report.py` to green against the above tests.
5. Write `docs/perf/battery-<date>.md`: the protocol (cites `docs/design/parakeet-engine-switch.md` §7 C4, the dev-panel engine toggle, 80–90% start charge, same room temp, speaker at 1 m, screen on per ADR 0019) and the 4-row table, all `TBD`, with a `Status:` line stating plainly that real-device runs are pending and naming exactly what command to run (`xcrun xctrace record …` + `python3 scripts/battery-report/report.py …`) once the hardware session happens.
6. `swift test --package-path Packages/CaptionCore` green (regression only — confirms step 1 added no behavior change).
7. **Blocked on the hardware-run-owner decision above:** once real captures exist, run `report.py` against them, fill in `docs/perf/battery-<date>.md`'s real numbers, name the biggest single cost with 1–3 candidate fixes (each costed against #25's 10% caption-speed budget), and only then write the new `docs/research/evidence/YYYY-MM-DD-<slug>.md` entry and run `node scripts/check-evidence.mjs`.