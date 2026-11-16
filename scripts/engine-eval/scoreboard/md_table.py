"""Minimal GFM table parser for scoreboard markdown sources."""
from dataclasses import dataclass
from typing import Optional


@dataclass
class Table:
	"""One table parsed from markdown."""
	headers: list[str]
	rows: list[dict[str, Optional[str]]]


def parse_tables(text: str) -> list[Table]:
	"""Parse all GFM tables from markdown text.

	GFM tables: pipe-separated cells, with a `|---|` header separator line.
	A table with N headers expects exactly N cells per row.
	Rows with fewer cells than headers are skipped with no error.

	Returns list of Table (headers + rows). Empty list if no valid tables found.
	"""
	tables = []
	lines = text.splitlines()
	i = 0

	while i < len(lines):
		line = lines[i]

		# Look for a table: a line with pipes followed by a separator line
		if '|' not in line:
			i += 1
			continue

		# Try to parse header and separator
		header_line = line.strip()
		if not header_line.startswith('|') or not header_line.endswith('|'):
			i += 1
			continue

		# Look ahead for separator
		if i + 1 >= len(lines):
			i += 1
			continue

		sep_line = lines[i + 1].strip()
		if not _is_separator_line(sep_line):
			i += 1
			continue

		# Parse headers
		headers = _parse_row(header_line)
		if not headers:
			i += 1
			continue

		# Parse body rows until we hit a non-table line
		rows = []
		j = i + 2
		while j < len(lines):
			body_line = lines[j].strip()

			# Empty line or non-pipe line ends the table
			if not body_line or '|' not in body_line:
				break

			if not body_line.startswith('|') or not body_line.endswith('|'):
				break

			row_cells = _parse_row(body_line)
			# Skip rows with wrong cell count
			if row_cells and len(row_cells) == len(headers):
				row_dict = _map_cells_to_headers(headers, row_cells)
				rows.append(row_dict)

			j += 1

		tables.append(Table(headers=headers, rows=rows))
		i = j

	return tables


def _map_cells_to_headers(headers: list[str], cells: list[str]) -> dict[str, Optional[str]]:
	"""Map cells to headers, preserving repeated header names by appending an index.

	For example, if headers = ["Engine", "WER", "95% CI", "CER", "95% CI"],
	the second "95% CI" becomes "95% CI__2" to avoid collision.
	"""
	result = {}
	seen_names = {}
	for header, cell in zip(headers, cells):
		if header in seen_names:
			seen_names[header] += 1
			indexed_key = f"{header}__{seen_names[header]}"
		else:
			seen_names[header] = 1
			indexed_key = header
		result[indexed_key] = cell
	return result


def _is_separator_line(line: str) -> bool:
	"""Check if a line is a GFM table separator (|---|---|...).

	Must contain only |, -, :, and whitespace.
	Must have at least one | and at least one - in each cell.
	"""
	if not line or '|' not in line:
		return False

	# Remove pipes and check if remainder is all dashes/colons/whitespace
	# Each cell must have at least one dash
	parts = line.split('|')
	has_valid_cell = False
	for part in parts:
		part = part.strip()
		if not part:
			continue
		# Each cell must contain only dashes, colons, and whitespace
		if not all(c in '-: ' for c in part):
			return False
		# Each cell must have at least one dash
		if '-' in part:
			has_valid_cell = True

	return has_valid_cell


def _parse_row(line: str) -> list[str]:
	"""Parse a table row, returning cells as strings.

	Strips leading/trailing whitespace from each cell.
	Returns empty list if parsing fails.
	"""
	if not line or '|' not in line:
		return []

	# Remove leading/trailing pipes and split
	line = line.strip()
	if line.startswith('|'):
		line = line[1:]
	if line.endswith('|'):
		line = line[:-1]

	if not line:
		return []

	cells = [cell.strip() for cell in line.split('|')]
	return cells
