"""Tests for language accuracy extraction."""
import pytest
from scoreboard_eval.extract_languages import extract_languages
from scoreboard_eval.rows import ScoreboardSourceMissing


def test_extract_language_sections():
    """Test case 1: Extract from language sections."""
    content = """# Language accuracy comparison

## Summary
Overall summary.

## Spanish

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 15.5% | 14.3% – 17.5% |

## French

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 9.9% | 8.1% – 11.8% |

## Recommendation
Best choice is X.
"""

    rows = extract_languages(content)

    assert len(rows) > 0

    # Should have Spanish and French rows
    spanish_rows = [r for r in rows if r.language == 'Spanish']
    french_rows = [r for r in rows if r.language == 'French']

    assert len(spanish_rows) > 0
    assert len(french_rows) > 0


def test_missing_language_sections():
    """Test case 2: Raise error if no language sections found."""
    content = """# Language accuracy comparison

## Summary
Just a summary.

## Recommendation
No language sections here.
"""

    with pytest.raises(ScoreboardSourceMissing, match="No language sections"):
        extract_languages(content)


def test_skip_metadata_sections():
    """Test case 5: Skip Summary, Engines, Recommendation sections."""
    content = """# Language accuracy comparison

## Summary
Should skip this.

## Spanish

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 15% | 14% – 16% |

## Engines and models
Should skip this.

## German

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 10% | 9% – 11% |

## Recommendation
Should skip this.
"""

    rows = extract_languages(content)

    # Should only extract Spanish and German, not Summary/Engines/Recommendation
    datasets = set(r.dataset for r in rows)
    assert 'Spanish' in datasets
    assert 'German' in datasets
    assert 'Summary' not in datasets
    assert 'Engines and models' not in datasets
    assert 'Recommendation' not in datasets


def test_language_section_ordering():
    """Test that language rows maintain section order."""
    content = """# Language accuracy comparison

## Spanish

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 15% | 14% – 16% |
| engine2 | 18% | 17% – 19% |

## French

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 9% | 8% – 10% |
"""

    rows = extract_languages(content)

    # Spanish rows should come before French rows
    spanish_indices = [i for i, r in enumerate(rows) if r.language == 'Spanish']
    french_indices = [i for i, r in enumerate(rows) if r.language == 'French']

    assert max(spanish_indices) < min(french_indices) if french_indices else True
