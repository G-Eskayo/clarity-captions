"""The calibration/test split, fixed once (#271). Calibration audio is never scored: every scoring path goes through
`require_test`, which refuses anything outside the set's test list. Each corpus is its own set, scored on its own."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

DEFAULT = Path(__file__).with_name("speaker_split.json")


class CalibrationLeak(ValueError):
    """A calibration recording reached the scorer, or a recording the split doesn't know."""


@dataclass(frozen=True)
class Split:
    calibration: frozenset[str]     # every set's calibration recordings
    test: tuple[str, ...]           # this set's test recordings

    def require_test(self, recording: str) -> None:
        if recording in self.calibration:
            raise CalibrationLeak(f"{recording} is calibration audio: it is never scored (#271)")
        if recording not in self.test:
            raise CalibrationLeak(f"{recording} is not in the frozen test list")


def load(path: Path = DEFAULT, set_name: str = "ami") -> Split:
    d = json.loads(Path(path).read_text())
    sets = d["sets"]
    cal_all: list[str] = [r for s in sets.values() for r in s["calibration"]]
    test_all: list[str] = [r for s in sets.values() for r in s["test"]]
    if len(set(cal_all)) != len(cal_all) or len(set(test_all)) != len(test_all):
        raise ValueError("duplicate recording in the split")
    if set(cal_all) & set(test_all):
        raise ValueError(f"recordings in both slices: {sorted(set(cal_all) & set(test_all))}")
    if set_name not in sets:
        raise ValueError(f"no set {set_name!r} (have {sorted(sets)})")
    return Split(frozenset(cal_all), tuple(sets[set_name]["test"]))
