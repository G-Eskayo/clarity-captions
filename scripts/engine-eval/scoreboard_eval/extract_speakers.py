"""Extract speaker diarization rows from JSON and markdown files."""
from __future__ import annotations

import json
from pathlib import Path
from scoreboard_eval.row import ScoreboardRow, normalize_percentage
from scoreboard_eval.extract_captions import parse_markdown_table


def extract_speakers(perf_dir: Path) -> list[ScoreboardRow]:
    """Extract DER rows from speaker scoreboards and Android engine comparisons."""
    result = []

    # Handle speaker-scoreboard.md markdown file
    md_path = perf_dir / "speaker-scoreboard.md"
    if md_path.exists():
        text = md_path.read_text()
        rows = parse_markdown_table(text, "## Scoreboard")

        for row in rows:
            engine = row.get("Engine", "").strip()
            test_set = row.get("Test Set", "").strip()
            der_str = row.get("DER", "").strip()
            der_value = normalize_percentage(der_str) if der_str else None

            if der_value is not None:
                result.append(ScoreboardRow(
                    task="Speakers",
                    language="English",
                    language_code="en",
                    engine=engine,
                    platform="iOS/macOS",
                    test_set=test_set,
                    metric_name="DER",
                    metric_value=der_value,
                    ci_low=None,
                    ci_high=None,
                    lag_ms=None,
                    size_bytes=None,
                    zipped_bytes=None,
                    memory_bytes=None,
                    heat=None,
                    speed_x_realtime=None,
                    source_ticket=None,
                    source_file="speaker-scoreboard.md",
                    note=None,
                ))

    # Handle speaker-scoreboard-*.json variant files
    json_files = [
        ("speaker-scoreboard-fp16-chime6.json", "Sortformer fp16", "chime6"),
        ("speaker-scoreboard-fp16-ami.json", "Sortformer fp16", "ami"),
        ("speaker-scoreboard-pal6-chime6.json", "Sortformer pal6", "chime6"),
        ("speaker-scoreboard-pal6-ami.json", "Sortformer pal6", "ami"),
        ("speaker-scoreboard-pal8-chime6.json", "Sortformer pal8", "chime6"),
        ("speaker-scoreboard-pal8-ami.json", "Sortformer pal8", "ami"),
    ]

    for json_name, engine_name, test_set in json_files:
        json_path = perf_dir / json_name
        if not json_path.exists():
            continue

        data = json.loads(json_path.read_text())
        der_live = data.get("der_live", {})
        der_value = der_live.get("value")

        if der_value is not None:
            der_norm = der_value / 100 if isinstance(der_value, (int, float)) else None
            result.append(ScoreboardRow(
                task="Speakers",
                language="English",
                language_code="en",
                engine=engine_name,
                platform="iOS/macOS",
                test_set=test_set,
                metric_name="DER",
                metric_value=der_norm,
                ci_low=None,
                ci_high=None,
                lag_ms=None,
                size_bytes=None,
                zipped_bytes=None,
                memory_bytes=None,
                heat=None,
                speed_x_realtime=None,
                source_ticket=None,
                source_file=json_name,
                note=None,
            ))

    android_md = perf_dir / "speaker-android-engines.md"
    if android_md.exists():
        text = android_md.read_text()
        rows = parse_markdown_table(text, "## Engines")

        for row in rows:
            engine = row.get("Engine", "").strip()
            der_str = row.get("DER", "").strip()
            der = normalize_percentage(der_str)

            if der is not None:
                result.append(ScoreboardRow(
                    task="Speakers",
                    language="English",
                    language_code="en",
                    engine=engine,
                    platform="Android",
                    test_set="chime6",
                    metric_name="DER",
                    metric_value=der,
                    ci_low=None,
                    ci_high=None,
                    lag_ms=None,
                    size_bytes=None,
                    zipped_bytes=None,
                    memory_bytes=None,
                    heat=None,
                    speed_x_realtime=None,
                    source_ticket=None,
                    source_file="speaker-android-engines.md",
                    note=None,
                ))

    return result
