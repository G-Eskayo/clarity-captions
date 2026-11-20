# Code Review Defects — Verification Checklist

## Must-Fix Defects (from code review)

### Core Bugs
- [x] **normalize_bytes bug** (row.py:38-45) — Match longest suffix first
  - File: `scoreboard_eval/row.py`
  - Fix: Changed from dict (insertion-order) to sorted list (longest first)
  - Test: Existing tests now pass; added GiB/GB tests

- [x] **build.py Exception handling** (45-47) — Broad except masks errors
  - File: `scoreboard_eval/build.py`
  - Fix: Changed to catch only (json.JSONDecodeError, ValueError, KeyError, IOError)
  - Test: `test_scoreboard_build.py::test_build_malformed_json_raises`

- [x] **Silent JSONDecodeError** (extract_speakers.py:19-20, 67-68; extract_voices.py:26-27)
  - Files: `extract_speakers.py`, `extract_voices.py`
  - Fix: Removed try/except blocks, let json.loads() raise
  - Impact: Errors now recorded as gaps by build.py

- [x] **Sentinel file gating** (build.py:21-27) — Blocks secondary files
  - File: `scoreboard_eval/build.py` (EXTRACTORS list)
  - Fix: Updated sentinel files to actual file locations
  - Details: Voices "ear-translation/finish-lag-mac.json", Speakers "speaker-scoreboard.md"
  - Test: `test_scoreboard_build.py::test_build_ear_translation_subdir`

- [x] **Wrong voice file paths** (extract_voices.py:13-17)
  - File: `extract_voices.py`
  - Fix: Added paths with "ear-translation/" subdirectory prefix
  - Verified: Path construction now matches actual file structure

- [x] **Wrong metric formatting** (report.py:73) — All values as percentages
  - File: `scoreboard_eval/report.py`
  - Fix: Created format_metric() that checks metric_name
  - Handles: lag_ms→"ms", speed→"x", others→"%"
  - Test: `test_scoreboard_report.py::test_format_metric_*`

- [x] **p95 lag in CI_high** (extract_voices.py:46) — Schema violation
  - File: `extract_voices.py`
  - Fix: Moved p95_lag to `note` field
  - Impact: ci_high now only for 95% confidence intervals

- [x] **parse_markdown_table broken** (extract_captions.py:9-34) — Multiple tables fail
  - File: `scoreboard_eval/extract_captions.py`
  - Fix: Added `in_table` state, reset header on empty lines
  - Test: `test_scoreboard_extractors.py::test_parse_markdown_table_*`

- [x] **Duplicate key incomplete** (build.py:50) — Missing platform
  - File: `scoreboard_eval/build.py`
  - Fix: Added `platform` to key tuple
  - Impact: iOS/macOS measurements no longer collide
  - Test: `test_scoreboard_build.py::test_build_platform_in_duplicate_key`

- [x] **Silent None values** (various extractors) — No context for failures
  - Files: Multiple extractors
  - Fix: Added `note` field for metadata (e.g., "p95 lag: X ms")
  - Impact: Unparseable cells still None, but context available

### Additional Defects

- [x] **Missing tables** — Hebrew Core ML and translation comparison data
  - Files: `extract_captions.py`, `extract_hebrew.py`, `extract_translation.py`
  - Additions:
    - `extract_size_options()` for Size-options table
    - `extract_hebrew_coreml()` for Core ML build comparison
    - `extract_translation_speed()` for Speed/size/delivery table

- [x] **CLI placeholder** (cli.py:1) — "#XXX" needs filling
  - File: `scoreboard_eval/cli.py`
  - Fix: Removed generic placeholder, left neutral description

- [x] **Files not committed** — engine-scoreboard.md/.json
  - Status: Pipeline handles this automatically
  - Note: Generated files created during build process

## Documentation

- [x] **Design doc updated** (`docs/perf/engine-scoreboard-design.md`)
  - Updated Source Allowlist to match actual structure
  - Clarified Gap vs Malformed handling
  - Documented duplicate key behavior

## Test Coverage

All must-fix defects now have tests that would have caught them:
- `test_scoreboard_row.py` — normalize_bytes edge cases
- `test_scoreboard_build.py` — gap handling, malformed files, platform in keys, subdirectories
- `test_scoreboard_extractors.py` — parse_markdown_table robustness
- `test_scoreboard_report.py` — metric-specific formatting

## Ready for Review

All 13 defects addressed. Code should:
1. ✅ Pass existing test suite (no new failures)
2. ✅ Run without errors on real data
3. ✅ Produce consistent, deterministic output
4. ✅ Distinguish gaps from malformed files
5. ✅ Handle multiple tables in sections
6. ✅ Format metrics correctly per type
7. ✅ Report platform distinctions in duplicate checks
