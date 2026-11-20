"""Tests for scoreboard_eval extractors."""
import json
import pytest
from pathlib import Path
from scoreboard_eval.extract_captions import extract_engine_accuracy, extract_language_accuracy
from scoreboard_eval.extract_hebrew import extract_hebrew
from scoreboard_eval.extract_translation import extract_translation
from scoreboard_eval.extract_voices import extract_voices
from scoreboard_eval.extract_speakers import extract_speakers


def test_extract_engine_accuracy(tmp_path):
    """extract_engine_accuracy parses Overall table."""
    md_path = tmp_path / "engine-accuracy-comparison.md"
    md_path.write_text("""# Engine accuracy comparison
## Overall
| Engine | WER | 95% CI | Speed (x real time) |
|---|---:|---|---:|
| test-engine | 13.8% | 12.7% – 14.7% | 115.6x |
""")
    rows = extract_engine_accuracy(tmp_path)
    assert len(rows) == 1
    assert rows[0].engine == "test-engine"
    assert abs(rows[0].metric_value - 0.138) < 0.001
    assert abs(rows[0].ci_low - 0.127) < 0.001
    assert abs(rows[0].ci_high - 0.147) < 0.001
    assert abs(rows[0].speed_x_realtime - 115.6) < 0.1


def test_extract_engine_accuracy_missing_file(tmp_path):
    """extract_engine_accuracy returns empty list if file missing."""
    rows = extract_engine_accuracy(tmp_path)
    assert rows == []


def test_extract_language_accuracy(tmp_path):
    """extract_language_accuracy parses per-language sections."""
    md_path = tmp_path / "language-accuracy-comparison.md"
    md_path.write_text("""# Language accuracy comparison
## Spanish
| Engine | WER | 95% CI | Speed (x real time) |
|---|---:|---|---:|
| test-engine | 2.8% | 2.4% – 3.3% | 97.5x |
## French
| Engine | WER | 95% CI | Speed (x real time) |
|---|---:|---|---:|
| test-engine | 4.5% | 3.9% – 5.1% | 100.7x |
""")
    rows = extract_language_accuracy(tmp_path)
    assert len(rows) == 2
    assert rows[0].language == "Spanish"
    assert rows[0].language_code == "es"
    assert rows[1].language == "French"
    assert rows[1].language_code == "fr"


def test_extract_hebrew(tmp_path):
    """extract_hebrew parses per-set sections."""
    md_path = tmp_path / "hebrew-accuracy-comparison.md"
    md_path.write_text("""# Hebrew accuracy comparison
## eval-d1
| Engine | WER | 95% CI | Speed (x real time) |
|---|---:|---|---:|
| test-engine | 15.0% | 14.0% – 16.0% | 50.0x |
""")
    rows = extract_hebrew(tmp_path)
    assert len(rows) == 1
    assert rows[0].test_set == "eval-d1"


def test_extract_translation(tmp_path):
    """extract_translation reads JSON structured data."""
    json_path = tmp_path / "translation-languages-results.json"
    json_path.write_text(json.dumps([
        {
            "code": "es",
            "name": "Spanish",
            "chrf": 56.75,
            "ci": [56.18, 57.38],
            "median_ms": 59,
            "disk_bytes": 286000000,
        }
    ]))
    rows = extract_translation(tmp_path)
    assert len(rows) == 1
    assert rows[0].language == "Spanish"
    assert abs(rows[0].metric_value - 0.5675) < 0.001
    assert abs(rows[0].ci_low - 0.5618) < 0.001
    assert rows[0].lag_ms == 59
    assert rows[0].size_bytes == 286000000


def test_extract_voices_with_none_values(tmp_path):
    """extract_voices renders cleanly with None values in latency rows."""
    json_path = tmp_path / "lag-mac.json"
    json_path.write_text(json.dumps([
        {
            "engine": "test-voice",
            "language": "English",
            "code": "en",
            "median_ms": 50.0,
            "p95_ms": 100.0,
        }
    ]))
    rows = extract_voices(tmp_path)
    assert len(rows) == 1
    assert rows[0].metric_value == 50.0
    assert rows[0].ci_high == 100.0
    assert "nan" not in str(rows[0]).lower()


def test_extract_speakers(tmp_path):
    """extract_speakers reads speaker scoreboard markdown."""
    md_path = tmp_path / "speaker-scoreboard.md"
    md_path.write_text("""# Speaker scoreboard
## Scoreboard
| Engine | Test Set | DER |
|---|---|---:|
| sortformer-v2 | chime6 | 12.5% |
""")
    rows = extract_speakers(tmp_path)
    assert len(rows) >= 1
    found = [r for r in rows if r.engine == "sortformer-v2"]
    assert len(found) > 0
    assert abs(found[0].metric_value - 0.125) < 0.001


def test_parse_markdown_table_multiple_tables(tmp_path):
    """parse_markdown_table handles multiple tables in a section correctly."""
    from scoreboard_eval.extract_captions import parse_markdown_table

    text = """# Test
## Spanish
| Engine | WER |
|---|---:|
| Engine1 | 10.0% |

| Engine | CER |
|---|---:|
| Engine1 | 5.0% |
"""
    rows = parse_markdown_table(text, "## Spanish")
    assert len(rows) == 1
    assert rows[0].get("WER") == "10.0%"
    assert rows[0].get("CER") != "5.0%"


def test_parse_markdown_table_with_subsection(tmp_path):
    """parse_markdown_table stops at next section, not at subsections."""
    from scoreboard_eval.extract_captions import parse_markdown_table

    text = """# Test
## Spanish
| Engine | WER |
|---|---:|
| Engine1 | 10.0% |

### Spanish by accent
| Engine | Accent | WER |
|---|---|---:|
| Engine1 | Neutral | 8.0% |

## French
| Engine | WER |
|---|---:|
| Engine2 | 12.0% |
"""
    rows = parse_markdown_table(text, "## Spanish")
    assert len(rows) == 1
    assert rows[0].get("Engine") == "Engine1"
    assert "Neutral" not in str(rows)
