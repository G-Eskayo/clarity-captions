"""Tests for scoreboard_eval.build orchestration."""
import json
import pytest
from pathlib import Path
from scoreboard_eval.build import build_scoreboard


def test_build_missing_all_files(tmp_path):
    """Empty perf_dir should report all files as gaps."""
    result = build_scoreboard(tmp_path)
    assert len(result.rows) == 0
    assert len(result.gaps) > 0


def test_build_idempotency(tmp_path):
    """build_scoreboard returns same result on second call."""
    result1 = build_scoreboard(tmp_path)
    result2 = build_scoreboard(tmp_path)
    assert result1.rows == result2.rows
    assert result1.gaps == result2.gaps


def test_build_no_duplicate_keys(tmp_path):
    """build_scoreboard raises on duplicate (engine, language, test_set, metric) key."""
    md_path = tmp_path / "engine-accuracy-comparison.md"
    md_path.write_text("""# Engine accuracy comparison
## Overall
| Engine | WER | 95% CI | Speed (x real time) |
|---|---:|---|---:|
| test-engine | 10.0% | 9.0% – 11.0% | 50.0x |
| test-engine | 10.0% | 9.0% – 11.0% | 50.0x |
""")
    with pytest.raises(ValueError, match="Duplicate row"):
        build_scoreboard(tmp_path)


def test_build_malformed_json_raises(tmp_path):
    """Malformed JSON is recorded as a gap, not silently skipped."""
    json_path = tmp_path / "translation-languages-results.json"
    json_path.write_text("{invalid json")
    result = build_scoreboard(tmp_path)
    assert "Translation" in result.gaps
    assert "Malformed" in result.gaps["Translation"]


def test_build_platform_in_duplicate_key(tmp_path):
    """Duplicate key check includes platform so iOS and macOS don't collide."""
    ear_dir = tmp_path / "ear-translation"
    ear_dir.mkdir()

    voice_data = [
        {"engine": "Engine1", "language": "English", "code": "en", "median_ms": 50},
    ]

    (ear_dir / "finish-lag-mac.json").write_text(json.dumps(voice_data))
    (tmp_path / "simulator-iphone.json").write_text(json.dumps(voice_data))

    result = build_scoreboard(tmp_path)
    assert len(result.rows) >= 2
    assert len(set((r.platform, r.engine, r.language_code) for r in result.rows)) >= 2


def test_build_ear_translation_subdir(tmp_path):
    """Ear translation files in subdirectory are found and read."""
    ear_dir = tmp_path / "ear-translation"
    ear_dir.mkdir()

    voice_data = [
        {"engine": "Engine1", "language": "English", "code": "en", "median_ms": 50},
    ]

    (ear_dir / "finish-lag-mac.json").write_text(json.dumps(voice_data))

    result = build_scoreboard(tmp_path)
    voice_rows = [r for r in result.rows if r.task == "Ear Translation"]
    assert len(voice_rows) >= 1
