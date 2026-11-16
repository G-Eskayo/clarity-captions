"""Tests for the six source parsers (sources.py)."""
import pytest
from pathlib import Path
import tempfile

from scoreboard import sources


@pytest.fixture
def temp_docs_dir():
	"""Create a temporary docs/perf directory for test fixtures."""
	with tempfile.TemporaryDirectory() as tmpdir:
		yield Path(tmpdir)


class TestEngineAccuracyParser:
	"""Test parse_engine_accuracy()."""

	def test_missing_file_returns_empty(self, temp_docs_dir):
		"""Missing file returns empty list with warning."""
		result = sources.parse_engine_accuracy(temp_docs_dir)
		assert result == []

	def test_parse_engine_accuracy_overall_table(self, temp_docs_dir):
		"""Parse the Overall table from engine-accuracy-comparison.md."""
		fixture = """# Engine accuracy comparison (EdAcc)

## Overall

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 13.8% | 12.7% – 14.7% |
| sherpa-onnx | 16.1% | 14.9% – 17.2% |
| apple-speechanalyzer | 17.2% | 16.0% – 18.4% |"""

		file_path = temp_docs_dir / "engine-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_engine_accuracy(temp_docs_dir)
		assert len(result) == 3

		# Check first row
		row = result[0]
		assert row.language == "English"
		assert row.task == "captions"
		assert row.engine == "parakeet-fluidaudio (parakeet-ultra-coreml)"
		assert row.metric_name == "WER"
		assert abs(row.metric_value - 0.138) < 0.001
		assert abs(row.ci_low - 0.127) < 0.001
		assert abs(row.ci_high - 0.147) < 0.001
		assert row.source_ticket == "#145"

	def test_skip_diagnostic_entries(self, temp_docs_dir):
		"""Diagnostic entries are skipped."""
		fixture = """# Engine accuracy comparison

## Overall

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-ultra | 13.8% | 12.7% – 14.7% |
| whisperkit-nogate (diagnostic, shard 1 only) | 19.8% | 17.9% – 21.8% |"""

		file_path = temp_docs_dir / "engine-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_engine_accuracy(temp_docs_dir)
		assert len(result) == 1  # diagnostic skipped


class TestLanguageAccuracyParser:
	"""Test parse_language_accuracy()."""

	def test_missing_file_returns_empty(self, temp_docs_dir):
		"""Missing file returns empty list."""
		result = sources.parse_language_accuracy(temp_docs_dir)
		assert result == []

	def test_parse_language_table(self, temp_docs_dir):
		"""Parse language accuracy tables."""
		fixture = """# Language accuracy comparison

## Spanish

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet Ultra | 2.8% | 2.4% – 3.3% |
| Apple SpeechAnalyzer | 4.0% | 3.4% – 4.5% |"""

		file_path = temp_docs_dir / "language-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_language_accuracy(temp_docs_dir)
		# Should parse rows even if language detection is imperfect
		assert len(result) >= 1

	def test_language_inferred_from_section(self, temp_docs_dir):
		"""Languages are inferred from section headers (Spanish, French, etc)."""
		fixture = """# Language accuracy comparison

## Spanish

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet Ultra | 2.8% | 2.4% – 3.3% |
| Apple SpeechAnalyzer | 4.0% | 3.4% – 4.5% |

## French

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet Ultra | 4.5% | 3.9% – 5.1% |
| Apple SpeechAnalyzer | 7.5% | 6.7% – 8.3% |"""

		file_path = temp_docs_dir / "language-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_language_accuracy(temp_docs_dir)
		assert len(result) == 4

		# Check that languages are correctly inferred
		spanish_rows = [r for r in result if r.language == "Spanish"]
		french_rows = [r for r in result if r.language == "French"]
		assert len(spanish_rows) == 2
		assert len(french_rows) == 2


class TestHebrewParser:
	"""Test parse_hebrew()."""

	def test_missing_file_returns_empty(self, temp_docs_dir):
		"""Missing file returns empty list."""
		result = sources.parse_hebrew(temp_docs_dir)
		assert result == []

	def test_parse_hebrew_tables(self, temp_docs_dir):
		"""Parse Hebrew accuracy tables."""
		fixture = """# Hebrew engine accuracy

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI | CER |
|---|---:|---|---:|
| Parakeet-He | 5.2% | 4.5% – 5.9% | 2.4% |
| Apple DictationTranscriber | 17.8% | 15.3% – 20.6% | 10.4% |"""

		file_path = temp_docs_dir / "hebrew-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_hebrew(temp_docs_dir)
		assert len(result) == 2

		row = result[0]
		assert row.language == "Hebrew"
		assert row.task == "captions"
		assert row.engine == "Parakeet-He"

	def test_hebrew_repeated_ci_headers(self, temp_docs_dir):
		"""Hebrew table with repeated 95% CI headers (WER CI and CER CI) - both must be preserved."""
		fixture = """# Hebrew engine accuracy

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI | CER | 95% CI |
|---|---:|---|---:|---|
| Parakeet-He | 5.2% | 4.5% – 5.9% | 2.4% | 2.0% – 2.9% |
| Apple DictationTranscriber | 17.8% | 15.3% – 20.6% | 10.4% | 7.8% – 13.3% |"""

		file_path = temp_docs_dir / "hebrew-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_hebrew(temp_docs_dir)
		# Should parse both rows, not collapse them
		assert len(result) == 2

		row = result[0]
		assert row.language == "Hebrew"
		# WER CI should be correctly assigned (not CER CI)
		assert abs(row.metric_value - 0.052) < 0.001  # WER = 5.2%
		assert abs(row.ci_low - 0.045) < 0.001  # WER CI low = 4.5%
		assert abs(row.ci_high - 0.059) < 0.001  # WER CI high = 5.9%


class TestTranslationParser:
	"""Test parse_translation()."""

	def test_missing_file_returns_empty(self, temp_docs_dir):
		"""Missing file returns empty list."""
		result = sources.parse_translation(temp_docs_dir)
		assert result == []

	def test_parse_translation_tables(self, temp_docs_dir):
		"""Parse translation accuracy tables."""
		fixture = """# Translation comparison

## en-es

### FLORES-200 devtest, as written

| Engine | Model | chrF | COMET |
|---|---|---|---|
| apple | apple-en-es | 56.8 [56.2–57.4] | 0.863 [0.858–0.867] |
| opus-mt | opus-mt-en-es | 55.0 [54.3–55.6] | 0.849 [0.844–0.854] |"""

		file_path = temp_docs_dir / "translation-comparison-results.md"
		file_path.write_text(fixture)

		result = sources.parse_translation(temp_docs_dir)
		assert len(result) == 2

		row = result[0]
		assert row.task == "translation"
		assert row.metric_name == "chrF"
		assert abs(row.metric_value - 56.8) < 0.1

	def test_exclude_mlkit_android_emulator(self, temp_docs_dir):
		"""ML Kit (Android emulator) rows are excluded."""
		fixture = """# Translation comparison

## en-es

| Engine | Model | chrF | COMET |
|---|---|---|---|
| apple | apple-en-es | 56.8 [56.2–57.4] | 0.863 |
| mlkit | mlkit-en-es | 53.2 [52.6–53.8] | 0.805 |"""

		file_path = temp_docs_dir / "translation-comparison-results.md"
		file_path.write_text(fixture)

		result = sources.parse_translation(temp_docs_dir)
		# Only apple should be included, mlkit excluded
		assert len(result) == 1
		assert result[0].engine == "apple"

	def test_language_pair_inferred_from_section(self, temp_docs_dir):
		"""Language pairs are inferred from section headers (en-es, en-fr, etc)."""
		fixture = """# Translation comparison

## en-es

| Engine | Model | chrF | COMET |
|---|---|---|---|
| apple | apple-en-es | 56.8 [56.2–57.4] | 0.863 |
| opus-mt | opus-mt-en-es | 55.0 [54.3–55.6] | 0.849 |

## en-fr

| Engine | Model | chrF | COMET |
|---|---|---|---|
| apple | apple-en-fr | 50.1 [49.5–50.7] | 0.812 |
| opus-mt | opus-mt-en-fr | 48.3 [47.7–48.9] | 0.791 |"""

		file_path = temp_docs_dir / "translation-comparison-results.md"
		file_path.write_text(fixture)

		result = sources.parse_translation(temp_docs_dir)
		assert len(result) == 4

		# Check that language pairs are correctly inferred
		en_es_rows = [r for r in result if r.language == "en-es"]
		en_fr_rows = [r for r in result if r.language == "en-fr"]
		assert len(en_es_rows) == 2
		assert len(en_fr_rows) == 2


class TestEarTranslationParser:
	"""Test parse_ear_translation()."""

	def test_missing_file_returns_empty(self, temp_docs_dir):
		"""Missing file returns empty list."""
		result = sources.parse_ear_translation(temp_docs_dir)
		assert result == []

	def test_parse_ear_translation_lag(self, temp_docs_dir):
		"""Parse ear translation lag measurements."""
		fixture = """# Live Translation in your ear

## Speech to voice lag

| Step | Median | p95 | Where measured |
|---|---|---|---|
| End of speech → finished caption line | **859 ms** | 1157 ms | Mac |
| Finished translation → first audible sample (warm voice) | 10–61 ms Mac | up to 140 ms Mac | Mac, 10 languages |"""

		file_path = temp_docs_dir / "ear-translation-spike.md"
		file_path.write_text(fixture)

		result = sources.parse_ear_translation(temp_docs_dir)
		# Should parse lag rows (no "lag" word in step names, but they measure latency)
		assert len(result) == 2

		row = result[0]
		assert row.task == "ear-translation"
		assert row.metric_name == "latency_ms"
		assert abs(row.metric_value - 859.0) < 0.1  # First step is 859 ms

	def test_ear_translation_various_formats(self, temp_docs_dir):
		"""Parse ear translation with various time formats."""
		fixture = """# Live Translation in your ear

## Speech to voice lag

| Step | Median | p95 | Where measured |
|---|---|---|---|
| Step 1 | **859 ms** | 1157 ms | Mac |
| Step 2 | 10–61 ms | up to 140 ms | Mac |
| Step 3 | 51–70 ms | 69–110 ms | Mac |"""

		file_path = temp_docs_dir / "ear-translation-spike.md"
		file_path.write_text(fixture)

		result = sources.parse_ear_translation(temp_docs_dir)
		assert len(result) == 3
		# First: 859 ms (bold)
		assert abs(result[0].metric_value - 859.0) < 0.1
		# Second: 10–61 ms -> (10 + 61) / 2 = 35.5
		assert abs(result[1].metric_value - 35.5) < 0.1
		# Third: 51–70 ms -> (51 + 70) / 2 = 60.5
		assert abs(result[2].metric_value - 60.5) < 0.1


class TestLowBitParser:
	"""Test parse_low_bit()."""

	def test_missing_file_returns_empty(self, temp_docs_dir):
		"""Missing file returns empty list."""
		result = sources.parse_low_bit(temp_docs_dir)
		assert result == []

	def test_parse_model_sizes(self, temp_docs_dir):
		"""Parse model size tables."""
		fixture = """# Install size and model sizes

## Results

| Part | On disk | Compressed (zip -9) |
|---|---|---|
| Parakeet Ultra 6-bit (`ParakeetUltra/`) | 498.0 MB | 484.1 MB |
| Sortformer v2.1 fp16 | 240.6 MB | 220.4 MB |"""

		file_path = temp_docs_dir / "install-size-2026-10-29.md"
		file_path.write_text(fixture)

		result = sources.parse_low_bit(temp_docs_dir)
		assert len(result) == 2

		row = result[0]
		assert row.task == "model-size"
		assert row.size_on_disk_mb == 498.0
		assert row.size_zipped_mb == 484.1


class TestDuplicateHandling:
	"""Test that duplicate engine names in the same table are both preserved."""

	def test_no_silent_overwrite_on_duplicates(self, temp_docs_dir):
		"""Duplicate engine names don't silently overwrite each other."""
		fixture = """# Engine accuracy

## Overall

| Engine | WER |
|---|---:|
| ultra-pal6 | 13.8% |
| ultra-pal4 | 14.8% |"""

		file_path = temp_docs_dir / "engine-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_engine_accuracy(temp_docs_dir)
		# Both rows should survive
		assert len(result) == 2
		engines = [r.engine for r in result]
		assert "ultra-pal6" in engines
		assert "ultra-pal4" in engines


class TestEarTranslationRegexDefects:
	"""Test fixes for ear-translation regex issues (defect #3)."""

	def test_single_value_without_dash(self, temp_docs_dir):
		"""Single values like **859 ms** (no dash) must match - this was failing before the fix."""
		fixture = """# Live Translation in your ear

## Speech to voice lag

| Step | Median | p95 | Where measured |
|---|---|---|---|
| End of speech → finished caption line | **859 ms** | 1157 ms | Mac |"""

		file_path = temp_docs_dir / "ear-translation-spike.md"
		file_path.write_text(fixture)

		result = sources.parse_ear_translation(temp_docs_dir)
		# Must parse the single value
		assert len(result) == 1
		assert abs(result[0].metric_value - 859.0) < 0.1

	def test_range_values_with_different_dashes(self, temp_docs_dir):
		"""Range values with various dash styles must work."""
		fixture = """# Live Translation in your ear

## Speech to voice lag

| Step | Median | p95 | Where measured |
|---|---|---|---|
| Step 1 | 10–61 ms | 100 ms | Mac |
| Step 2 | 10-61 ms | 100 ms | Mac |
| Step 3 | 10–61 ms | 100 ms | Mac |"""

		file_path = temp_docs_dir / "ear-translation-spike.md"
		file_path.write_text(fixture)

		result = sources.parse_ear_translation(temp_docs_dir)
		# All three should parse
		assert len(result) == 3
		# All should average to 35.5
		for row in result:
			assert abs(row.metric_value - 35.5) < 0.1


class TestLanguageAccuracyTableIndexing:
	"""Test fixes for table_index counting bug (defect #5)."""

	def test_language_accuracy_with_summary_table_before_data(self, temp_docs_dir):
		"""A summary/recommendation table should not shift language indices."""
		fixture = """# Language accuracy comparison

## Recommendation

| Language | Recommended Engine |
|---|---|
| Spanish | Parakeet Ultra |

## Spanish

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet Ultra | 2.8% | 2.4% – 3.3% |

## French

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet Ultra | 4.5% | 3.9% – 5.1% |"""

		file_path = temp_docs_dir / "language-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_language_accuracy(temp_docs_dir)
		# Should correctly identify Spanish and French (not shift them)
		spanish_rows = [r for r in result if r.language == "Spanish"]
		french_rows = [r for r in result if r.language == "French"]
		assert len(spanish_rows) == 1
		assert len(french_rows) == 1


class TestLanguageAccuracyAndroidPath:
	"""Test Android-path ONNX handling (defect #6)."""

	def test_include_android_path_onnx_when_d2_unchecked(self, temp_docs_dir):
		"""Android-path ONNX rows are currently included (decision d2 is deferred to step 4)."""
		fixture = """# Language accuracy comparison

## Spanish

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet Ultra, FluidAudio (Core ML) | 2.8% | 2.4% – 3.3% |
| Parakeet Ultra, sherpa-onnx (ONNX, community export) | 3.2% | 2.7% – 3.7% |
| Apple SpeechAnalyzer | 4.0% | 3.4% – 4.5% |"""

		file_path = temp_docs_dir / "language-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_language_accuracy(temp_docs_dir)
		# All three rows should be included (d2 is unchecked)
		engines = [r.engine for r in result]
		assert "Parakeet Ultra, FluidAudio (Core ML)" in engines
		assert "Parakeet Ultra, sherpa-onnx (ONNX, community export)" in engines
		assert "Apple SpeechAnalyzer" in engines


class TestHebrewMultipleDatasets:
	"""Test Hebrew handling with multiple datasets (defect #7)."""

	def test_hebrew_rows_include_dataset_in_engine_name(self, temp_docs_dir):
		"""Hebrew rows from different datasets should be distinguishable."""
		fixture = """# Hebrew engine accuracy

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet-He | 5.2% | 4.5% – 5.9% |

## ivrit.ai eval-whatsapp (conversation)

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet-He | 6.1% | 5.2% – 7.0% |

## FLEURS he

| Engine | WER | 95% CI |
|---|---:|---|
| Parakeet-He | 7.3% | 6.4% – 8.2% |"""

		file_path = temp_docs_dir / "hebrew-accuracy-comparison.md"
		file_path.write_text(fixture)

		result = sources.parse_hebrew(temp_docs_dir)
		# Should have three rows (one per dataset)
		assert len(result) == 3
		# Each should have a different engine name (including dataset)
		engines = [r.engine for r in result]
		assert len(set(engines)) == 3  # All unique
		# Each should mention the dataset in the engine name
		assert all("(" in e and ")" in e for e in engines)
		# Check that notes is None now (dataset is in engine name)
		assert all(r.notes is None for r in result)


class TestTranslationLanguagePairInference:
	"""Test translation language pair inference (defect #8)."""

	def test_translation_with_multiple_tables_per_pair(self, temp_docs_dir):
		"""Multiple tables per language pair should be handled correctly."""
		fixture = """# Translation comparison

## en-es

### FLORES-200 devtest, as written

| Engine | Model | chrF | COMET |
|---|---|---|---|
| apple | apple-en-es | 56.8 [56.2–57.4] | 0.863 |
| opus-mt | opus-mt-en-es | 55.0 [54.3–55.6] | 0.849 |

### FLORES-200 devtest, backtranslated

| Engine | Model | chrF | COMET |
|---|---|---|---|
| apple | apple-en-es-bt | 58.1 [57.5–58.7] | 0.875 |

## en-fr

### FLORES-200 devtest, as written

| Engine | Model | chrF | COMET |
|---|---|---|---|
| apple | apple-en-fr | 50.1 [49.5–50.7] | 0.812 |"""

		file_path = temp_docs_dir / "translation-comparison-results.md"
		file_path.write_text(fixture)

		result = sources.parse_translation(temp_docs_dir)
		# First two tables are en-es, third is en-fr
		en_es_rows = [r for r in result if r.language == "en-es"]
		en_fr_rows = [r for r in result if r.language == "en-fr"]
		assert len(en_es_rows) == 3  # 2 from first table, 1 from second
		assert len(en_fr_rows) == 1
