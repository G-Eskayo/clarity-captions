"""Build the scoreboard by running all extractors."""
from __future__ import annotations

import json
from pathlib import Path
from typing import NamedTuple

from scoreboard_eval.row import ScoreboardRow
from scoreboard_eval.extract_captions import extract_captions
from scoreboard_eval.extract_hebrew import extract_hebrew
from scoreboard_eval.extract_translation import extract_translation
from scoreboard_eval.extract_voices import extract_voices
from scoreboard_eval.extract_speakers import extract_speakers


class BuildResult(NamedTuple):
    rows: list[ScoreboardRow]
    gaps: dict[str, str]


EXTRACTORS = [
    ("Captions", "engine-accuracy-comparison.md", extract_captions),
    ("Hebrew", "hebrew-accuracy-comparison.md", extract_hebrew),
    ("Translation", "translation-languages-results.json", extract_translation),
    ("Voices", "ear-translation/finish-lag-mac.json", extract_voices),
    ("Speakers", "speaker-scoreboard.md", extract_speakers),
]


def build_scoreboard(perf_dir: Path) -> BuildResult:
    """Extract all rows and report gaps/errors."""
    perf_dir = Path(perf_dir)
    rows = []
    gaps = {}

    for task_name, sentinel_file, extractor in EXTRACTORS:
        sentinel_path = perf_dir / sentinel_file

        if not sentinel_path.exists():
            gaps[task_name] = f"Missing {sentinel_file}"
            continue

        try:
            task_rows = extractor(perf_dir)
            rows.extend(task_rows)
        except (json.JSONDecodeError, ValueError, KeyError) as e:
            gaps[task_name] = f"Malformed {sentinel_file}: {e}"
        except IOError as e:
            gaps[task_name] = f"Cannot read {sentinel_file}: {e}"

    seen = set()
    for row in rows:
        key = (row.engine, row.language_code, row.test_set, row.metric_name, row.platform)
        if key in seen:
            raise ValueError(f"Duplicate row: {key}")
        seen.add(key)

    return BuildResult(rows=rows, gaps=gaps)
