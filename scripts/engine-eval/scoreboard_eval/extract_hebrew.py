"""Extract Hebrew engine rows from markdown tables."""
from __future__ import annotations

from pathlib import Path
from scoreboard_eval.row import ScoreboardRow, normalize_ci, normalize_percentage
from scoreboard_eval.extract_captions import parse_markdown_table


def extract_hebrew_coreml(perf_dir: Path) -> list[ScoreboardRow]:
    """Parse hebrew-coreml-comparison.md build accuracy table."""
    md_path = perf_dir / "hebrew-coreml-comparison.md"
    if not md_path.exists():
        return []

    text = md_path.read_text()
    text_lines = text.split("\n")
    result = []
    headers = None

    for i, line in enumerate(text_lines):
        if line.startswith("|") and "---" in line and headers is None:
            if i > 0 and text_lines[i-1].startswith("|"):
                headers = [h.strip() for h in text_lines[i-1].split("|")[1:-1]]
        elif headers and line.startswith("|") and "---" not in line:
            cells = [c.strip() for c in line.split("|")[1:-1]]
            if len(cells) != len(headers):
                continue

            row = dict(zip(headers, cells))
            build = row.get("Build", "").strip()
            size_str = row.get("Size on disk", "").strip()

            if not build or build == "Build":
                continue

            from scoreboard_eval.row import normalize_bytes
            size_bytes = normalize_bytes(size_str) if size_str else None

            for header in headers:
                if "CER" in header or "WER" in header:
                    metric = "CER" if "CER" in header else "WER"
                    metric_str = row.get(header, "").strip()

                    if not metric_str or metric_str == "–":
                        continue

                    metric_value = normalize_percentage(metric_str)
                    if metric_value is not None:
                        test_set = "eval-d1" if "eval-d1" in header else ("eval-whatsapp" if "eval-whatsapp" in header else "unknown")

                        result.append(ScoreboardRow(
                            task="Captions",
                            language="Hebrew",
                            language_code="he",
                            engine=build,
                            platform="iOS",
                            test_set=test_set,
                            metric_name=metric,
                            metric_value=metric_value,
                            ci_low=None,
                            ci_high=None,
                            lag_ms=None,
                            size_bytes=size_bytes,
                            zipped_bytes=None,
                            memory_bytes=None,
                            heat=None,
                            speed_x_realtime=None,
                            source_ticket="#220",
                            source_file="hebrew-coreml-comparison.md",
                            note="Core ML build comparison",
                        ))

    return result


def extract_hebrew(perf_dir: Path) -> list[ScoreboardRow]:
    """Parse hebrew-accuracy-comparison.md per-set tables."""
    md_path = perf_dir / "hebrew-accuracy-comparison.md"
    if not md_path.exists():
        return []

    text = md_path.read_text()
    result = []

    for section in ["## eval-d1", "## eval-whatsapp", "## eval-common"]:
        rows = parse_markdown_table(text, section)

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

            test_set = section.replace("## ", "")

            result.append(ScoreboardRow(
                task="Captions",
                language="Hebrew",
                language_code="he",
                engine=engine,
                platform="macOS",
                test_set=test_set,
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
                source_ticket="#201",
                source_file="hebrew-accuracy-comparison.md",
                note=None,
            ))

    return extract_hebrew_coreml(perf_dir) + result
