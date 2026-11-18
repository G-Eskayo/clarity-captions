"""Tests for Hebrew accuracy extraction."""
import pytest
from scoreboard_eval.extract_hebrew import extract_hebrew


def test_extract_hebrew_accuracy():
    """Test case 1: Extract from hebrew-accuracy-comparison.md."""
    acc_content = """# Hebrew accuracy comparison

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 25% | 23% – 27% |

## ivrit.ai eval-whatsapp (voice notes)

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 28% | 26% – 30% |

## FLEURS he (read speech)

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 22% | 20% – 24% |

## Engines and versions
Details here.
"""

    coreml_content = """# Hebrew CoreML comparison

## Latency and memory on the Mac (one build per process)

| Build | Latency | Memory |
|---|---:|---:|
| parakeet-ultra-coreml | 100 ms | 50 MB |

## Recommendation
Use this build.
"""

    rows = extract_hebrew(acc_content, coreml_content)

    assert len(rows) > 0

    # Should have accuracy rows for each dataset
    datasets = set(r.dataset for r in rows)
    assert any('ivrit.ai eval-d1' in d for d in datasets)
    assert any('ivrit.ai eval-whatsapp' in d for d in datasets)
    assert any('FLEURS he' in d for d in datasets)


def test_extract_hebrew_coreml():
    """Test case 2: Extract from hebrew-coreml-comparison.md."""
    acc_content = """# Hebrew accuracy comparison

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 25% | 23% – 27% |
"""

    coreml_content = """# Hebrew CoreML comparison

## Latency and memory on the Mac (one build per process)

| Build | Latency | Memory |
|---|---:|---:|
| build1 | 100 ms | 50 MB |
| build2 | 150 ms | 75 MB |

## Recommendation
Text.
"""

    rows = extract_hebrew(acc_content, coreml_content)

    # Should have coreml build rows
    coreml_rows = [r for r in rows if 'coreml' in r.dataset.lower()]
    assert len(coreml_rows) >= 2


def test_hebrew_languages_field():
    """Test case 6: All rows have language=Hebrew."""
    acc_content = """# Hebrew accuracy comparison

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 25% | 23% – 27% |
"""

    coreml_content = """# Hebrew CoreML comparison

## Latency and memory on the Mac

| Build | Latency | Memory |
|---|---:|---|
| build1 | 100 ms | 50 MB |
"""

    rows = extract_hebrew(acc_content, coreml_content)

    # All rows should have language='Hebrew'
    assert all(r.language == 'Hebrew' for r in rows)


def test_hebrew_source_files():
    """Test case 8: Source files are recorded correctly."""
    acc_content = """# Hebrew accuracy comparison

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 25% | 23% – 27% |
"""

    coreml_content = """# Hebrew CoreML comparison

## Latency and memory on the Mac

| Build | Latency | Memory |
|---|---:|---|
| build1 | 100 ms | 50 MB |
"""

    rows = extract_hebrew(acc_content, coreml_content)

    acc_rows = [r for r in rows if 'accuracy-comparison' in r.source_file]
    coreml_rows = [r for r in rows if 'coreml-comparison' in r.source_file]

    assert len(acc_rows) > 0
    assert len(coreml_rows) > 0
    assert all('hebrew' in r.source_file for r in rows)


def test_hebrew_model_extraction():
    """Test case 9: Model extracted from engine names."""
    acc_content = """# Hebrew accuracy comparison

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 25% | 23% – 27% |
"""

    coreml_content = """# Hebrew CoreML comparison

## Latency and memory on the Mac

| Build | Latency | Memory |
|---|---:|---|
| build1 | 100 ms | 50 MB |
"""

    rows = extract_hebrew(acc_content, coreml_content)

    # Should extract model name
    assert any(r.model == 'parakeet-ultra-coreml' for r in rows)


def test_hebrew_coreml_dataset_tracking():
    """Test case 6 (fix verification): Duplicate CER/WER headers track dataset context."""
    acc_content = """# Hebrew accuracy comparison

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| engine1 | 25% | 23% – 27% |
"""

    # Table with duplicate CER and WER headers for different datasets
    coreml_content = """# Hebrew CoreML comparison

| Build | Size on disk | ivrit.ai eval-d1 (conversation) CER | WER | ivrit.ai eval-whatsapp (voice notes) CER | WER |
|---|---|---|---|---|---|
| Core ML fp16 | 134.2 MB | 2.4% | 4.9% | 4.2% | 8.7% |
"""

    rows = extract_hebrew(acc_content, coreml_content)

    # Extract the CER/WER rows from the Core ML table
    coreml_rows = [r for r in rows if 'coreml' in r.dataset.lower()]

    # Should have 4 coreml rows: 2 CER + 2 WER for different datasets
    accuracy_rows = [r for r in coreml_rows if r.metric in ('CER', 'WER')]
    assert len(accuracy_rows) == 4

    # Verify dataset tracking: values should not be conflated
    eval_d1_rows = [r for r in accuracy_rows if 'eval-d1' in r.dataset]
    whatsapp_rows = [r for r in accuracy_rows if 'eval-whatsapp' in r.dataset]

    assert len(eval_d1_rows) == 2  # One CER, one WER
    assert len(whatsapp_rows) == 2  # One CER, one WER

    # Verify values are correct
    assert any(r.metric == 'CER' and r.value == '2.4%' for r in eval_d1_rows)
    assert any(r.metric == 'WER' and r.value == '4.9%' for r in eval_d1_rows)
    assert any(r.metric == 'CER' and r.value == '4.2%' for r in whatsapp_rows)
    assert any(r.metric == 'WER' and r.value == '8.7%' for r in whatsapp_rows)
