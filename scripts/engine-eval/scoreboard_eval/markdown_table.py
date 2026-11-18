"""Parse and extract data from markdown tables."""
import re
from typing import Any, Dict, List, Optional


class MarkdownTable:
    """Header-indexed, duplicate-header-aware markdown table parser."""

    def __init__(self, lines: List[str], start_line: int = 0):
        """Parse a markdown table from lines.

        Args:
            lines: Lines of markdown text, starting with or containing a table
            start_line: Line number of the first line (for tracking source)

        Raises:
            ValueError: If no valid table is found
        """
        self.lines = lines
        self.start_line = start_line
        self.headers: List[str] = []
        self.rows: List[Dict[str, Any]] = []
        self._parse()

    def _parse(self) -> None:
        """Parse the markdown table from lines."""
        # Find the header line (first line that looks like a table row)
        header_idx = None
        for i, line in enumerate(self.lines):
            if '|' in line:
                header_idx = i
                break

        if header_idx is None:
            raise ValueError("No table found in lines")

        # Parse headers
        header_line = self.lines[header_idx].strip()
        self.headers = [h.strip() for h in header_line.split('|')[1:-1]]

        # Find and skip the separator line
        sep_idx = header_idx + 1
        if sep_idx < len(self.lines):
            sep_line = self.lines[sep_idx].strip()
            if not self._is_separator_line(sep_line):
                raise ValueError("Expected separator line after headers")

        # Parse data rows until blank line or non-table line
        for i in range(sep_idx + 1, len(self.lines)):
            line = self.lines[i]
            # Blank line ends the table
            if not line.strip():
                break
            # Non-table line ends the table
            if '|' not in line:
                break
            # Skip separator lines within the table
            if self._is_separator_line(line.strip()):
                continue

            cells = [c.strip() for c in line.strip().split('|')[1:-1]]
            if len(cells) != len(self.headers):
                # Row has mismatched cell count; log warning and skip
                import warnings
                warnings.warn(
                    f"Row {i} has {len(cells)} cells but {len(self.headers)} headers; skipping",
                    stacklevel=3
                )
                continue

            # Handle duplicate headers by storing as list of values per header
            row_dict: Dict[str, Any] = {}
            for header, cell in zip(self.headers, cells):
                if header in row_dict:
                    # Duplicate header: store as list of values
                    if not isinstance(row_dict[header], list):
                        row_dict[header] = [row_dict[header]]
                    row_dict[header].append(cell)
                else:
                    row_dict[header] = cell
            self.rows.append(row_dict)

    @staticmethod
    def _is_separator_line(line: str) -> bool:
        """Check if a line is a markdown table separator."""
        # Separator lines contain only |, -, :, and spaces
        return all(c in '|-: ' for c in line)

    def get_column(self, header: str) -> List[Any]:
        """Get all values from a column by header name.

        Returns a list of values. If a header is duplicated in a row,
        the value at that position is a list; otherwise it's a string.
        """
        if header not in self.headers:
            return []
        return [row.get(header, '') for row in self.rows]

    def find_rows_with_header_value(self, header: str, value: str) -> List[Dict[str, str]]:
        """Find rows where a column matches a value."""
        return [row for row in self.rows if row.get(header, '') == value]

    def to_dict_list(self) -> List[Dict[str, str]]:
        """Return rows as list of dictionaries."""
        return self.rows

    def raw_rows(self) -> List[List[str]]:
        """Return raw rows as lists of cell values, without header mapping.

        This is useful when you need to understand the column structure
        (e.g., dataset prefixes in adjacent columns). Returns the raw
        cell values in their original order.
        """
        result = []
        # Re-parse to get raw cells without the duplicate-header merging
        lines = self.lines
        if not lines:
            return result

        # Find header and separator
        header_idx = None
        for i, line in enumerate(lines):
            if '|' in line:
                header_idx = i
                break

        if header_idx is None:
            return result

        sep_idx = header_idx + 1

        # Collect raw rows
        for i in range(sep_idx + 1, len(lines)):
            line = lines[i]
            if not line.strip() or '|' not in line:
                break
            if self._is_separator_line(line.strip()):
                continue

            cells = [c.strip() for c in line.strip().split('|')[1:-1]]
            if len(cells) == len(self.headers):
                result.append(cells)

        return result

    @staticmethod
    def extract_all_tables(content: str) -> List['MarkdownTable']:
        """Extract all tables from markdown content.

        Returns a list of MarkdownTable objects, each representing a table.
        Blank lines separate tables.
        """
        lines = content.split('\n')
        tables = []
        i = 0

        while i < len(lines):
            if '|' in lines[i]:
                # Found start of a table, collect lines until blank line or non-table content
                table_lines = []
                start = i
                while i < len(lines):
                    line = lines[i]
                    # Blank line ends the table
                    if not line.strip():
                        i += 1
                        break
                    # Non-table line ends the table
                    if '|' not in line:
                        break
                    table_lines.append(line)
                    i += 1

                if table_lines:
                    try:
                        table = MarkdownTable(table_lines, start_line=start)
                        tables.append(table)
                    except ValueError:
                        pass
            else:
                i += 1

        return tables
