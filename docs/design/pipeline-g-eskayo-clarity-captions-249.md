## North-star fit

**Reuses:** the generator pattern in `scripts/engine-eval/edacc_eval/report.py` (`write_report`/`write_language_report`, lines ~292/549: `now = meta.get("generated_at") or dt.datetime.now(...)`) and `scripts/engine-eval/translation_eval/report.py` — dataclass rows, a `meta` dict for injectable/testable timestamps, "rebuilt from scratch each cycle," a `python -m <pkg>.cli <command>` entry point, and a flat `tests/test_*.py` dir with `pytest.ini` (`testpaths = tests`). No existing markdown-*table-parser* to reuse (every existing package only *writes* tables, never reads one back), so `md_table.py`'s small GFM-table reader is genuinely new, kept deliberately tiny.

**Simplest sufficient approach:** the ticket's listed sources (#145, #158, #217, #225, #241, #159, #237, #203) have no raw per-clip data in this repo — audio/transcripts are gitignored by design (`docs/perf/engine-accuracy-design.md`) and the raw result JSONL lives on the Mac minis, not in any worktree. The only "perf results files" a pipeline agent can actually read are the already-committed summaries in `docs/perf/*.md` (and the handful of sibling `*.json`). So the generator parses *those* six committed files, not the offline eval pipelines — matching the retriage comment's own instruction ("read whatever results files are on main"). This is a deviation from a literal reading of "generated... from the perf results files" worth flagging, not guessing past silently.

**Spends tokens on:** one parser per source doc (six small, pure functions), because the six docs have six different table shapes (WER+CI, chrF+COMET, CER on two corpora, lag-by-step, size-by-build). A single generic parser would either break on the first format change or produce misleading unified numbers (chrF forced to look like WER). Small, separate, pure functions is the CaptionCore-style pattern this repo already uses for exactly this reason.

**Saves tokens/effort downstream:** step 2 (routing) and future scoreboard refreshes read one normalized JSON file instead of six prose docs — compounding leverage for every later ticket that touches engine choice.

**Machine/runs on:** nothing (pure Python, no model inference) — runs anywhere the repo checks out, including CI's "site" job (path glob `scripts/*` triggers it, but `check-site.mjs` only scans `site/` and `Apps/`, confirmed by reading it — no collision).

**Leaves the user more capable:** yes — a reusable, tested source of truth for engine choice that replaces six documents nobody could compare by eye. **CaptionCore, Apps/Spike and Apps/Mac are untouched** — no swift test or app-build risk, and no repeat of this ticket's three earlier `ParakeetUltra` build crashes (those only happen when the app target is touched).

**Explicitly out of scope this run** (per the 2026-11-04 retriage comment): CaptionCore routing (step 2, waits on #221), the gaps/follow-up-ticket list (step 3), the Android column (step 4), and size cleanup before/after (step 5). Acceptance criterion 1 only.

## Decisions

<!-- marvin:decisions -->
### d1: Should non-WER tasks (translation chrF, in-ear-voice lag/voice-availability) be forced into the same per-row (language × engine × device, one metric) schema as captions, or kept as separate per-task sections in both the `.md` and `.json`?
- [ ] Same unified row schema everywhere (`metric_name` varies: WER, CER, chrF, lag_ms, voice_available) — one table shape, easiest for step 2's routing code to consume later, but a row like "voice available: yes/no" sits oddly next to a WER row
- [ ] Shared `Row` type, but the `.md` renders Captions / Translation / In-ear voice as separate table sections (current lean) — same JSON contract, friendlier reading
- [ ] Captions and Translation unified (both have an accuracy metric + CI); in-ear voice lag/voice-availability kept out of the per-row table entirely, reported as its own short prose section fed by the same script

### d2: sherpa-onnx numbers (language-accuracy-comparison.md, translation-comparison-results.md's ML Kit) were measured on an Android **emulator on the Mac**, not real Android hardware. Label them in the scoreboard as:
- [ ] `device_or_platform: "Android (emulator on Mac)"` — explicit about the gap
- [ ] `device_or_platform: "Mac (Android's engine)"` — groups by where it actually ran, flags in a footnote that it's a stand-in for Android
- [ ] Exclude Android-path rows from this run entirely; add them only when #249's step 4 (Android column, ADR 0026) lands

## Tests (written first)

The ticket has no "How we'll try to break it" or Attacks section (checked `gh issue view 249 --comments`; the body has only "What to build" and "Acceptance criteria"). Tests derived from the north-star "tests try to break it" principle, scoped to what a doc-reading, file-writing script can actually fail at:

1. **`md_table.py` parser, direct unit tests** (no files, inline strings):
   - a well-formed GFM table with a leading/trailing `|---|` separator parses to the right headers/rows
   - a table cell containing `%`, `±`/`–`/`×` and parenthesised CIs (`"24.0% (20.4%–27.3%)"`) parses without exception — the shared numeric-cell format every source doc uses
   - two tables in one file (own headers each) are returned as two separate tables, not merged
   - a non-numeric cell (`"not built"`, `"not run"`, `"–"`) parses to `None`, never raises — exercised directly against the real `docs/perf/engine-accuracy-comparison.md` §"Low-bit builds (#203)" fixture, which has exactly this
   - a table with a missing/short row (fewer cells than headers) is skipped with a note, not a crash
   - empty input / a file with no tables at all returns `[]`, not an exception
2. **Each of the six source parsers** (`parse_engine_accuracy`, `parse_language_accuracy`, `parse_hebrew`, `parse_translation`, `parse_ear_translation`, `parse_low_bit`), against small inline fixtures shaped like the real doc (not the live file, so a later doc edit can't silently break the test):
   - produces one row per engine/language/build as expected, with correct `metric_name`
   - a source file that doesn't exist (simulating a results doc not yet produced, e.g. #203's "not built yet" state) returns `[]` with a warning, not an exception — the generator must not crash because one of six sources is incomplete
   - duplicate engine names in the same table (shouldn't happen, but malformed input might) don't silently overwrite each other — both rows survive, or a clear collision note is attached
3. **Name-matching between sections within one doc** (e.g. engine-accuracy's "Overall" WER rows enriched with "Size options" sizes by substring match): a deliberately ambiguous pair (`ultra-pal6` vs `ultra-pal4`) must match its own row, not its neighbor — regression test pinned to this exact pair since they differ by one character.
4. **`build.py` end-to-end**, against real fixtures copied from the current repo files (frozen copies in `tests/fixtures/`, not live `docs/perf/*.md`, so the test doesn't flap when those files are regenerated):
   - running the generator twice on the same input produces byte-identical output (determinism/idempotency) except for an explicitly injected `generated_at` (same pattern as `edacc_eval.report`'s `meta.get("generated_at")`)
   - the `.json` output round-trips: every row in the `.md` tables has a corresponding row in the `.json`, same values
   - pointing the generator at a `docs/perf/` directory missing all six source files produces an empty-but-valid report (header + "no data yet" note) and exit code 0, not a crash — this *will* happen for real whenever #271/#272-style in-flight tickets haven't landed yet
   - a huge synthetic table (1000 rows) completes in the test suite's normal timeout — guards against an accidentally quadratic merge step
5. **CLI**: `python -m scoreboard.cli build --root <tmp> --out <tmp>/engine-scoreboard.md --json-out <tmp>/engine-scoreboard.json` run against a temp dir with fixture docs/perf files produces both outputs; missing `--root` or a `--root` that isn't a directory exits non-zero with a message, not a stack trace.

## Task List

1. Add `scripts/engine-eval/scoreboard/__init__.py`, `model.py` (the `Row` dataclass: `language`, `task`, `engine`, `device_or_platform`, `metric_name`, `metric_value`, `ci_low`, `ci_high`, `size_on_disk_mb`, `size_zipped_mb`, `latency`, `memory_mb`, `source_ticket`, `source_doc`, `notes` — all but the first four optional).
2. Write `md_table.py`: a minimal GFM table reader (`parse_tables(text) -> list[Table]`), covering the parser unit tests above.
3. Write the six source parsers in `sources.py`, one function per doc, each returning `list[Row]`, per the fixtures/tests above. Resolve Decision d1's outcome for how translation/voice rows are shaped, and d2's outcome for how Android-path rows are labeled, before finalizing `parse_translation`/`parse_language_accuracy`/`parse_ear_translation`.
4. Write `build.py`: `build(root: Path, meta: dict | None = None) -> list[Row]` calling all six parsers (each failure isolated and logged, never fatal), plus `render_markdown(rows) -> str` and `render_json(rows, meta) -> str`.
5. Write `cli.py` (`python -m scoreboard.cli build --root --out --json-out`), following `edacc_eval/cli.py`'s `argparse` subcommand shape.
6. Add `scripts/engine-eval/tests/test_scoreboard_md_table.py`, `test_scoreboard_sources.py`, `test_scoreboard_build.py`, `test_scoreboard_cli.py`, with the fixture files under `scripts/engine-eval/tests/fixtures/scoreboard/` (frozen copies, per test design above).
7. Run the generator once for real against the live `docs/perf/` and commit its output as `docs/perf/engine-scoreboard.md` + `docs/perf/engine-scoreboard.json`, with a short header stating what it covers, its six sources, and that routing/gaps/Android-column/before-after-size are deferred to #249's later steps.
8. Verify: `python3 -m pytest` from `scripts/engine-eval/` (new suite green, existing suites unaffected) and `swift test --package-path Packages/CaptionCore` (unaffected — confirms no accidental Swift/CaptionCore touch). No app-build verify needed since `Apps/*` is untouched.

**Untested/unverifiable by this agent:** nothing UI-facing changes, so the "look proof" / screenshot playbook step doesn't apply — this ticket produces docs and a Python package only.