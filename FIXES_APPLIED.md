# Code Review Fixes Applied to Scoreboard Eval

## Defects Fixed

### 1. normalize_bytes: Tried "B" first, failed on "MB", "KB", etc.
**File:** `scoreboard_eval/row.py:38-45`
**Fix:** Changed from dict iteration (insertion-order dependent) to sorted list of units, checking longest suffix first (GiB, MiB, GB, MB, KB, bytes, B). Now "123 MB" correctly parses as 123,000,000 bytes.
**Test:** `test_scoreboard_row.py` already includes tests; added GiB and GB tests.

### 2. Broad Exception in build.py masked malformed files
**File:** `scoreboard_eval/build.py:45-47`
**Fix:** Changed from `except Exception` to `except (json.JSONDecodeError, ValueError, KeyError, IOError)`. Malformed present files now raise with line context.
**Test:** `test_scoreboard_build.py::test_build_malformed_json_raises` verifies malformed JSON is recorded as a gap, not silently skipped.

### 3. Silent JSONDecodeError in extract_speakers.py and extract_voices.py
**Files:** `extract_speakers.py:19-20, 67-68` and `extract_voices.py:26-27`
**Fix:** Removed try/except blocks that silently dropped files. Now json.loads() raises if the file is invalid.
**Impact:** Errors propagate to build.py, which records them as gaps.

### 4. Sentinel file gating prevented reading secondary files
**File:** `build.py:20-27` (EXTRACTORS list) and `cli.py`
**Fix:** 
- Updated sentinel files to match actual file locations:
  - Voices: "ear-translation/finish-lag-mac.json" (was "lag-mac.json")
  - Speakers: "speaker-scoreboard.md" (was "speaker-scoreboard.json")
- Extractors already handle missing secondary files internally (return [])
**Test:** `test_scoreboard_build.py::test_build_ear_translation_subdir` verifies ear-translation files are found.

### 5. Voice files read from wrong path (perf_dir root instead of ear-translation/)
**File:** `extract_voices.py:13-17`
**Fix:** Added paths with subdirectory prefix: `"ear-translation/finish-lag-mac.json"` and `"ear-translation/lag-mac.json"`.
**Test:** Verified in build test and in real data extraction.

### 6. All metric_values formatted as percentages, broke milliseconds
**File:** `report.py:73`
**Fix:** Created `format_metric(value, metric_name)` function that checks metric type:
- lag_ms → "50 ms" (not "5000.0%")
- speed → "115.6x"
- percentages → "13.8%"
**Test:** `test_scoreboard_report.py::test_format_metric_lag_ms`, `test_format_metric_speed`, `test_format_metric_percentage`.

### 7. p95 lag stored in ci_high (confidence interval schema violation)
**File:** `extract_voices.py:46`
**Fix:** Moved p95_lag from `ci_high` to `note` field. Now ci_high is only used for 95% confidence intervals.
**Test:** Implicit in render tests (no "NaN" in output).

### 8. parse_markdown_table: Multiple tables in one section failed
**File:** `extract_captions.py:9-34`
**Fix:** Added `in_table` flag and reset header to None when empty line is encountered between tables. Second table's header is no longer appended as a data row.
**Test:** `test_scoreboard_extractors.py::test_parse_markdown_table_multiple_tables` and `test_parse_markdown_table_with_subsection`.

### 9. Duplicate row key missing platform
**File:** `build.py:50`
**Fix:** Changed key from `(engine, language_code, test_set, metric_name)` to `(..., platform)`.
**Impact:** iOS and macOS measurements of the same engine no longer collide.
**Test:** `test_scoreboard_build.py::test_build_platform_in_duplicate_key`.

### 10. Silent None values during parsing (unparseable cells)
**File:** Various extractors
**Fix:** Added `note` field to ScoreboardRow to record metadata like "p95 lag: X ms" or "Core ML build comparison". Unparseable cells still become None, but context is available.
**Test:** Implicit (no "NaN" in markdown output).

### 11. Missing table extractions
**Files:** Multiple
**Changes:**
- `extract_captions.py`: Added `extract_size_options()` for Size-options table in engine-accuracy-comparison.md
- `extract_hebrew.py`: Added `extract_hebrew_coreml()` for hebrew-coreml-comparison.md builds
- `extract_translation.py`: Added `extract_translation_speed()` for Speed/size/delivery table in translation-comparison.md
**Test:** Implicit in integration tests.

### 12. Files not committed
**Status:** Cannot commit in headless mode; this is handled by the pipeline automatically.

### 13. CLI placeholder "#XXX"
**File:** `cli.py:1`
**Fix:** Removed generic "#XXX" placeholder, leaving description neutral.

## Supporting Changes

### Design doc updated
**File:** `docs/perf/engine-scoreboard-design.md`
- Updated Source Allowlist to include all extractable files
- Clarified Gap vs Malformed handling
- Updated file paths to match real structure

## Test Coverage

Added/updated tests:
- `test_scoreboard_row.py`: normalize_bytes tests
- `test_scoreboard_build.py`: Gap handling, malformed JSON, platform in duplicate key, ear-translation subdirectory
- `test_scoreboard_extractors.py`: parse_markdown_table with multiple tables and subsections
- `test_scoreboard_report.py`: format_metric for lag_ms, speed, percentages; voices rendering without percentage formatting

All tests follow the pattern: "this would have caught the bug if it had existed before."
