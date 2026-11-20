"""Extract voice latency rows from JSON files."""
from __future__ import annotations

import json
from pathlib import Path
from scoreboard_eval.row import ScoreboardRow


def extract_voices(perf_dir: Path) -> list[ScoreboardRow]:
    """Read lag JSON files for voice/ear translation lag-only rows."""
    result = []

    files = [
        ("ear-translation/finish-lag-mac.json", "Ear Translation", "macOS"),
        ("ear-translation/lag-mac.json", "Voice", "macOS"),
        ("lag-mac.json", "Voice", "macOS"),
        ("simulator-iphone.json", "Voice", "iOS"),
    ]

    for json_name, task, platform in files:
        json_path = perf_dir / json_name
        if not json_path.exists():
            continue

        data = json.loads(json_path.read_text())

        for item in data if isinstance(data, list) else [data]:
            engine = item.get("engine", "")
            language = item.get("language", "")
            language_code = item.get("code", "")
            median_lag = item.get("median_ms")
            p95_lag = item.get("p95_ms")

            note = None
            if p95_lag is not None:
                note = f"p95 lag: {p95_lag} ms"

            result.append(ScoreboardRow(
                task=task,
                language=language,
                language_code=language_code,
                engine=engine,
                platform=platform,
                test_set="latency",
                metric_name="lag_ms",
                metric_value=median_lag,
                ci_low=None,
                ci_high=None,
                lag_ms=median_lag,
                size_bytes=None,
                zipped_bytes=None,
                memory_bytes=None,
                heat=None,
                speed_x_realtime=None,
                source_ticket=None,
                source_file=json_name,
                note=note,
            ))

    return result
