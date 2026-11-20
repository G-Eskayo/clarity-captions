"""ScoreboardRow dataclass and unit normalizers."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class ScoreboardRow:
    """One performance measurement across all dimensions."""
    task: str  # Captions, Translation, Voices, Speakers
    language: str
    language_code: str
    engine: str
    platform: str  # iOS, macOS, Android
    test_set: str  # EdAcc, FLEURS, etc
    metric_name: str  # WER, CER, lag_ms, DER, etc
    metric_value: float | None
    ci_low: float | None
    ci_high: float | None
    lag_ms: float | None
    size_bytes: int | None
    zipped_bytes: int | None
    memory_bytes: int | None
    heat: str | None  # thermal state if relevant
    speed_x_realtime: float | None
    source_ticket: str | None
    source_file: str
    note: str | None


def normalize_bytes(value: str) -> int | None:
    """Parse "123 MB", "456 KiB", "789 bytes" to bytes."""
    if not value or value == "–":
        return None
    value = value.strip()
    units = [("GiB", 1024 ** 3), ("MiB", 1024 * 1024), ("KiB", 1024),
             ("GB", 1000000000), ("MB", 1000000), ("KB", 1000), ("bytes", 1), ("B", 1)]
    for unit, mult in units:
        if value.endswith(unit):
            try:
                return int(float(value[:-len(unit)].strip()) * mult)
            except ValueError:
                return None
    return None


def normalize_ci(value: str) -> tuple[float | None, float | None]:
    """Parse confidence interval: 'X – Y' or 'X to Y' or '[lo, hi]'."""
    if not value or value == "–":
        return None, None
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].split(",")
        try:
            return float(inner[0].strip().rstrip("%")) / 100, float(inner[1].strip().rstrip("%")) / 100
        except (ValueError, IndexError):
            return None, None
    for sep in [" – ", " to "]:
        if sep in value:
            parts = value.split(sep)
            try:
                lo = float(parts[0].strip().rstrip("%")) / 100
                hi = float(parts[1].strip().rstrip("%")) / 100
                return lo, hi
            except ValueError:
                return None, None
    return None, None


def normalize_percentage(value: str) -> float | None:
    """Parse 'X.Y%' to decimal (0.0–1.0)."""
    if not value or value == "–":
        return None
    try:
        return float(value.strip().rstrip("%")) / 100
    except ValueError:
        return None
