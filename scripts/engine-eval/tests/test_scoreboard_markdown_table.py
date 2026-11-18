"""Tests for markdown table parser."""
import pytest
from scoreboard_eval.markdown_table import MarkdownTable


def test_simple_table_parsing():
    """Test case 3: Parse a simple markdown table."""
    content = [
        "| Name | Value |",
        "|---|---|",
        "| Test | 1.0 |",
        "| Demo | 2.0 |",
    ]

    table = MarkdownTable(content)

    assert table.headers == ['Name', 'Value']
    assert len(table.rows) == 2
    assert table.rows[0] == {'Name': 'Test', 'Value': '1.0'}
    assert table.rows[1] == {'Name': 'Demo', 'Value': '2.0'}


def test_table_with_whitespace():
    """Test case 4: Handle extra whitespace in table."""
    content = [
        "|  Name  |  Value  |",
        "|---|---|",
        "|  Test  |  1.0  |",
    ]

    table = MarkdownTable(content)

    assert table.headers == ['Name', 'Value']
    assert table.rows[0] == {'Name': 'Test', 'Value': '1.0'}


def test_get_column():
    """Test case 5: Get a column by header."""
    content = [
        "| Engine | WER |",
        "|---|---|",
        "| Engine1 | 10% |",
        "| Engine2 | 20% |",
    ]

    table = MarkdownTable(content)

    wer_col = table.get_column('WER')
    assert wer_col == ['10%', '20%']


def test_find_rows_with_header_value():
    """Test case 6: Find rows matching a criterion."""
    content = [
        "| Language | Engine | WER |",
        "|---|---|---|",
        "| English | Engine1 | 10% |",
        "| Spanish | Engine1 | 15% |",
        "| English | Engine2 | 12% |",
    ]

    table = MarkdownTable(content)

    english_rows = table.find_rows_with_header_value('Language', 'English')
    assert len(english_rows) == 2
    assert english_rows[0]['Engine'] == 'Engine1'
    assert english_rows[1]['Engine'] == 'Engine2'


def test_extract_all_tables():
    """Test case 7: Extract multiple tables from markdown content."""
    content = """
# Report

## Section 1

| A | B |
|---|---|
| 1 | 2 |

Some text here.

## Section 2

| X | Y |
|---|---|
| 3 | 4 |
"""

    tables = MarkdownTable.extract_all_tables(content)

    assert len(tables) == 2
    assert tables[0].headers == ['A', 'B']
    assert tables[1].headers == ['X', 'Y']


def test_table_separated_by_blank_line():
    """Test case 3: Two tables separated by blank line are distinct."""
    content = """
| A | B |
|---|---|
| 1 | 2 |

| X | Y |
|---|---|
| 3 | 4 |
"""

    tables = MarkdownTable.extract_all_tables(content)

    # Blank line should separate tables, not merge them
    assert len(tables) == 2
    assert tables[0].headers == ['A', 'B']
    assert tables[0].rows == [{'A': '1', 'B': '2'}]
    assert tables[1].headers == ['X', 'Y']
    assert tables[1].rows == [{'X': '3', 'Y': '4'}]


def test_invalid_table_missing_separator():
    """Test case 8: Raise error for table without separator."""
    content = [
        "| Name | Value |",
        "| Test | 1.0 |",
    ]

    with pytest.raises(ValueError, match="Expected separator line"):
        MarkdownTable(content)


def test_duplicate_headers():
    """Test case 9: Handle duplicate headers in a table (duplicate-header-aware)."""
    content = [
        "| Engine | WER | WER |",
        "|---|---|---|",
        "| Engine1 | 10% | 15% |",
    ]

    table = MarkdownTable(content)

    # Should store duplicate header values as a list
    assert table.rows[0]['Engine'] == 'Engine1'
    wer_value = table.rows[0]['WER']
    # Both WER values should be preserved
    assert isinstance(wer_value, list)
    assert wer_value == ['10%', '15%']


def test_table_with_empty_cells():
    """Test case 10: Handle tables with empty cells."""
    content = [
        "| Engine | WER | Note |",
        "|---|---|---|",
        "| Engine1 | 10% | |",
        "| Engine2 | | missing data |",
    ]

    table = MarkdownTable(content)

    assert table.rows[0]['Note'] == ''
    assert table.rows[1]['WER'] == ''


def test_table_mismatched_cell_count_warns():
    """Test case 7 (fix verification): Warn when row has wrong cell count."""
    content = [
        "| Engine | WER | CER |",
        "|---|---|---|",
        "| Engine1 | 10% | 5% |",
        "| Engine2 | 20% |",  # Missing one cell
        "| Engine3 | 30% | 15% | extra |",  # Extra cell
    ]

    with pytest.warns(UserWarning, match="mismatched cell count"):
        table = MarkdownTable(content)

    # Should only have the valid row
    assert len(table.rows) == 1
    assert table.rows[0]['Engine'] == 'Engine1'


def test_table_raw_rows_preserves_column_order():
    """Test that raw_rows() preserves column order and structure."""
    content = [
        "| Build | CER | WER | Size |",
        "|---|---|---|---|",
        "| build1 | 2.4% | 4.9% | 100MB |",
        "| build2 | 3.1% | 6.2% | 150MB |",
    ]

    table = MarkdownTable(content)
    raw = table.raw_rows()

    assert len(raw) == 2
    assert raw[0] == ['build1', '2.4%', '4.9%', '100MB']
    assert raw[1] == ['build2', '3.1%', '6.2%', '150MB']
