"""Tests for translation results extraction."""
import json
import pytest
from scoreboard_eval.extract_translation import extract_translation
from scoreboard_eval.rows import ScoreboardSourceMissing


def test_extract_translation_basic():
    """Test case 1: Extract basic translation results."""
    data = [
        {
            "code": "es",
            "name": "Spanish",
            "chrf": 56.75,
            "ci": [56.18, 57.38],
            "comet": 0.863,
            "median_ms": 59.0,
            "p95_ms": 89.0,
        },
        {
            "code": "fr",
            "name": "French",
            "chrf": 73.15,
            "ci": [72.19, 74.07],
            "comet": 0.879,
            "median_ms": 57.6,
            "p95_ms": 97.1,
        },
    ]

    json_content = json.dumps(data)
    rows = extract_translation(json_content)

    assert len(rows) > 0

    # Should have multiple rows per language (chrF, COMET, latency)
    spanish_rows = [r for r in rows if r.language == 'Spanish']
    assert len(spanish_rows) >= 3

    # Check that we have different metrics
    metrics = set(r.metric for r in spanish_rows)
    assert 'chrF' in metrics
    assert 'COMET' in metrics
    assert 'latency_ms' in metrics


def test_chrf_with_ci():
    """Test case 2: Format chrF with confidence interval."""
    data = [
        {
            "code": "es",
            "name": "Spanish",
            "chrf": 56.75,
            "ci": [56.18, 57.38],
            "comet": 0.863,
            "median_ms": 59.0,
        },
    ]

    json_content = json.dumps(data)
    rows = extract_translation(json_content)

    chrf_rows = [r for r in rows if r.metric == 'chrF']
    assert len(chrf_rows) > 0

    chrf_value = chrf_rows[0].value
    assert '56.8%' in chrf_value or '56.7%' in chrf_value  # Rounded
    assert '56.2' in chrf_value  # CI min
    assert '57.4' in chrf_value  # CI max


def test_invalid_json():
    """Test case 5: Raise error for invalid JSON."""
    with pytest.raises(ScoreboardSourceMissing, match="Invalid JSON"):
        extract_translation("not valid json")


def test_comet_formatting():
    """Test case 6: Format COMET as decimal."""
    data = [
        {
            "code": "ja",
            "name": "Japanese",
            "chrf": 43.48,
            "ci": [42.47, 44.52],
            "comet": 0.9115836,
            "median_ms": 58.78,
        },
    ]

    json_content = json.dumps(data)
    rows = extract_translation(json_content)

    comet_rows = [r for r in rows if r.metric == 'COMET']
    assert len(comet_rows) > 0

    comet_value = comet_rows[0].value
    # Should be formatted to 3 decimal places
    assert '0.911' in comet_value


def test_latency_formatting():
    """Test case 8: Format latency in milliseconds."""
    data = [
        {
            "code": "en",
            "name": "English",
            "chrf": 100.0,
            "ci": [99.0, 101.0],
            "comet": 0.95,
            "median_ms": 51.51,
        },
    ]

    json_content = json.dumps(data)
    rows = extract_translation(json_content)

    latency_rows = [r for r in rows if r.metric == 'latency_ms']
    assert len(latency_rows) > 0

    latency_value = latency_rows[0].value
    assert 'ms' in latency_value
    assert '51' in latency_value or '52' in latency_value


def test_multiple_languages():
    """Test case 10: Extract all languages from array."""
    data = [
        {"code": "es", "name": "Spanish", "chrf": 56.75, "ci": [56, 57], "comet": 0.86, "median_ms": 59},
        {"code": "fr", "name": "French", "chrf": 73.15, "ci": [72, 74], "comet": 0.87, "median_ms": 57},
        {"code": "de", "name": "German", "chrf": 68.16, "ci": [67, 69], "comet": 0.88, "median_ms": 69},
    ]

    json_content = json.dumps(data)
    rows = extract_translation(json_content)

    languages = set(r.language for r in rows)
    assert 'Spanish' in languages
    assert 'French' in languages
    assert 'German' in languages

    # Each language should have 3 metrics (if all present)
    spanish_rows = [r for r in rows if r.language == 'Spanish']
    assert len(spanish_rows) == 3


def test_missing_optional_fields():
    """Test case 11: Handle missing optional metrics gracefully."""
    data = [
        {
            "code": "es",
            "name": "Spanish",
            "chrf": 56.75,
            "ci": [56, 57],
            # Missing comet and median_ms
        },
    ]

    json_content = json.dumps(data)
    rows = extract_translation(json_content)

    # Should still extract chrF even if other metrics missing
    spanish_rows = [r for r in rows if r.language == 'Spanish']
    assert any(r.metric == 'chrF' for r in spanish_rows)


def test_source_file_tracking():
    """Test case 12: Source file is tracked correctly."""
    data = [
        {
            "code": "es",
            "name": "Spanish",
            "chrf": 56.75,
            "ci": [56, 57],
            "comet": 0.86,
            "median_ms": 59,
        },
    ]

    json_content = json.dumps(data)
    rows = extract_translation(json_content)

    # All rows should have correct source file
    assert all('translation-languages-results.json' in r.source_file for r in rows)
