## North-star fit

**Reuses:** the existing `scripts/engine-eval/` workspace — `edacc_eval` (English/#145, language/#158, Hebrew/#201 reports), `translation_eval` (#159), each already following the same shape: a pure scoring function tested with hand-built in-memory rows (`edacc_eval/report.py:score`, tested in `tests/test_report.py`), then a thin renderer/CLI. `write_report`/`write_language_report`/`write_hebrew_report` (`edacc_eval/report.py:399,636`, `report_hebrew.py:206`) already accept an optional `json_out` and dump their `Score`/`LanguageResult` dataclasses as JSON — but that JSON was never committed alongside the `.md` docs in `docs/perf/`, and the raw per-clip result directories those commands need (`~/edacc-eval/results*`) don't exist in this worktree or any CI checkout. So the only inputs actually available to a script running from this repo are the **committed** `docs/perf/*.md` prose reports (machine-generated, "do not edit by hand") and the few sibling JSONs that already exist (`translation-languages-results.json`). The new generator is a same-shaped sibling package, `scoreboard_eval/`, that extracts typed rows from those committed files — composable with the existing `tests/` + `pytest.ini` workspace, no new test runner or script location invented.

**Simplest sufficient approach:** one small extractor function per source table (by column *name*, not position, since `hebrew-coreml-comparison.md` reuses the header `WER` twice for two different datasets) feeding one shared `ScenarioRow` shape, rendered to both `docs/perf/engine-scoreboard.md` and `docs/perf/engine-scoreboard.json`. No generic markdown-table engine, no re-running any scorer (that needs corpora and hours of Mac-mini time, explicitly out of scope). No Swift/CaptionCore/app changes at all — `swift test` and the app build stay untouched and green by construction, which also avoids the build-crash failure mode two attempts ago.

**Scope correction against the ticket:** Gil's 2026-11-04 comment narrows this run to step 1 only ("Write the scoreboard generator with tests... Routing (step 2) waits for #221's pack engine. Steps 3–5 get their own follow-up tickets"). So of the issue's 4 acceptance criteria, only the first applies now; the second (routing driven by the scoreboard) is blocked on #221 (open, pack engine not built — confirmed via `CaptionEngineRouting.parakeetLanguages` in `EngineFallbackPolicy.swift:38`, still a hand-written `Set`), and the third/fourth (gap tickets, before/after install size) are step 3/5 follow-ups. I'm treating "built from the existing perf results files" literally: only files already committed under `docs/perf/`, not a re-run of any evaluation.

**Token/compute cost:** trivial — pure-Python, string/table parsing over already-committed text, a few hundred ms. No model loads, no audio, no simulator.

**More capable, not more passive:** today `CaptionEngineRouting`'s language list is a hand-maintained `Set` with inline citations the reader must trust ("#158, FLEURS: 2.8% vs 4.0%"). A generated scoreboard makes those numbers checkable and diffable in review instead of asserted in a comment — a precondition for step 2 to later read routing from data instead of hand-written rules, which is the actual leverage point.

**Machine:** none (not an iOS build step) — pure Python, runs anywhere; verified locally with `pytest` from `scripts/engine-eval`.

## What the scoreboard covers, and what it doesn't (this run)

Source docs, mapped to the ticket's issue list by what's actually committed:

| Ticket's source | Committed file | What it gives the scoreboard |
|---|---|---|
| #145, #203 | `docs/perf/engine-accuracy-comparison.md` | English: `## Overall` (engine, WER, 95% CI, speed) + `## Low-bit builds (#203)` + `## Size options` (size, memory) |
| #158, #241 (#234) | `docs/perf/language-accuracy-comparison.md` | Per-language (`es/fr/de/it/pt`) tables: engine, WER, 95% CI, accent-blind WER, speed |
| #217 | `docs/perf/hebrew-accuracy-comparison.md` | Hebrew, per dataset (eval-d1, eval-whatsapp): engine, WER+CER with CI |
| #225 (#220) | `docs/perf/hebrew-coreml-comparison.md` | Hebrew zipformer builds: bits, size, WER/CER per dataset vs fp16 |
| #159 | `docs/perf/translation-languages-results.json` | Already machine-readable: language, chrF, 95% CI, latency, asset size — read directly, no parsing |

**Explicitly out of this run's scoreboard**, stated plainly rather than force-fit:
- **#237 (in-ear voice / `ear-translation-spike.md`)** has no per-language/per-engine table — it's pipeline-stage latency (end-of-speech→caption, translate, voice-start) with mixed Mac/simulator ranges in single cells, not WER/CER. It doesn't fit the `language × engine × device × task` row shape with an accuracy metric. Folding it in would mean inventing a row shape only it uses. I'm leaving it out of the generator and noting it as a gap in the scoreboard's own "Not covered yet" section, rather than guessing a shape for it.
- **Speaker labels / `speaker-scoreboard.md`** (#271) — not in the ticket's "What to build" or source list; diarization (who's speaking) is a different concern from engine routing (what transcribes/translates). Left out.
- **Android column** (`speaker-android-engines.md`) — step 4 of the ticket, explicitly a separate future step.
- **Heat** — no measured thermal numbers exist anywhere in `docs/perf/` yet (only design-doc mentions of the *plan* to measure it, e.g. ADR 0025's "60-minute heat and battery" phone check, never run). The schema carries a `heat` field for every row (future-proof per the ticket's "What to build" item 1), but it will read `null`/"not measured" for every row today — reported honestly, not fabricated.
- **Install-size before/after with quality unchanged** (acceptance criterion 4) is step 5's cleanup-tracking feature, not this generator's per-scenario `size` column (which *is* in scope, from the "Size options" and Hebrew build tables above).

No Decisions needed: the task-aware row shape (`{language, engine, device, task}` → metrics that vary by task: WER/CER+CI for captions, chrF+CI for translation) follows directly from the owner's own framing in the ticket ("language × device × platform × task: captions, translation, in-ear voice"), and the exclusions above are judgment calls I can make and state, not genuine open choices.

## Design

New package `scripts/engine-eval/scoreboard_eval/` (sibling to `edacc_eval`, `translation_eval`), consistent with the existing one-package-per-domain layout:

- `rows.py` — the shared `ScenarioRow` dataclass: `task` (`"captions"`/`"translation"`), `language`, `engine`, `device` (`"Mac"`/`"iPhone simulator"`/etc., defaulting to what the source doc states), `metric_name` (`"WER"`/`"CER"`/`"chrF"`), `value`, `ci_low`, `ci_high`, `speed_x_realtime`, `size_mb`, `memory_mb`, `heat`, `source_issue`, `source_doc`.
- `extract_english.py` — parses `## Overall` and `## Low-bit builds (#203)` and `## Size options` out of `engine-accuracy-comparison.md` by locating each heading then reading its Markdown table by column name.
- `extract_languages.py` — parses each `## <Language>` section's table out of `language-accuracy-comparison.md`.
- `extract_hebrew.py` — parses the two dataset tables out of `hebrew-accuracy-comparison.md` (WER **and** CER per engine) and the build table out of `hebrew-coreml-comparison.md` (handles the repeated `WER` header by reading column groups positionally within the row, not globally by name).
- `extract_translation.py` — loads `translation-languages-results.json` directly (already structured; just reshapes into `ScenarioRow`).
- `markdown_table.py` — the one shared low-level helper: given a block of lines starting at a `|---|` row, return `list[dict[str, str]]` keyed by header text, preserving duplicate header text as a list-of-values when a table repeats a header (used by the Hebrew Core ML table).
- `build.py` — `build_scoreboard(rows: list[ScenarioRow]) -> Scoreboard`: groups rows, sorts, and is the one function with the real logic (grouping, "not measured" gaps, sort order) — pure, no file I/O, fully unit-testable with hand-built `ScenarioRow` lists (mirrors `edacc_eval/report.py`'s `score()`/`build_report()` split).
- `render.py` — `render_markdown(Scoreboard) -> str` and `render_json(Scoreboard) -> dict`.
- `cli.py` — `python -m scoreboard_eval.cli build --repo-root . --out docs/perf/engine-scoreboard.md --json-out docs/perf/engine-scoreboard.json`: wires the five extractors (reading the fixed, committed doc paths), `build_scoreboard`, and both renderers. Thin, no logic of its own — matches `edacc_eval/cli.py`'s existing style.

`docs/perf/engine-scoreboard.md` header states plainly it's generated (matching the "do not edit by hand" convention of its siblings), lists which issues/tasks it covers, and has a "Not covered yet" section naming in-ear voice, speaker labels, Android, and heat as named gaps (not pretending they're `0` or missing silently).

## Tests first (adversarial — one per misuse)

All in `scripts/engine-eval/tests/test_scoreboard.py` (+ a couple of small fixture strings inline, not full copies of the real docs, so tests don't drift when Gil hand-edits prose elsewhere in those files):

1. **Happy path** — a minimal well-formed `## Overall` table extracts the expected `ScenarioRow`s with correct engine/WER/CI/speed.
2. **Missing file** — `extract_english` (etc.) given a path that doesn't exist raises a clear, named error (`ScoreboardSourceMissing`), not a bare `FileNotFoundError` three frames down; `build.py`'s caller catches it and records the whole source as a gap rather than crashing the whole generator (one missing/renamed doc shouldn't blank the scoreboard).
3. **Heading present, table empty** (0 data rows under the header) — returns `[]`, not an exception; doesn't fabricate a row.
4. **Heading missing entirely** (doc edited, section renamed/removed) — same: a gap, not a crash, not a silently-empty-but-successful table mistaken for "no data at all."
5. **Column reordered** — swap two columns in the fixture table; extraction by header name still finds the right value in the right field (guards the exact kind of silent misalignment a positional parser would produce).
6. **Duplicate header name** (the Hebrew Core ML `WER`-appears-twice case) — fixture reproduces it; extractor must return both values attached to their respective dataset groups, not overwrite one with the other.
7. **Malformed/truncated table row** (fewer cells than headers, e.g. a hand-edit that drops a trailing `|`) — skipped with a recorded warning, not an `IndexError` that kills the whole run.
8. **Non-numeric / "not run" / "not built" cells** (seen for real in `engine-accuracy-comparison.md`'s #203 section and `install-size`'s "Not measured") — parsed as an explicit "not measured" value, never silently coerced to `0.0` (which would look like a perfect score) or crash the float parse.
9. **CI string formats differ across docs** (`"12.7% – 14.7%"` en dash vs `"12.7%-14.7%"` vs the Hebrew doc's different dash) — the CI parser is tested against both forms seen in the real files.
10. **translation JSON missing an expected key** (schema drift in `translation-languages-results.json`) — recorded as a gap for that language, not a `KeyError` crash.
11. **Two source docs name the same engine differently** (`"apple-speechanalyzer"` vs `"Apple SpeechAnalyzer"` vs `"Apple DictationTranscriber he-IL"`) — `build_scoreboard` is tested to keep them as distinct engine identities rather than silently merging unrelated engines, since collapsing them would be a worse bug than leaving them separate.
12. **Re-running the generator is idempotent** — calling `build_scoreboard` twice on the same rows (or running the CLI twice) produces byte-identical output; guards against nondeterministic dict/set ordering leaking into the committed `.md`/`.json`.
13. **Wrong working directory / relative paths** — CLI invoked from a directory other than the repo root fails closed with a clear message rather than silently reading nothing (mirrors the project's `--repo-root` convention already used by other `scripts/` tools... — if no such convention exists, state it fails closed with a clear "doc not found at <resolved path>" message).
14. **Large/huge input** — a fixture table with hundreds of rows (one real doc, `engine-accuracy-comparison.md`'s "By accent" table, already has ~30+ rows) extracts and renders in the same shape without truncation.

## Task List

1. Add `scripts/engine-eval/scoreboard_eval/__init__.py`, `rows.py` (the `ScenarioRow` dataclass and `ScoreboardSourceMissing` exception), and `markdown_table.py` (header-indexed, duplicate-header-aware table parser) — with its own unit tests (cases 3, 4, 5, 6, 7, 8, 9 above, at the parser level).
2. Add `extract_english.py` (`## Overall`, `## Low-bit builds (#203)`, `## Size options` from `engine-accuracy-comparison.md`) with tests (cases 1, 2, 8, 14).
3. Add `extract_languages.py` (per-`## <Language>` tables from `language-accuracy-comparison.md`) with tests (cases 1, 2, 5).
4. Add `extract_hebrew.py` (two dataset tables from `hebrew-accuracy-comparison.md`, build table from `hebrew-coreml-comparison.md`) with tests (cases 1, 2, 6, 8, 9).
5. Add `extract_translation.py` (reshape `translation-languages-results.json`) with tests (cases 1, 2, 10).
6. Add `build.py` (`build_scoreboard`: group, sort, collect gaps, de-duplicate engine identity per case 11) with tests (cases 11, 12).
7. Add `render.py` (`render_markdown`, `render_json`, including the "Not covered yet" gaps section) with a snapshot-style test asserting stable, sorted output (case 12).
8. Add `cli.py` (`build` subcommand wiring extractors → `build_scoreboard` → both renderers → writes `docs/perf/engine-scoreboard.md` + `.json`) with a test invoking it against the real committed `docs/perf/*` files in this repo and asserting it runs end-to-end without error (case 13 for the failure path, run from a wrong cwd).
9. Run the CLI for real, generate and commit `docs/perf/engine-scoreboard.md` and `docs/perf/engine-scoreboard.json`.
10. Run `pytest` across all of `scripts/engine-eval` (not just the new tests) to confirm nothing in the shared `tests/` workspace broke, and confirm `swift test --package-path Packages/CaptionCore` is unaffected (no Swift files touched).
11. PR: name the ticket (`Part of #249`), state plainly that steps 2–5 are follow-up work (step 2 blocked on #221), and link the new `docs/perf/engine-scoreboard.md` for review — no screenshots needed (no UI/look change).