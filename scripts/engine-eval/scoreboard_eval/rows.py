"""Data structures for scoreboard rows and exceptions."""
from dataclasses import dataclass
from typing import Optional


class ScoreboardSourceMissing(Exception):
    """Raised when a required source file or section is missing."""
    pass


@dataclass(frozen=True)
class ScenarioRow:
    """A single test result row combining engine/model/language/condition."""
    dataset: str  # e.g., "EdAcc", "Spanish", "Hebrew (ivrit.ai eval-d1)", "Translation"
    engine: str  # e.g., "parakeet-fluidaudio (parakeet-ultra-coreml)"
    model: Optional[str]  # e.g., "parakeet-ultra-coreml", None if derived from engine
    language: str  # e.g., "English", "Spanish", "French", "Hebrew", "Indonesian"
    condition: Optional[str]  # e.g., "overall", "by accent", "by clip length", None
    metric: str  # e.g., "WER", "chrF", "latency_ms"
    value: str  # Formatted value with CI if applicable, e.g., "13.8% (12.7%–14.7%)"
    source_file: str  # e.g., "docs/perf/engine-accuracy-comparison.md"
    source_section: str  # e.g., "## Overall"
    order: int  # Line number in source, for stable sorting
