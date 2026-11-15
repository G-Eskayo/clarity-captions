## North-star fit

**Reuses before adding anything:** `TailCommitter`/`ParakeetEmitter` (`TailCommitter.swift`) for all commit/line logic — no new committer; `CaptionEngineRouting.parakeetLanguages`/`parakeetWins` (`EngineFallbackPolicy.swift:38-48`) for the language→Parakeet mapping; `align_pairs`/`align_counts` (`scripts/engine-eval/edacc_eval/wer.py`) for the edit-path a boundary classifier needs, instead of a new aligner; `paired_gap`/`language_gate`'s fixed-margin-from-a-dev-run pattern (`scripts/system-replay/replay.py`) for the new regression gate; `ParakeetBackend.onDecode`/`onTrigger`'s existing callback shape for the new seam-logging hook; `RecognizedPiece.words`/`RecognizedWord` (`SpeechRecognizerBackend.swift`), which already carry per-word timing from both backends end to end — `CaptionUpdate` just drops it today.

**Simplest sufficient approach:** no new aligner, no FluidAudio fork, no new audio model. Two of the four boundary categories (commit boundary, line break) need zero new instrumentation — they're index positions in data already logged (`updates`, `lines`). Only the "seam" category needs one new callback, mirroring `onDecode`.

**Where it spends, not saves, tokens:** this is real cross-language engineering (Swift + Python + two Mac-only measurement runs), not a cheap change — the ticket's own order (evidence, then fix) is correct even though it costs an extra round trip through the harness.

**Investigation finding that changes the fix, not just the test:** I checked the vendored FluidAudio 0.17.5 source (`Packages/CaptionCore/.build/checkouts/FluidAudio`, pinned at `Packages/CaptionCore/Package.resolved` rev `0b1f462`). `AsrManager.transcribe(_:decoderState:language:)` does take an optional `Language` hint — but `TokenLanguageFilter` (`Shared/TokenLanguageFilter.swift`) only partitions by Unicode **script** (Latin / Cyrillic / Greek), filtering top-K decode candidates to match. English, Portuguese and Czech are all Latin-script, so pinning `language: .english` **will not fix the exact "yes → olha jestli" case** the ticket describes — it only guards against cross-*script* drift (e.g. a stray Cyrillic/Greek token). It's still worth wiring in (it's free, already exposed, not the retired custom-vocabulary feature from ADR 0025 D5), but the plan below treats it as a partial mitigation to be *measured*, not assumed to close the gap. The ticket's real target — the 2.6–3.4 point live-path loss — needs the per-boundary evidence, not a decoder flag.

**Capability:** pure quality work for a deaf user reading live captions — no new UI, no new choice (ADR 0013 untouched). North star 3.

## Tests to write first

**Pure, no model — `TailCommitterTests` (extend existing file):**
1. Every existing case (prefix-only finals, "the the" not doubled/swallowed, force commit at 12s, flush on stop, 10,000-case random fuzz) still holds after any `Config` tuning from task 10 — a default change without these re-passing must fail.
2. A word whose true boundary sits inside the *old* margin but outside a *tuned* one commits one hop later, never earlier, never dropped/duplicated (pins the tuning's direction).

**Pure, no model — new language-mapping tests (`EngineFallbackPolicy`/`ParakeetBackend` test file):**
3. Each of `CaptionEngineRouting.parakeetLanguages` ("en","es","fr","de","it","pt") maps to its matching `FluidAudio.Language` case; a region variant ("pt-BR") maps the same as its base code; an unsupported code (e.g. "ja") maps to `nil` — total, safe mapping even though `EngineFallbackPolicy` should already route those to Apple.

**Pure, no model — `scripts/system-replay/tests/test_replay.py` (new):**
4. A session with no boundaries near any error: everything buckets to "elsewhere."
5. An error within N words of a commit boundary (two consecutive final `updates`) counts once under "commit boundary."
6. An error within N words of a line break (`lines` boundary) counts once under "line break."
7. An error within N words of a logged seam event counts once under "seam."
8. **Ticket's own stress case** — "fast speaker turns, so a line break and a seam land on the same word": an error near *both* increments both categories once each, never double-counted into "elsewhere."
9. Malformed/missing input: an older session log with no `seams` field (or an Apple-engine session, where seams never fire) degrades that category to empty, never raises, never zeroes the others.
10. Invariant check: `sum(per-category counts) == total errors` for every conversation — catches a classifier bug that double-counts or drops an error, which no single-category test would.

**Opt-in integration, real model (`CAPTION_PARAKEET=1`, extends `ParakeetIntegrationTests`):**
11. **Ticket case "yes alone in a window":** short one-word clip, long leading silence, decoded with `language: .english`. Comment records the expectation from the finding above: this is *not* guaranteed to fix cross-Latin drift, so the test checks the call is wired and plumbed correctly and logs the actual output — it does not assert a specific text, to avoid a flaky/misleading green.
12. **Run-on sentence forcing the 12s commit:** extend the existing long-fixture test; committed text only grows, never shrinks, through the forced commit.
13. **Fast speaker turns, line break and seam on one word:** two-speaker fixture with rapid turn-taking; no dropped/duplicated word across the turn (integration-level version of unit test 8).
14. **Fixing accuracy by waiting longer:** not a unit test — a measured check that `word_lag_p50/p95` and `line_lag_p50/p95` (already recorded by the harness) don't regress past ADR 0015's budget after any `Config` tuning. **Untested here** — needs the Mac harness; flagged below.

**Explicitly untested in this worktree — say so plainly:**
15. The real per-boundary evidence run (AC1), confirming the WER CI overlaps engine-alone (AC2), confirming no lag regression (AC3), and the new gate's first validation-split run to fix its margin. All need the M4 Mac mini, the EdAcc corpus and the bundled Parakeet model, none of which this worktree has.

## Decisions

<!-- marvin:decisions -->
### d1: which `TailCommitter.Config` field to tune once the per-boundary evidence (task 9) is in
- [ ] Let the evidence pick automatically: whichever of {seam, commit boundary} has the larger error share gets its matching field (`leftContext` for seam, `stabilityMargin` for commit boundary) raised, re-measured, reported — no manual pick
- [ ] Gil picks by hand after seeing the per-boundary table in the results doc

### d2: the new regression gate's fixed margin (mirrors `gate-language`'s 2-point margin, set from a dev run, never the test split)
- [ ] Set it from the validation-split run of this fix, same discipline as `language_gate` (margin = that run's gap's upper CI bound, rounded up)
- [ ] Gil sets a round number up front (e.g. 1.0 or 1.5 WER points), independent of any run

### d3: scope of the `language:` pin — English only (the ticket's example), or all 6 Parakeet-routed languages at once
- [ ] English only for this ticket; the other 5 get the same change in a follow-up once this one is measured
- [ ] All 6 `CaptionEngineRouting.parakeetLanguages` at once — same mapper already covers them, same tests just generalize

## Task List

1. **Thread per-word timing through `CaptionUpdate`** (pure): add `words: [RecognizedWord]` to `CaptionUpdate` (`TranscriptionEngine.swift`), populated from `RecognizedPiece.words` at both existing piece→update construction sites (~lines 529, 573) — additive, no behavior change.
2. **Make `CaptionLine.startTime`/`endTime` public** (`CaptionStream.swift`) — already computed, just not visible outside the module.
3. **Log the new data in the harness**: add `words` to `SessionLog.Update`, `start`/`end` to `SessionLog.Line`, and a new `seams: [{windowStart, audioEnd}]` array (`SystemReplayKit/SessionLog.swift`); add `ParakeetBackend.onSeam` firing once per hop with the window just taken (`run()`, right before `committer.ingest`, mirrors `onDecode`); thread it through `TranscriptionEngine`'s existing callback wiring into `system-replay/main.swift`.
4. **Write the pure boundary classifier in `replay.py`** (tests 4–10 first): given a conversation's `align_pairs` alignment plus `updates`/`lines`/`seams` and an `n_words` window (start at 2), return per-category error counts that sum to the total.
5. **Wire it into `score`/`markdown`**: new table in the existing markdown output.
6. **Language mapping** (pure, test 3): static function mapping a `Locale`'s language code through `CaptionEngineRouting.parakeetLanguages` to `FluidAudio.Language`, else `nil`.
7. **Wire the pin into the decode call** (`ParakeetBackend.swift`): pass the mapped language into `manager.transcribe(padded, decoderState:, language:)`; thread `locale` into `ParakeetBackend.init` from all three existing construction sites (`TranscriptionEngine.swift:176,212,662`), same pattern `AppleSpeechBackend(locale:)` already uses.
8. **Opt-in integration tests 11–13**, extending `ParakeetIntegrationTests`.
9. **Mac-side evidence run (not executable here):** `system-replay`/`replay.py score` on the validation split with the new logging, to populate the per-boundary table in `docs/perf/whole-system-replay-results.md`.
10. **Evidence-gated `TailCommitter.Config` tuning** per Decision d1; re-run pure tests (task 1), re-run the Mac replay for AC2/AC3.
11. **New regression gate**: `replay.py gate-boundary` following the `language_gate`/`paired_gap` pattern, margin per Decision d2; wire into the same build-scoring step `check-saved-language.sh` already occupies (AC4).
12. **Update docs**: `whole-system-replay-design.md` (new fields, seam definition) and `whole-system-replay-results.md` (per-boundary table, tuned `Config` values with evidence, the language-pin result including if it didn't fix the same-script case — a documented finding either way).