"""Tests for the GFM table parser (md_table.py)."""
import pytest
from scoreboard.md_table import parse_tables, _is_separator_line


class TestParseTablesBasic:
	"""Basic table parsing."""

	def test_empty_input(self):
		"""Empty input returns empty list."""
		assert parse_tables("") == []

	def test_no_tables(self):
		"""Text with no tables returns empty list."""
		text = "# Heading\n\nSome text without pipes.\n"
		assert parse_tables(text) == []

	def test_single_table(self):
		"""Parse a well-formed GFM table."""
		text = """| Header 1 | Header 2 |
|---|---|
| cell 1 | cell 2 |
| cell 3 | cell 4 |"""

		tables = parse_tables(text)
		assert len(tables) == 1

		table = tables[0]
		assert table.headers == ["Header 1", "Header 2"]
		assert len(table.rows) == 2
		assert table.rows[0] == {"Header 1": "cell 1", "Header 2": "cell 2"}
		assert table.rows[1] == {"Header 1": "cell 3", "Header 2": "cell 4"}

	def test_two_tables_in_one_text(self):
		"""Two separate tables are returned as separate Table objects."""
		text = """| A | B |
|---|---|
| 1 | 2 |

| X | Y |
|---|---|
| a | b |"""

		tables = parse_tables(text)
		assert len(tables) == 2
		assert tables[0].headers == ["A", "B"]
		assert tables[1].headers == ["X", "Y"]


class TestParseTablesNumerics:
	"""Numeric and special characters in cells."""

	def test_percentage_cells(self):
		"""Cells with percent signs parse correctly."""
		text = """| Engine | WER |
|---|---|
| engine-a | 13.8% |
| engine-b | 16.1% |"""

		tables = parse_tables(text)
		assert len(tables) == 1
		assert tables[0].rows[0]["WER"] == "13.8%"
		assert tables[0].rows[1]["WER"] == "16.1%"

	def test_confidence_intervals(self):
		"""Cells with CI format parse without crashing."""
		text = """| Engine | WER | 95% CI |
|---|---|---|
| test | 13.8% | 12.7% – 14.7% |"""

		tables = parse_tables(text)
		assert len(tables) == 1
		assert tables[0].rows[0]["95% CI"] == "12.7% – 14.7%"

	def test_special_characters_in_cells(self):
		"""Cells with ±, ×, – are handled correctly."""
		text = """| Metric | Value |
|---|---|
| range | 5–10 |
| times | 5×2 |
| pm | 10±2 |"""

		tables = parse_tables(text)
		assert len(tables) == 1
		assert tables[0].rows[0]["Value"] == "5–10"
		assert tables[0].rows[1]["Value"] == "5×2"
		assert tables[0].rows[2]["Value"] == "10±2"


class TestParseTablesMalformed:
	"""Malformed rows and edge cases."""

	def test_short_row_skipped(self):
		"""A row with fewer cells than headers is skipped."""
		text = """| A | B | C |
|---|---|---|
| 1 | 2 | 3 |
| 1 | 2 |
| 4 | 5 | 6 |"""

		tables = parse_tables(text)
		assert len(tables[0].rows) == 2  # Short row skipped
		assert tables[0].rows[0]["A"] == "1"
		assert tables[0].rows[1]["A"] == "4"

	def test_table_ends_at_empty_line(self):
		"""A blank line ends the table."""
		text = """| A | B |
|---|---|
| 1 | 2 |

| C | D |
|---|---|
| 3 | 4 |"""

		tables = parse_tables(text)
		assert len(tables) == 2
		assert len(tables[0].rows) == 1
		assert len(tables[1].rows) == 1

	def test_non_numeric_cells(self):
		"""Non-numeric cells (–, not built) are stored as-is."""
		text = """| Engine | Result |
|---|---|
| test-a | 15.3% |
| test-b | – |
| test-c | not run |"""

		tables = parse_tables(text)
		rows = tables[0].rows
		assert rows[0]["Result"] == "15.3%"
		assert rows[1]["Result"] == "–"
		assert rows[2]["Result"] == "not run"


class TestIsSeparatorLine:
	"""Test the separator line detection."""

	def test_valid_separator(self):
		"""Valid GFM table separators."""
		assert _is_separator_line("|---|---|") is True
		assert _is_separator_line("|---|---:|") is True  # Right-aligned
		assert _is_separator_line("|:---|---|") is True  # Left-aligned
		assert _is_separator_line("|:---:|---:|") is True  # Centered

	def test_invalid_separator(self):
		"""Invalid separators are rejected."""
		assert _is_separator_line("not a separator") is False
		assert _is_separator_line("|abc|def|") is False
		assert _is_separator_line("") is False
		assert _is_separator_line("| abc | def |") is False
		# Lines with no dashes should be rejected
		assert _is_separator_line("| | |") is False
		assert _is_separator_line("| : | : |") is False


class TestRealWorldExamples:
	"""Parse realistic markdown from actual docs."""

	def test_engine_accuracy_overall_table(self):
		"""Minimal version of engine-accuracy-comparison.md 'Overall' table."""
		text = """| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 13.8% | 12.7% – 14.7% |
| sherpa-onnx | 16.1% | 14.9% – 17.2% |
| apple-speechanalyzer | 17.2% | 16.0% – 18.4% |"""

		tables = parse_tables(text)
		assert len(tables) == 1
		assert len(tables[0].rows) == 3

		# First row
		row = tables[0].rows[0]
		assert row["Engine"] == "parakeet-fluidaudio (parakeet-ultra-coreml)"
		assert row["WER"] == "13.8%"
		assert row["95% CI"] == "12.7% – 14.7%"

	def test_language_accuracy_summary_table(self):
		"""Language accuracy summary table from language-accuracy-comparison.md."""
		text = """| Language | Apple, best locale | Parakeet Ultra | Recommendation |
|---|---|---|---|
| Spanish | 4.0% (3.4%–4.5%), es-ES | 2.8% (2.4%–3.3%) | **Parakeet** |
| French | 7.5% (6.7%–8.3%), fr-FR | 4.5% (3.9%–5.1%) | **Parakeet** |"""

		tables = parse_tables(text)
		assert len(tables) == 1
		assert len(tables[0].rows) == 2

		row = tables[0].rows[0]
		assert row["Language"] == "Spanish"
		assert row["Parakeet Ultra"] == "2.8% (2.4%–3.3%)"


class TestRepeatedHeaders:
	"""Test handling of repeated header names (e.g., Hebrew table with two "95% CI" columns)."""

	def test_repeated_headers_indexed(self):
		"""Repeated headers are indexed to avoid data loss."""
		text = """| Engine | WER | 95% CI | CER | 95% CI |
|---|---:|---|---:|---|
| test-a | 5.2% | 4.5% – 5.9% | 2.4% | 2.0% – 2.9% |
| test-b | 5.0% | 4.2% – 5.6% | 2.5% | 2.1% – 2.8% |"""

		tables = parse_tables(text)
		assert len(tables) == 1
		assert len(tables[0].rows) == 2

		# The second "95% CI" should be indexed to preserve both
		row = tables[0].rows[0]
		# First occurrence: "95% CI" for WER
		assert row["95% CI"] == "4.5% – 5.9%"
		# Second occurrence: indexed as "95% CI__2" for CER
		assert row["95% CI__2"] == "2.0% – 2.9%"
		assert row["CER"] == "2.4%"

	def test_repeated_headers_multiple_occurrences(self):
		"""Three repeated headers are all indexed correctly."""
		text = """| A | B | A | C | A |
|---|---|---|---|---|
| 1 | 2 | 3 | 4 | 5 |"""

		tables = parse_tables(text)
		assert len(tables) == 1
		row = tables[0].rows[0]
		assert row["A"] == "1"
		assert row["A__2"] == "3"
		assert row["A__3"] == "5"
		assert row["B"] == "2"
		assert row["C"] == "4"
