"""Extract translation results from translation-languages-results.json."""
import json
from typing import Any, Dict, List
from .rows import ScenarioRow, ScoreboardSourceMissing


def extract_translation(json_content: str) -> List[ScenarioRow]:
    """Extract translation results from translation-languages-results.json.

    Reshapes JSON array of language results into ScenarioRow objects.

    Args:
        json_content: JSON file content (string)

    Returns:
        List of ScenarioRow objects

    Raises:
        ScoreboardSourceMissing: If JSON is invalid
    """
    try:
        data = json.loads(json_content)
    except json.JSONDecodeError as e:
        raise ScoreboardSourceMissing(f"Invalid JSON in translation-languages-results.json: {e}")

    if not isinstance(data, list):
        raise ScoreboardSourceMissing("Expected JSON array in translation-languages-results.json")

    rows = []

    for idx, entry in enumerate(data):
        if not isinstance(entry, dict):
            continue

        language = entry.get('name', '')
        code = entry.get('code', '')
        chrf = entry.get('chrf')
        ci = entry.get('ci')
        comet = entry.get('comet')

        # Format chrF value with CI
        if chrf is not None and ci:
            chrf_str = f"{chrf:.1f}"
            ci_str = f"{ci[0]:.1f} to {ci[1]:.1f}"
            chrf_value = f"{chrf_str}% ({ci_str}%)"
        elif chrf is not None:
            chrf_value = f"{chrf:.1f}%"
        else:
            chrf_value = ""

        # Create row for chrF metric
        if chrf_value:
            rows.append(ScenarioRow(
                dataset=f'Translation ({language})',
                engine='Apple Translation',
                model=None,
                language=language,
                condition=None,
                metric='chrF',
                value=chrf_value,
                source_file='docs/perf/translation-languages-results.json',
                source_section='main',
                order=idx * 3
            ))

        # Create row for COMET metric
        if comet is not None:
            comet_value = f"{comet:.3f}"
            rows.append(ScenarioRow(
                dataset=f'Translation ({language})',
                engine='Apple Translation',
                model=None,
                language=language,
                condition=None,
                metric='COMET',
                value=comet_value,
                source_file='docs/perf/translation-languages-results.json',
                source_section='main',
                order=idx * 3 + 1
            ))

        # Create row for latency metric (median_ms)
        median_ms = entry.get('median_ms')
        if median_ms is not None:
            latency_value = f"{median_ms:.0f} ms"
            rows.append(ScenarioRow(
                dataset=f'Translation ({language})',
                engine='Apple Translation',
                model=None,
                language=language,
                condition=None,
                metric='latency_ms',
                value=latency_value,
                source_file='docs/perf/translation-languages-results.json',
                source_section='main',
                order=idx * 3 + 2
            ))

    return rows
