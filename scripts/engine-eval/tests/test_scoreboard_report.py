"""Tests for scoreboard_eval.report rendering."""
import json
import pytest
from pathlib import Path
from scoreboard_eval.report import write_scoreboard, format_percentage, format_ci, format_number, format_metric


def test_format_percentage():
    assert format_percentage(0.138) == "13.8%"
    assert format_percentage(1.0) == "100.0%"
    assert format_percentage(None) == "–"


def test_format_ci():
    assert format_ci(0.127, 0.147) == "12.7% – 14.7%"
    assert format_ci(None, None) == "–"
    assert format_ci(0.5, None) == "–"


def test_format_number():
    assert format_number(50.123) == "50.1"
    assert format_number(50.123, 0) == "50"
    assert format_number(None) == "–"


def test_format_metric_lag_ms():
    """format_metric renders lag in milliseconds, not percentages."""
    assert format_metric(50.0, "lag_ms") == "50 ms"
    assert format_metric(123.456, "lag_ms") == "123 ms"
    assert format_metric(None, "lag_ms") == "–"


def test_format_metric_speed():
    """format_metric renders speed in multiples of realtime."""
    assert format_metric(115.6, "speed") == "115.6x"
    assert format_metric(1.0, "speed") == "1.0x"
    assert format_metric(None, "speed") == "–"


def test_format_metric_percentage():
    """format_metric renders other metrics as percentages."""
    assert format_metric(0.138, "WER") == "13.8%"
    assert format_metric(0.5, "DER") == "50.0%"
    assert format_metric(None, "WER") == "–"


def test_write_scoreboard_missing_files(tmp_path):
    """write_scoreboard generates markdown with Gaps section if files missing."""
    md_out = tmp_path / "scoreboard.md"
    write_scoreboard(tmp_path, md_out)

    md_text = md_out.read_text()
    assert "# Engine Scoreboard" in md_text
    assert "## Gaps" in md_text
    assert "Missing" in md_text


def test_write_scoreboard_with_data(tmp_path):
    """write_scoreboard generates table with actual data."""
    md_path = tmp_path / "engine-accuracy-comparison.md"
    md_path.write_text("""# Engine accuracy comparison
## Overall
| Engine | WER | 95% CI | Speed (x real time) |
|---|---:|---|---:|
| test-engine | 13.8% | 12.7% – 14.7% | 115.6x |
""")

    md_out = tmp_path / "scoreboard.md"
    json_out = tmp_path / "scoreboard.json"
    write_scoreboard(tmp_path, md_out, json_out)

    md_text = md_out.read_text()
    assert "test-engine" in md_text
    assert "13.8%" in md_text
    assert "Captions" in md_text

    json_data = json.loads(json_out.read_text())
    assert len(json_data["rows"]) > 0
    assert json_data["rows"][0]["engine"] == "test-engine"


def test_write_scoreboard_no_nan_in_output(tmp_path):
    """write_scoreboard rendering never contains 'nan'."""
    md_path = tmp_path / "engine-accuracy-comparison.md"
    md_path.write_text("""# Engine accuracy comparison
## Overall
| Engine | WER | 95% CI | Speed (x real time) |
|---|---:|---|---:|
| test-engine | 13.8% | 12.7% – 14.7% | 115.6x |
""")

    md_out = tmp_path / "scoreboard.md"
    write_scoreboard(tmp_path, md_out)

    md_text = md_out.read_text()
    assert "nan" not in md_text.lower()


def test_write_scoreboard_voices_lag_not_percentage(tmp_path):
    """Voice latency rows render as milliseconds, not percentages."""
    ear_dir = tmp_path / "ear-translation"
    ear_dir.mkdir()

    voice_data = json.dumps([
        {"engine": "Voice1", "language": "English", "code": "en", "median_ms": 50.5},
    ])
    (ear_dir / "finish-lag-mac.json").write_text(voice_data)

    md_out = tmp_path / "scoreboard.md"
    write_scoreboard(tmp_path, md_out)

    md_text = md_out.read_text()
    assert "50" in md_text
    assert "5050%" not in md_text
