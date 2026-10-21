"""Append-only result lines: one JSON object per (clip, engine, model, repeat) (#145)."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, NamedTuple

REQUIRED = ("clip_id", "engine", "model", "repeat", "hypothesis", "audio_seconds", "processing_seconds")


class ResultKey(NamedTuple):
    clip_id: str
    engine: str
    model: str
    repeat: int


@dataclass
class LoadStats:
    lines: int = 0
    corrupt: int = 0
    duplicates: int = 0


def key_of(row: dict) -> ResultKey:
    return ResultKey(str(row["clip_id"]), str(row["engine"]), str(row["model"]), int(row["repeat"]))


def _parse(line: str) -> dict | None:
    line = line.strip()
    if not line:
        return None
    try:
        row = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(row, dict) or any(k not in row for k in REQUIRED):
        return None
    if not isinstance(row["hypothesis"], str):
        return None
    try:
        key_of(row)
        float(row["audio_seconds"]), float(row["processing_seconds"])
    except (TypeError, ValueError):
        return None
    return row


def load_results(paths: Iterable[Path]) -> tuple[list[dict], LoadStats]:
    """Valid rows in file order, first occurrence of each key wins; corrupt lines are counted and skipped."""
    stats = LoadStats()
    seen: set[ResultKey] = set()
    rows: list[dict] = []
    for path in paths:
        path = Path(path)
        if not path.exists():
            continue
        with path.open(encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if not raw.strip():
                    continue
                stats.lines += 1
                row = _parse(raw)
                if row is None:
                    stats.corrupt += 1
                    continue
                k = key_of(row)
                if k in seen:
                    stats.duplicates += 1
                    continue
                seen.add(k)
                rows.append(row)
    return rows, stats


def done_keys(path: Path) -> set[ResultKey]:
    rows, _ = load_results([path])
    return {key_of(r) for r in rows}
