"""Render scoreboard data to markdown and JSON formats."""
import json
from typing import List, Dict, Any
from .build import Scoreboard
from .rows import ScenarioRow


def render_markdown(scoreboard: Scoreboard) -> str:
    """Render scoreboard as markdown.

    Produces a markdown document with tables organized by dataset.
    Includes a "Not covered yet" gaps section at the end.

    Args:
        scoreboard: The scoreboard to render

    Returns:
        Markdown string
    """
    lines = [
        "# Engine Scoreboard",
        "",
        "Unified comparison of engine accuracy, latency, and resource usage across datasets and languages.",
        "",
    ]

    # Group rows by dataset
    rows_by_dataset: Dict[str, List[ScenarioRow]] = {}
    for row in scoreboard.rows:
        if row.dataset not in rows_by_dataset:
            rows_by_dataset[row.dataset] = []
        rows_by_dataset[row.dataset].append(row)

    # Render each dataset section
    for dataset in sorted(rows_by_dataset.keys()):
        lines.append(f"## {dataset}")
        lines.append("")

        dataset_rows = rows_by_dataset[dataset]
        lines.extend(_render_dataset_table(dataset_rows))
        lines.append("")

    # Render gaps section
    if scoreboard.gaps:
        lines.append("## Not covered yet")
        lines.append("")
        for gap in scoreboard.gaps:
            lines.append(f"- {gap}")
        lines.append("")

    return '\n'.join(lines)


def _render_dataset_table(rows: List[ScenarioRow]) -> List[str]:
    """Render a table for rows in a single dataset."""
    lines = []

    # Group by condition/metric combo to decide table structure
    # For now, simple table with: Engine | Condition | Metric | Value

    # Get unique columns needed
    engines = sorted(set(r.engine for r in rows))
    languages = sorted(set(r.language for r in rows))
    metrics = sorted(set(r.metric for r in rows))
    conditions = sorted(set(r.condition or 'overall' for r in rows))

    # Simple rendering: rows are engines, columns are language/condition/metric combos
    if len(set(r.language for r in rows)) == 1 and len(metrics) == 1:
        # Single language, single metric: simple table
        lines.extend(_render_simple_table(rows))
    else:
        # Multi-metric or multi-language: more complex table or multiple tables
        lines.extend(_render_complex_table(rows))

    return lines


def _escape_pipe(text: str) -> str:
    """Escape pipe character in markdown table cell."""
    return text.replace('|', '\\|')


def _render_simple_table(rows: List[ScenarioRow]) -> List[str]:
    """Render a simple single-metric, single-language table."""
    lines = []

    # Get unique values
    engines = sorted(set(r.engine for r in rows))
    conditions = sorted(set(r.condition for r in rows if r.condition is not None))

    if not conditions:
        # No specific conditions, combine all rows by engine
        headers = ["Engine", "Value"]
        lines.append("| " + " | ".join(headers) + " |")
        lines.append("|---|---|")

        for engine in engines:
            engine_rows = [r for r in rows if r.engine == engine]
            if engine_rows:
                # Combine all values for this engine (different metrics, if present)
                values = [_escape_pipe(r.value) for r in engine_rows]
                combined_value = " | ".join(values) if len(values) > 1 else values[0]
                escaped_engine = _escape_pipe(engine)
                lines.append(f"| {escaped_engine} | {combined_value} |")
    else:
        # Multiple conditions, use as columns
        headers = ["Engine"] + conditions
        lines.append("| " + " | ".join(headers) + " |")
        lines.append("|" + "|".join(["---"] * len(headers)) + "|")

        for engine in engines:
            escaped_engine = _escape_pipe(engine)
            row_vals = [escaped_engine]
            for condition in conditions:
                matching = [r for r in rows if r.engine == engine and r.condition == condition]
                if matching:
                    # Combine all matching values (different metrics, if present)
                    values = [_escape_pipe(r.value) for r in matching]
                    combined_value = " | ".join(values) if len(values) > 1 else values[0]
                    row_vals.append(combined_value)
                else:
                    row_vals.append("–")
            lines.append("| " + " | ".join(row_vals) + " |")

    return lines


def _render_complex_table(rows: List[ScenarioRow]) -> List[str]:
    """Render a more complex multi-metric or multi-language table."""
    lines = []

    # For now, just render as a single table with all info
    headers = ["Engine", "Language", "Condition", "Metric", "Value"]
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("|" + "|".join(["---"] * len(headers)) + "|")

    for row in rows:
        condition = row.condition or "overall"
        escaped_engine = _escape_pipe(row.engine)
        escaped_language = _escape_pipe(row.language)
        escaped_condition = _escape_pipe(condition)
        escaped_metric = _escape_pipe(row.metric)
        escaped_value = _escape_pipe(row.value)
        lines.append(f"| {escaped_engine} | {escaped_language} | {escaped_condition} | {escaped_metric} | {escaped_value} |")

    return lines


def render_json(scoreboard: Scoreboard) -> str:
    """Render scoreboard as JSON.

    Produces a JSON object with rows and gaps.
    Output is sorted and stable.

    Args:
        scoreboard: The scoreboard to render

    Returns:
        JSON string
    """
    data = {
        "rows": [
            {
                "dataset": row.dataset,
                "engine": row.engine,
                "model": row.model,
                "language": row.language,
                "condition": row.condition,
                "metric": row.metric,
                "value": row.value,
                "source_file": row.source_file,
                "source_section": row.source_section,
            }
            for row in scoreboard.rows
        ],
        "gaps": scoreboard.gaps,
    }

    # Render with consistent formatting
    return json.dumps(data, indent=2, sort_keys=False)
