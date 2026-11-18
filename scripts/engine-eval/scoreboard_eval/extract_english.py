"""Extract English engine comparison results from engine-accuracy-comparison.md."""
import re
from typing import List
from .rows import ScenarioRow, ScoreboardSourceMissing
from .markdown_table import MarkdownTable


def extract_english(content: str) -> List[ScenarioRow]:
    """Extract English engine accuracy results from engine-accuracy-comparison.md.

    Extracts data from:
    - ## Overall
    - ## Low-bit builds (#203)
    - ## Size options

    Args:
        content: Full markdown content

    Returns:
        List of ScenarioRow objects

    Raises:
        ScoreboardSourceMissing: If required sections are missing
    """
    rows = []
    order_counter = 0

    # Extract ## Overall section
    overall_section = _extract_section(content, "## Overall")
    if overall_section is None:
        raise ScoreboardSourceMissing("## Overall section not found in engine-accuracy-comparison.md")

    overall_rows = _parse_overall_section(overall_section[1], order_counter)
    rows.extend(overall_rows)
    order_counter += len(overall_rows)

    # Extract ## Low-bit builds (#203) section
    lowbit_section = _extract_section(content, "## Low-bit builds (#203)")
    if lowbit_section:
        lowbit_rows = _parse_lowbit_section(lowbit_section[1], order_counter)
        rows.extend(lowbit_rows)
        order_counter += len(lowbit_rows)

    # Extract ## Size options section
    size_section = _extract_section(content, "## Size options")
    if size_section:
        size_rows = _parse_size_section(size_section[1], order_counter)
        rows.extend(size_rows)
        order_counter += len(size_rows)

    return rows


def _extract_section(content: str, section_header: str) -> tuple[int, str] | None:
    """Extract content between a section header and the next section.

    Returns:
        Tuple of (line number of header, section content) or None
    """
    lines = content.split('\n')

    for i, line in enumerate(lines):
        if line.startswith(section_header):
            # Find the next section header
            end_i = len(lines)
            for j in range(i + 1, len(lines)):
                if lines[j].startswith('## '):
                    end_i = j
                    break

            section_content = '\n'.join(lines[i + 1:end_i])
            return (i, section_content)

    return None


def _parse_overall_section(content: str, order_start: int) -> List[ScenarioRow]:
    """Parse the Overall section table."""
    rows = []
    tables = MarkdownTable.extract_all_tables(content)

    if not tables:
        return rows

    table = tables[0]

    for idx, row_data in enumerate(table.to_dict_list()):
        engine = row_data.get('Engine', '')
        wer = row_data.get('WER', '')
        ci = row_data.get('95% CI', '')

        # Combine WER and CI into value field
        if ci:
            value = f"{wer} ({ci})"
        else:
            value = wer

        # Extract model from engine if present (in parentheses)
        model = None
        model_match = re.search(r'\(([^)]+)\)', engine)
        if model_match:
            model = model_match.group(1)

        rows.append(ScenarioRow(
            dataset='EdAcc',
            engine=engine,
            model=model,
            language='English',
            condition='overall',
            metric='WER',
            value=value,
            source_file='docs/perf/engine-accuracy-comparison.md',
            source_section='## Overall',
            order=order_start + idx
        ))

    return rows


def _parse_lowbit_section(content: str, order_start: int) -> List[ScenarioRow]:
    """Parse the Low-bit builds section."""
    rows = []
    tables = MarkdownTable.extract_all_tables(content)

    if not tables:
        return rows

    table = tables[0]

    for idx, row_data in enumerate(table.to_dict_list()):
        engine = row_data.get('Engine', '')
        wer = row_data.get('WER', '')
        ci = row_data.get('95% CI', '')

        if ci:
            value = f"{wer} ({ci})"
        else:
            value = wer

        model = None
        model_match = re.search(r'\(([^)]+)\)', engine)
        if model_match:
            model = model_match.group(1)

        rows.append(ScenarioRow(
            dataset='EdAcc',
            engine=engine,
            model=model,
            language='English',
            condition='low-bit builds',
            metric='WER',
            value=value,
            source_file='docs/perf/engine-accuracy-comparison.md',
            source_section='## Low-bit builds (#203)',
            order=order_start + idx
        ))

    return rows


def _parse_size_section(content: str, order_start: int) -> List[ScenarioRow]:
    """Parse the Size options section.

    Extracts size and memory metrics, not accuracy metrics.
    The Size options table shows model size tradeoffs and memory usage.
    """
    rows = []
    tables = MarkdownTable.extract_all_tables(content)

    if not tables:
        return rows

    table = tables[0]
    order_counter = order_start

    for row_data in table.to_dict_list():
        # Try various column names for engine/model
        engine = row_data.get('Engine', '') or row_data.get('Model', '')

        model = None
        model_match = re.search(r'\(([^)]+)\)', engine)
        if model_match:
            model = model_match.group(1)

        # Extract "On disk" size (first size column)
        on_disk_mb = row_data.get('On disk', '') or row_data.get('Size on disk', '')
        if on_disk_mb:
            rows.append(ScenarioRow(
                dataset='EdAcc',
                engine=engine,
                model=model,
                language='English',
                condition='size options',
                metric='on_disk_mb',
                value=on_disk_mb,
                source_file='docs/perf/engine-accuracy-comparison.md',
                source_section='## Size options',
                order=order_counter
            ))
            order_counter += 1

        # Extract "Zipped" size (compressed size)
        zipped_mb = row_data.get('Zipped', '')
        if zipped_mb:
            rows.append(ScenarioRow(
                dataset='EdAcc',
                engine=engine,
                model=model,
                language='English',
                condition='size options',
                metric='zipped_mb',
                value=zipped_mb,
                source_file='docs/perf/engine-accuracy-comparison.md',
                source_section='## Size options',
                order=order_counter
            ))
            order_counter += 1

        # Extract "Peak memory" column
        peak_memory_mb = row_data.get('Peak memory', '')
        if peak_memory_mb:
            rows.append(ScenarioRow(
                dataset='EdAcc',
                engine=engine,
                model=model,
                language='English',
                condition='size options',
                metric='peak_memory_mb',
                value=peak_memory_mb,
                source_file='docs/perf/engine-accuracy-comparison.md',
                source_section='## Size options',
                order=order_counter
            ))
            order_counter += 1

    return rows
