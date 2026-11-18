"""Tests for English accuracy extraction."""
import pytest
from scoreboard_eval.extract_english import extract_english
from scoreboard_eval.rows import ScoreboardSourceMissing


def test_extract_overall_section():
    """Test case 1: Extract from ## Overall section."""
    content = """# Engine accuracy comparison

## Overall

| Engine | WER | 95% CI | vs target |
|---|---:|---|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 13.8% | 12.7% – 14.7% | good |
| sherpa-onnx | 16.1% | 14.9% – 17.2% | acceptable |

## By accent
Some other content
"""

    rows = extract_english(content)

    assert len(rows) > 0
    overall_rows = [r for r in rows if r.condition == 'overall']
    assert len(overall_rows) >= 2

    # Find the parakeet row
    parakeet_row = next((r for r in overall_rows if 'parakeet-ultra-coreml' in r.engine), None)
    assert parakeet_row is not None
    assert parakeet_row.dataset == 'EdAcc'
    assert parakeet_row.language == 'English'
    assert parakeet_row.metric == 'WER'
    assert '13.8%' in parakeet_row.value


def test_missing_overall_section():
    """Test case 2: Raise error if ## Overall is missing."""
    content = """# Engine accuracy comparison

## By accent
Some content
"""

    with pytest.raises(ScoreboardSourceMissing, match="## Overall"):
        extract_english(content)


def test_extract_lowbit_section():
    """Test case 8: Extract from ## Low-bit builds section."""
    content = """# Engine accuracy comparison

## Overall

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 13.8% | 12.7% – 14.7% |

## Low-bit builds (#203)

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-tdt-0.6b-v3-coreml-int4) | 22.7% | 20.8% – 24.6% |

## Size options
"""

    rows = extract_english(content)

    lowbit_rows = [r for r in rows if r.condition == 'low-bit builds']
    assert len(lowbit_rows) > 0

    int4_row = next((r for r in lowbit_rows if 'int4' in r.engine), None)
    assert int4_row is not None
    assert '22.7%' in int4_row.value


def test_extract_size_options_section():
    """Test case 14: Extract from ## Size options section."""
    content = """# Engine accuracy comparison

## Overall

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 13.8% | 12.7% – 14.7% |

## Size options

| Model | On disk | Zipped | Peak memory |
|---|---:|---:|---:|
| ultra-pal6 | 498 MB | 485 MB | 63 MB |
| parakeet-ultra-coreml | 632 MB | 555 MB | 60 MB |
"""

    rows = extract_english(content)

    size_rows = [r for r in rows if r.condition == 'size options']
    # Should have multiple rows: on_disk, zipped, and peak_memory for each model
    assert len(size_rows) >= 6

    # Verify we're extracting size/memory metrics, not WER
    metrics = set(r.metric for r in size_rows)
    assert 'on_disk_mb' in metrics
    assert 'zipped_mb' in metrics
    assert 'peak_memory_mb' in metrics
    assert 'WER' not in metrics


def test_model_extraction():
    """Test that model is extracted from engine name."""
    content = """# Engine accuracy comparison

## Overall

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 13.8% | 12.7% – 14.7% |
"""

    rows = extract_english(content)

    assert any(r.model == 'parakeet-ultra-coreml' for r in rows)
