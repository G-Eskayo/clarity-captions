"""Extract Hebrew comparison results from hebrew-accuracy-comparison.md and hebrew-coreml-comparison.md."""
import re
from typing import List
from .rows import ScenarioRow, ScoreboardSourceMissing
from .markdown_table import MarkdownTable


def extract_hebrew(accuracy_content: str, coreml_content: str) -> List[ScenarioRow]:
    """Extract Hebrew accuracy results from both comparison files.

    Args:
        accuracy_content: Content from hebrew-accuracy-comparison.md
        coreml_content: Content from hebrew-coreml-comparison.md

    Returns:
        List of ScenarioRow objects

    Raises:
        ScoreboardSourceMissing: If required sections are missing
    """
    rows = []
    order_counter = 0

    # Extract from hebrew-accuracy-comparison.md
    accuracy_rows = _parse_accuracy_file(accuracy_content, order_counter)
    rows.extend(accuracy_rows)
    order_counter += len(accuracy_rows)

    # Extract from hebrew-coreml-comparison.md
    coreml_rows = _parse_coreml_file(coreml_content, order_counter)
    rows.extend(coreml_rows)
    order_counter += len(coreml_rows)

    return rows


def _parse_accuracy_file(content: str, order_start: int) -> List[ScenarioRow]:
    """Parse hebrew-accuracy-comparison.md dataset tables."""
    rows = []
    order_counter = order_start

    lines = content.split('\n')

    # Find dataset sections: ivrit.ai eval-d1, ivrit.ai eval-whatsapp, FLEURS he
    dataset_sections = [
        ('## ivrit.ai eval-d1 (conversation)', 'Hebrew (ivrit.ai eval-d1)'),
        ('## ivrit.ai eval-whatsapp (voice notes)', 'Hebrew (ivrit.ai eval-whatsapp)'),
        ('## FLEURS he (read speech)', 'Hebrew (FLEURS he)'),
    ]

    for section_header, dataset_name in dataset_sections:
        for i, line in enumerate(lines):
            if line.startswith(section_header):
                # Find the next section header
                end_i = len(lines)
                for j in range(i + 1, len(lines)):
                    if lines[j].startswith('## '):
                        end_i = j
                        break

                section_content = '\n'.join(lines[i:end_i])
                section_rows = _parse_hebrew_section(section_content, dataset_name, order_counter)
                rows.extend(section_rows)
                order_counter += len(section_rows)
                break

    return rows


def _parse_hebrew_section(content: str, dataset: str, order_start: int) -> List[ScenarioRow]:
    """Parse a single Hebrew dataset section (accuracy comparison)."""
    rows = []
    tables = MarkdownTable.extract_all_tables(content)

    if not tables:
        return rows

    table = tables[0]
    order_counter = order_start

    for row_data in table.to_dict_list():
        engine = row_data.get('Engine', '')
        wer = row_data.get('WER', '')
        ci = row_data.get('95% CI', '')

        if ci:
            wer_value = f"{wer} ({ci})"
        else:
            wer_value = wer

        model = None
        model_match = re.search(r'\(([^)]+)\)', engine)
        if model_match:
            model = model_match.group(1)

        # Add WER row
        rows.append(ScenarioRow(
            dataset=dataset,
            engine=engine,
            model=model,
            language='Hebrew',
            condition=None,
            metric='WER',
            value=wer_value,
            source_file='docs/perf/hebrew-accuracy-comparison.md',
            source_section=f'## {dataset}',
            order=order_counter
        ))
        order_counter += 1

        # Add CER row if available
        cer = row_data.get('CER', '')
        if cer:
            rows.append(ScenarioRow(
                dataset=dataset,
                engine=engine,
                model=model,
                language='Hebrew',
                condition=None,
                metric='CER',
                value=cer,
                source_file='docs/perf/hebrew-accuracy-comparison.md',
                source_section=f'## {dataset}',
                order=order_counter
            ))
            order_counter += 1

    return rows


def _parse_coreml_file(content: str, order_start: int) -> List[ScenarioRow]:
    """Parse hebrew-coreml-comparison.md build table with accuracy results."""
    rows = []

    # Extract the first table (build/size/accuracy), skip latency section
    tables = MarkdownTable.extract_all_tables(content)
    if not tables:
        return rows

    # The first table in the file is the build table with accuracy data
    table = tables[0]
    order_counter = order_start

    # Build a mapping of column indices to dataset names
    # Headers like "ivrit.ai eval-d1 (conversation) CER" have dataset prefixes
    # Bare headers like "WER" inherit the prefix from the previous column
    dataset_by_col = _build_dataset_column_map(table.headers)

    # Use raw rows to maintain column order and understand dataset context
    raw_rows = table.raw_rows()
    dict_rows = table.to_dict_list()

    for raw_cells, row_data in zip(raw_rows, dict_rows):
        build = row_data.get('Build', '')
        size_mb = row_data.get('Size on disk', '')

        # Add size row
        if size_mb:
            rows.append(ScenarioRow(
                dataset='Hebrew (coreml builds)',
                engine=build,
                model=None,
                language='Hebrew',
                condition=None,
                metric='size_mb',
                value=size_mb,
                source_file='docs/perf/hebrew-coreml-comparison.md',
                source_section='Build table (compressed builds #220)',
                order=order_counter
            ))
            order_counter += 1

        # Extract accuracy metrics using column context to track datasets
        for col_idx, (header, cell_value) in enumerate(zip(table.headers, raw_cells)):
            if not cell_value or cell_value in ('CER', 'WER'):
                continue  # Skip empty, header text

            # Extract metric and dataset from column index
            metric = _extract_metric_from_header(header)
            dataset = dataset_by_col.get(col_idx, 'Hebrew (coreml builds)')

            if metric and cell_value:
                rows.append(ScenarioRow(
                    dataset=dataset,
                    engine=build,
                    model=None,
                    language='Hebrew',
                    condition=None,
                    metric=metric,
                    value=cell_value,
                    source_file='docs/perf/hebrew-coreml-comparison.md',
                    source_section='Build table (compressed builds #220)',
                    order=order_counter
                ))
                order_counter += 1

    return rows


def _build_dataset_column_map(headers: List[str]) -> dict:
    """Map column indices to their dataset context.

    Headers like "ivrit.ai eval-d1 (conversation) CER" have explicit dataset names.
    Bare headers like "WER" inherit from the preceding column with a dataset name.

    Returns dict mapping column index -> dataset name.
    """
    dataset_by_col = {}
    current_dataset = 'Hebrew (coreml builds)'

    for i, header in enumerate(headers):
        # Check if this header has a dataset prefix (ends with a metric)
        if header.endswith(('CER', 'WER')):
            # Extract dataset name: everything except the final metric
            if ' CER' in header:
                dataset = header.rsplit(' CER', 1)[0]
            elif ' WER' in header:
                dataset = header.rsplit(' WER', 1)[0]
            else:
                dataset = current_dataset

            if dataset:
                current_dataset = dataset
                dataset_by_col[i] = dataset
            else:
                dataset_by_col[i] = current_dataset
        else:
            # Bare header (like "WER" or "Size on disk") - use current context
            dataset_by_col[i] = current_dataset

    return dataset_by_col


def _extract_metric_from_header(header: str) -> str:
    """Extract metric name (WER, CER, size_mb) from a column header."""
    # Check for compound headers with dataset+metric
    if ' CER' in header:
        return 'CER'
    elif ' WER' in header:
        return 'WER'
    elif header == 'WER':
        return 'WER'
    elif header == 'CER':
        return 'CER'
    elif 'Size on disk' in header:
        return 'size_mb'
    elif 'Build' in header:
        return None
    elif 'Latency' in header or 'Memory' in header or 'Load' in header:
        return None  # Skip non-accuracy metrics

    return None
