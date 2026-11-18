"""Build a unified scoreboard by grouping, sorting, and deduplicating results."""
from dataclasses import dataclass
from typing import List
from .rows import ScenarioRow


@dataclass
class Scoreboard:
    """A unified scoreboard with rows, gaps, and metadata."""
    rows: List[ScenarioRow]
    gaps: List[str]  # "Not covered yet" items


def build_scoreboard(
    rows: List[ScenarioRow],
    dedup_engine_identity: bool = False
) -> Scoreboard:
    """Build a scoreboard from extracted rows.

    Groups rows by dataset/engine/language, sorts consistently, and collects
    gaps (scenarios with no data).

    Engine identities are kept distinct to preserve information about
    different model variants and configurations.

    Args:
        rows: List of ScenarioRow objects from extractors
        dedup_engine_identity: Deprecated; kept for compatibility but ignored

    Returns:
        Scoreboard with rows and gaps
    """

    # Sort rows for stable, consistent output
    sorted_rows = sorted(rows, key=lambda r: (
        r.dataset,
        r.engine,
        r.language,
        r.condition or '',
        r.metric,
        r.order
    ))

    # Collect gaps (scenarios with no data)
    gaps = _collect_gaps(sorted_rows)

    return Scoreboard(
        rows=sorted_rows,
        gaps=gaps
    )


def _collect_gaps(rows: List[ScenarioRow]) -> List[str]:
    """Collect scenarios with no coverage (gaps in the scoreboard).

    Identifies missing evaluations based on known research priorities:
    - In-ear voice (captured speech during ear wear)
    - Speaker labels (who is speaking)
    - Android (non-iOS platforms)
    - Heat (device thermal performance under load)
    - Missing source files (evaluations not in the repo yet)

    Returns a list of descriptive strings for each gap, sorted and deduplicated.
    """
    gaps = []

    # Known gaps that are not yet evaluated
    gaps.append("In-ear voice evaluation (captured speech during active wear)")
    gaps.append("Speaker labels and multi-speaker scenarios")
    gaps.append("Android platform accuracy (non-iOS platforms)")
    gaps.append("Device thermal performance and heat dissipation")

    # Check for missing source files mentioned in rows but not present
    source_files = set(row.source_file for row in rows)
    expected_files = {
        'docs/perf/engine-accuracy-comparison.md',
        'docs/perf/language-accuracy-comparison.md',
        'docs/perf/hebrew-accuracy-comparison.md',
        'docs/perf/hebrew-coreml-comparison.md',
        'docs/perf/translation-languages-results.json',
    }
    missing_sources = expected_files - source_files
    for source in sorted(missing_sources):
        gaps.append(f"Missing source: {source}")

    return sorted(list(set(gaps)))
