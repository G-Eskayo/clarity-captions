## North-star fit

- **Reuses before adding anything new:** `TailCommitter`/`ParakeetEmitter` (`Packages/CaptionCore/Sources/CaptionCore/TailCommitter.swift`) for commit semantics; `SessionLog`/`replay.py score_arm`/`by_fallback` (`Packages/SystemReplay/Sources/SystemReplayKit/SessionLog.swift`, `scripts/system-replay/replay.py`) for the whole measurement harness; `edacc_eval.wer.align_pairs`/`matched_reference` (`scripts/engine-eval/edacc_eval/wer.py:107-142`) for position-aware alignment, instead of writing a second aligner; the existing `onDecode`/`decodeSeconds` callback pattern (`ParakeetBackend.swift:109`, `TranscriptionEngine.swift:213-224`) as the template for the one new callback this needs.
- **Simplest sufficient approach:** all three boundary types (seam, commit, line break) resolve to the same unit — the first word-index of a final `Update` in the existing session log — so one new Swift field (`decodeWindows: [Double]`) plus pure Python bucketing is enough; no per-word timing needs to be threaded through `CaptionUpdate`/`TranscriptionEngine` (that was the larger, riskier design I rejected — see Decision D2).
- **Tokens/cost:** spent on pure, fast-to-test Swift/Python additions; explicitly *not* spent trying to fabricate a "gap closed" result I can't produce (the Mac-only EdAcc replay needs real audio, a 500 MB bundled model, and ~2.5 hours per build per `docs/perf/whole-system-replay-design.md` — none of that is available in this worktree).
- **Phone-OS direction:** indirect — better-measured captions make the one promise (quality on-device) more trustworthy, but this ticket is instrumentation/plumbing, not user-facing.
- **More capable, not more passive:** yes for Gil (owner): precise, reusable evidence instead of a guess at which of four named suspects is costing the most, each time this gap needs re-checking (the probe is reusable going forward, not a one-off).
- **A north star argues against guessing the fix:** "Verified, not assumed" (guiding principle) directly argues against claiming the WER-gap-closed criterion without a real run. I'm saying so plainly below rather than working around it.

## What I found before designing (changes the ticket's own suggested test)

The ticket's "What to build" names "short-chunk language drift... test pinning the decode to the caption language" as one suspect for the `"yes"` → `"olha jestli"` (Portuguese/Czech) bug. I read FluidAudio 0.17.5's vendored source (`Packages/CaptionCore/.build/checkouts/FluidAudio/Sources/FluidAudio/...`, read-only — package dependencies are off-limits to change here) to see what pinning actually does:

- `AsrManager.transcribe(_:decoderState:language:)` takes an optional `Language?` and *is* honored for `.ultra` (`AsrManager.swift:314-334`, `.ultra` is routed through `TdtDecoderV3` same as `.v3`).
- But `TokenLanguageFilter` (`Shared/TokenLanguageFilter.swift`) **only discriminates writing script** — Latin vs Cyrillic vs Greek. English, Spanish, French, German, Italian and Portuguese are **all Latin script**. `TdtDecoderV3.swift:639` says this outright: *"This runs AFTER tokenLanguageFilter (which only distinguishes Latin from Cyrillic and leaves English/French ambiguous)."*
- The one same-script mitigation that exists (`englishBlocklistApplies`, `TdtDecoderV3.swift:627-633`) is hard-scoped to French only, by design — the vendor's own comment says applying it to other Latin languages "corrupts clean speech" (issue #840).

**Conclusion:** pinning `language:` to the caption language cannot fix the reported symptom (English captioned as Portuguese/Czech — same script). It's still a free, zero-risk, zero-regression guard worth adding (it blocks real cross-script leakage, e.g. Cyrillic/Greek tokens in an English/Spanish caption, at no cost — "short-circuits when nil"), but it must not be presented as closing the "yes" bug. I think this — or an earlier attempt silently assuming the pin fixes it — is a plausible reason the last two automated attempts failed code review ("must-fix issues" after 3 iterations each): an unverified fix claim is exactly what review should catch.

## Design: per-boundary measurement, reusing the existing log as-is

All three boundary types collapse to **positions in the sequence of final `SessionLog.Update`s**, which already exist — no per-word timing needs to be added anywhere:

1. **New, additive instrumentation (Swift, small blast radius):**
   - `ParakeetBackend`: add `var onWindow: (@Sendable (Double) -> Void)?`, fired with `shot.end` (session-audio seconds, same clock as everything else) at the real-decode call sites in `run()` (the main `decode(...)` branch and the `settleRequested` branch) — **not** the silence-gated skip (no re-decode happens there) and **not** `finish()`'s terminal flush (nothing follows it, so it isn't a seam). Exact sibling of the existing `onDecode` pattern at `ParakeetBackend.swift:109,184-202`.
   - `ParakeetBackend.init(modelURL:locale:)`: add `locale: Locale`, storing `language: Language?` via a pure, testable helper `ParakeetBackend.language(for:) -> Language?` (maps `locale.language.languageCode` to FluidAudio's `Language` enum; `nil` for anything FluidAudio doesn't cover — never crashes, never filters). Pass `language: language` into both `manager.transcribe(...)` call sites in `decode(...)`.
   - `TranscriptionEngine`: add `public var onDecodeWindow: (@Sendable (Double) -> Void)?`; wire it in `makeBackend()`'s `.parakeet` case (`backend.onWindow = { [weak self] t in self?.onDecodeWindow?(t) }`); pass `locale` into `ParakeetBackend(modelURL:locale:)` at its one call site.
   - `SessionLog`: add `public var decodeWindows: [Double] = []` ("audioEnd of every real Parakeet decode this session; empty on Apple's engine").
   - `main.swift`: `engine.onDecodeWindow = { t in log.decodeWindows.append(t) }`, next to the existing `watchFallbacks` wiring.
   - This is the entire Swift surface. `CaptionUpdate`, `CaptionStream`, and the app's UI are untouched.

2. **New pure analysis (Python, `scripts/system-replay/replay.py`), tested the same way `paired_gap`/`by_fallback` are:**
   - `update_spans(log) -> list[(first_idx, last_idx)]`: walk `log["updates"]` where `isFinal`, normalize each update's own text individually (`edacc_eval.normalize.normalize`), and track the contiguous run of normalized-word indices each update owns. Guard: if concatenating per-update normalization disagrees in word count with `normalize(session_text(log))` (the string already used for scoring), skip that conversation and report it as excluded — refuse rather than silently misattribute, matching `conversation_of`'s existing "refuse rather than guess" style.
   - `boundary_positions(log, spans) -> dict[str, set[int]]`: `"commit"` = every span's first index; `"line"` = span-start indices where the previous update's `end` to this update's `start` gap is ≥ `1.2` (CaptionStream's `defaultPauseSeconds`, mirrored as a named constant) or `speaker` differs; `"seam"` = for each `decodeWindows` timestamp, the first index of the span whose `[start, end]` contains it (or the next span if between two).
   - `boundary_errors(engine_only_text, log, margin_words=3) -> dict`: `align_pairs(normalize(engine_only_text).split(), normalize(session_text(log)).split())` (reusing the existing function as-is), classify each substitution/insertion by its hypothesis-side index (deletions by the nearest surviving neighbour), tag it with every boundary type whose nearest position is within `margin_words`, and count `"elsewhere"` for errors tagged with none. Non-exclusive by design (an error can be both near a line break and a seam) plus an explicit `"elsewhere"` bucket, matching the ticket's own phrasing ("within N words of X, Y, Z, **and elsewhere**").
   - Only run over conversations where the arm's session **stayed on Parakeet the whole way** (reuse `results[arm]["left_parakeet"]`, same stratification `by_fallback` already does) — commit/seam boundaries are meaningless for a session that fell back to Apple.
   - Wire into `score()`/`markdown()`: a new table, written into `docs/perf/whole-system-replay-results.md` the next time the harness runs on the Mini — this *is* the acceptance criterion's "regression check added to how builds are scored" (the gate-language precedent: `replay.py gate-language`, `docs/perf/whole-system-replay-results.md:147-165`). I'm not inventing a fourth CLI subcommand; this becomes part of the existing `score` output.

3. **What I will *not* implement in this pass, and why:** criteria 2–3 ("fix that closes the WER gap," "no lag regression") require running this harness on real EdAcc audio with the bundled model on the Mac mini — hours of wall-clock time and data this worktree doesn't have. Claiming either without that run would be exactly the unverified claim a reviewer should reject. I'll land the measurement infrastructure plus the (correctly-scoped) language pin now, and flag the structural fix as blocked on a real run — see Decisions below.

## Decisions

<!-- marvin:decisions -->
### scope-285: How to split #285 given this agent can't run the Mac-only EdAcc replay itself
- [ ] Land the per-boundary measurement infrastructure (Swift instrumentation + Python analysis, fully unit-tested) and the language-pin guard now; open/keep a follow-up for the structural fix once a real Mini run produces per-boundary numbers (recommended — matches "Verified, not assumed")
- [ ] Attempt a full speculative fix now (pick one of committed-tail window / AdaptiveHop / line-splitting to change) without measured evidence of which dominates
- [ ] Hold the whole ticket until someone can run `scripts/system-replay/run-ab.sh` on the Mini first, then implement in a single later pass

### language-pin-285: Land the FluidAudio `language:` pin given it does not fix the reported "yes" → "olha jestli" example
- [ ] Land it now as a free, zero-regression guard against cross-script leakage (Cyrillic/Greek into a Latin-script caption), documented as *not* fixing same-script drift (recommended)
- [ ] Skip it until the Mini run's boundary evidence says script-leakage is actually a measurable contributor
<!-- marvin:decisions -->

## Tests first (red before green)

1. **`ParakeetBackendLanguageTests`** (new, pure, no model needed): `ParakeetBackend.language(for:)` — `en-US` → `.english`; `es-ES`/`pt-BR`/`fr-FR`/`de-DE`/`it-IT` → their `Language` case; a locale FluidAudio doesn't cover (e.g. `ja-JP`) → `nil`; a locale with no language code → `nil` (never traps).
2. **`TranscriptionEngineBackendTests`** (existing file, extend): `makeBackend()`'s `.parakeet` case constructs `ParakeetBackend` with the engine's own `locale`, not a hardcoded default.
3. **`SessionLogTests`** (existing file, extend, mirrors `aSwitchMidSessionIsSeenFromTheUpdatesAlone`): `decodeWindows` round-trips through JSON; defaults to `[]`; `record(_:)` behaviour is unaffected by the new field.
4. **Python `test_replay.py`, new section** (mirrors `test_stitch_orders_by_segment_number...`):
   - `update_spans`: three final updates with known texts give the right index ranges; a number-containing update (`"twenty three"` vs raw `"23"`) still gets a contiguous span; a session whose per-update and whole-string normalization disagree is reported as excluded, not misattributed.
   - `boundary_positions`: a pause ≥ 1.2 s between two finals marks a line boundary; a speaker change with no pause also marks one; a pause just under 1.2 s does not; a `decodeWindows` timestamp between two spans attaches to the next one, never a negative/past-the-end index.
   - `boundary_errors`: a substitution right after a commit is tagged `"commit"`; one 10 words into a long uninterrupted span is tagged `"elsewhere"`; one that is both near a line break and near a seam gets both tags (non-exclusive); a deletion (word missing entirely from the live hypothesis) is attributed to its nearest surviving neighbour, not dropped; an engine-only text that is empty, a session log with zero final updates, and a session log whose `error` field is set (must raise, same as `session_text` does today) are all handled without crashing; a session that left Parakeet mid-way is excluded from the boundary breakdown entirely, same stratification as `by_fallback`.
5. **How we'll try to break it, explicitly from the ticket's list:**
   - A one-word utterance alone in a window → caption-language guard test (1) proves the pin is wired for the case where it *would* help (cross-script); a written note (not a test, since the model isn't available here) records that it does **not** help the documented same-script example.
   - A word split exactly across a seam, and the same word repeated across it ("the the") → already covered by existing `TailCommitterTests` (unchanged by this work); this ticket only adds the ability to *locate* such errors against a seam after the fact, so no new commit-logic test is needed here.
   - A long run-on sentence forced to commit at 12 s → `boundary_positions` test with a span count large enough that a `decodeWindows` timestamp falls strictly between two spans (already in the list above).
   - Fast speaker turns landing a line break and a seam on the same word → the non-exclusive multi-tag test above.
   - "Fixing accuracy by waiting longer" (lag regression) → out of scope for this pass (needs the real run); flagged in Decision `scope-285`, not silently dropped.

## Task List

1. `ParakeetBackend.language(for:)` pure helper + `ParakeetBackendLanguageTests` (red, then green).
2. `ParakeetBackend.init(modelURL:locale:)`, pass `language:` into both `decode()` call sites' `manager.transcribe(...)`.
3. `ParakeetBackend.onWindow` callback, fired at both real-decode sites in `run()` (not the silence-gated skip, not `finish()`).
4. `TranscriptionEngine.onDecodeWindow`, wire `locale` and `onWindow` through `makeBackend()`'s `.parakeet` case; extend `TranscriptionEngineBackendTests`.
5. `SessionLog.decodeWindows: [Double]`; extend `SessionLogTests` for round-trip.
6. `main.swift`: wire `engine.onDecodeWindow` into `log.decodeWindows`, next to `watchFallbacks`.
7. `replay.py`: `update_spans`, `boundary_positions`, `boundary_errors`, each with the pytest cases above; wire the new table into `score()`/`markdown()`, scoped to sessions that stayed on Parakeet (reuse `left_parakeet`).
8. `swift test --package-path Packages/CaptionCore` and `swift test --package-path Packages/SystemReplay` green; `python -m pytest scripts/system-replay/tests` green.
9. Update `docs/design/parakeet-engine-switch.md` and `docs/perf/whole-system-replay-design.md` with the new `decodeWindows` field and the FluidAudio script-filter finding (so the next person doesn't re-propose the same "language pin" as a fix for same-script drift).
10. PR body states plainly: criteria 2–3 (WER gap closed, no lag regression) are **not** claimed — they need a real `scripts/system-replay/run-ab.sh` run on the Mac mini using this PR's new `decodeWindows`/per-boundary output, which this agent cannot execute here; recommend Decision `scope-285`'s first option.