"""Extract translation rows from JSON results and markdown comparisons."""
from __future__ import annotations

import json
from pathlib import Path
from scoreboard_eval.row import ScoreboardRow, normalize_bytes
from scoreboard_eval.extract_captions import parse_markdown_table


def extract_translation_speed(perf_dir: Path) -> list[ScoreboardRow]:
    """Extract lag and size from translation-comparison.md 'Speed, size and delivery' table."""
    md_path = perf_dir / "translation-comparison.md"
    if not md_path.exists():
        return []

    text = md_path.read_text()
    rows = parse_markdown_table(text, "## Speed, size and delivery")
    result = []

    for row in rows:
        engine = row.get("Engine (en-es)", "").strip()
        median_ms_str = row.get("Median ms per line", "").strip()
        p95_ms_str = row.get("p95 ms", "").strip()
        size_str = row.get("Size per pair", "").strip()

        if not engine or engine == "–":
            continue

        median_ms = None
        if median_ms_str and median_ms_str != "–":
            try:
                median_ms = float(median_ms_str)
            except ValueError:
                pass

        p95_ms = None
        if p95_ms_str and p95_ms_str != "–":
            try:
                p95_ms = float(p95_ms_str)
            except ValueError:
                pass

        size_bytes = normalize_bytes(size_str.split(",")[0].strip()) if size_str and "," in size_str else None

        note = None
        if p95_ms is not None:
            note = f"p95: {p95_ms} ms"

        result.append(ScoreboardRow(
            task="Translation",
            language="Spanish",
            language_code="es",
            engine=engine,
            platform="macOS",
            test_set="FLORES",
            metric_name="lag_ms",
            metric_value=median_ms,
            ci_low=None,
            ci_high=None,
            lag_ms=median_ms,
            size_bytes=size_bytes,
            zipped_bytes=None,
            memory_bytes=None,
            heat=None,
            speed_x_realtime=None,
            source_ticket="#159",
            source_file="translation-comparison.md",
            note=note,
        ))

    return result


def extract_translation(perf_dir: Path) -> list[ScoreboardRow]:
    """Read translation-languages-results.json for per-language rows and speed table."""
    json_path = perf_dir / "translation-languages-results.json"
    result = []

    if json_path.exists():
        data = json.loads(json_path.read_text())

        for item in data:
            code = item.get("code", "")
            name = item.get("name", "")
            chrf = item.get("chrf")
            ci = item.get("ci", [None, None])
            ci_lo, ci_hi = None, None
            if ci and len(ci) == 2:
                ci_lo = ci[0] / 100 if ci[0] else None
                ci_hi = ci[1] / 100 if ci[1] else None

            median_ms = item.get("median_ms")
            p95_ms = item.get("p95_ms")
            disk_bytes = item.get("disk_bytes")

            chrf_norm = chrf / 100 if chrf else None

            result.append(ScoreboardRow(
                task="Translation",
                language=name,
                language_code=code,
                engine="Apple Translation",
                platform="iOS/macOS",
                test_set="FLORES",
                metric_name="chrF",
                metric_value=chrf_norm,
                ci_low=ci_lo,
                ci_high=ci_hi,
                lag_ms=median_ms,
                size_bytes=disk_bytes,
                zipped_bytes=None,
                memory_bytes=None,
                heat=None,
                speed_x_realtime=None,
                source_ticket="#159",
                source_file="translation-languages-results.json",
                note=None,
            ))

    result.extend(extract_translation_speed(perf_dir))
    return result
