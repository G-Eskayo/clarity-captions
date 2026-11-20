"""Extract caption engine rows from markdown tables."""
from __future__ import annotations

import re
from pathlib import Path
from scoreboard_eval.row import ScoreboardRow, normalize_ci, normalize_percentage


def parse_markdown_table(text: str, section_name: str) -> list[dict]:
    """Parse a markdown table from section into list of dicts."""
    lines = text.split("\n")
    in_section = False
    in_table = False
    header_line = None
    rows = []

    for i, line in enumerate(lines):
        if section_name in line and line.startswith("#"):
            in_section = True
            continue
        if in_section and line.startswith("#") and section_name not in line:
            break

        if in_section and line.startswith("|"):
            in_table = True
            if "---" in line:
                if i > 0 and lines[i-1].startswith("|"):
                    header_line = lines[i-1]
            elif header_line is not None:
                cells = [c.strip() for c in line.split("|")[1:-1]]
                if len(cells) == len(header_line.split("|")[1:-1]):
                    rows.append(cells)
        elif in_table and line.strip() == "":
            in_table = False
            header_line = None

    headers = [h.strip() for h in header_line.split("|")[1:-1]] if header_line else []
    result = []
    for row in rows:
        result.append(dict(zip(headers, row)))
    return result


def extract_engine_accuracy(perf_dir: Path) -> list[ScoreboardRow]:
    """Parse engine-accuracy-comparison.md Overall table."""
    md_path = perf_dir / "engine-accuracy-comparison.md"
    if not md_path.exists():
        return []

    text = md_path.read_text()
    rows = parse_markdown_table(text, "## Overall")
    result = []

    for row in rows:
        engine = row.get("Engine", "").strip()
        wer_str = row.get("WER", "").strip()
        ci_str = row.get("95% CI", "").strip()
        speed_str = row.get("Speed (x real time)", "").strip()

        wer = normalize_percentage(wer_str)
        ci_lo, ci_hi = normalize_ci(ci_str)
        speed = None
        if speed_str and speed_str != "–":
            try:
                speed = float(speed_str.rstrip("x"))
            except ValueError:
                pass

        result.append(ScoreboardRow(
            task="Captions",
            language="English",
            language_code="en",
            engine=engine,
            platform="macOS",
            test_set="EdAcc",
            metric_name="WER",
            metric_value=wer,
            ci_low=ci_lo,
            ci_high=ci_hi,
            lag_ms=None,
            size_bytes=None,
            zipped_bytes=None,
            memory_bytes=None,
            heat=None,
            speed_x_realtime=speed,
            source_ticket="#145",
            source_file="engine-accuracy-comparison.md",
            note=None,
        ))

    return result


def extract_language_accuracy(perf_dir: Path) -> list[ScoreboardRow]:
    """Parse language-accuracy-comparison.md per-language tables."""
    md_path = perf_dir / "language-accuracy-comparison.md"
    if not md_path.exists():
        return []

    text = md_path.read_text()
    result = []

    for section in ["## Spanish", "## French", "## German", "## Italian", "## Portuguese"]:
        rows = parse_markdown_table(text, section)
        lang_map = {"Spanish": "es", "French": "fr", "German": "de", "Italian": "it", "Portuguese": "pt"}
        lang_name = section.split()[-1]
        lang_code = lang_map.get(lang_name, lang_name.lower()[:2])

        for row in rows:
            engine = row.get("Engine", "").strip()
            wer_str = row.get("WER", "").strip()
            ci_str = row.get("95% CI", "").strip()
            speed_str = row.get("Speed (x real time)", "").strip()

            wer = normalize_percentage(wer_str)
            ci_lo, ci_hi = normalize_ci(ci_str)
            speed = None
            if speed_str and speed_str != "–":
                try:
                    speed = float(speed_str.rstrip("x"))
                except ValueError:
                    pass

            result.append(ScoreboardRow(
                task="Captions",
                language=lang_name,
                language_code=lang_code,
                engine=engine,
                platform="macOS",
                test_set="FLEURS",
                metric_name="WER",
                metric_value=wer,
                ci_low=ci_lo,
                ci_high=ci_hi,
                lag_ms=None,
                size_bytes=None,
                zipped_bytes=None,
                memory_bytes=None,
                heat=None,
                speed_x_realtime=speed,
                source_ticket="#158",
                source_file="language-accuracy-comparison.md",
                note=None,
            ))

    return result


def extract_size_options(perf_dir: Path) -> list[ScoreboardRow]:
    """Parse engine-accuracy-comparison.md Size-options table."""
    md_path = perf_dir / "engine-accuracy-comparison.md"
    if not md_path.exists():
        return []

    text = md_path.read_text()
    rows = parse_markdown_table(text, "## Size-options")
    result = []

    for row in rows:
        engine = row.get("Build", "").strip()
        size_str = row.get("Size on disk", "").strip()
        wer_str = row.get("WER", "").strip()
        ci_str = row.get("95% CI", "").strip()

        from scoreboard_eval.row import normalize_bytes
        size_bytes = normalize_bytes(size_str) if size_str else None
        wer = normalize_percentage(wer_str)
        ci_lo, ci_hi = normalize_ci(ci_str)

        if engine and wer is not None:
            result.append(ScoreboardRow(
                task="Captions",
                language="English",
                language_code="en",
                engine=engine,
                platform="iOS",
                test_set="EdAcc",
                metric_name="WER",
                metric_value=wer,
                ci_low=ci_lo,
                ci_high=ci_hi,
                lag_ms=None,
                size_bytes=size_bytes,
                zipped_bytes=None,
                memory_bytes=None,
                heat=None,
                speed_x_realtime=None,
                source_ticket="#203",
                source_file="engine-accuracy-comparison.md",
                note="Size-options table",
            ))

    return result


def extract_captions(perf_dir: Path) -> list[ScoreboardRow]:
    """Extract all caption rows from perf_dir."""
    return (extract_engine_accuracy(perf_dir) +
            extract_language_accuracy(perf_dir) +
            extract_size_options(perf_dir))
