"""#160: the paired comparison of two engines on the same recordings (engine minus baseline), trying to break it."""
import math

import pytest

from speaker_eval.der import DerCounts
from speaker_eval.score import RecScore
from speaker_onnx.paired import paired_bootstrap, paired_summary


def rec(name, live_err, ref=1000, bare_err=None, split=(False,)):
    d = lambda e: DerCounts(ref, e, 0, 0)
    return RecScore(recording=name, live=d(live_err), raw=d(live_err), bare=d(live_err if bare_err is None else bare_err),
                    floor=d(0), ref_speakers=4, shown_speakers=4, bare_speakers=4,
                    monologues=[(s, 1.0) for s in split], first_label_s=1.0, line_delays=[0.5], unlabeled_lines=0,
                    lines=10, audio_s=600, wall_s=600, chunk_p95_ms=1, chunk_max_ms=1, chunk_audio_ms=85,
                    peak_mb=100, load_s=1)


def pooled_live(rs):
    t = DerCounts(0, 0, 0, 0)
    for r in rs:
        t = t + r.live
    return t.der


def test_same_engine_twice_differs_by_exactly_zero():
    a = [rec(f"r{i}", 100 + 50 * i) for i in range(8)]
    v, (lo, hi) = paired_bootstrap(a, a, pooled_live)
    assert v == 0 and lo == 0 and hi == 0


def test_a_constant_shift_is_found_with_a_tight_interval():
    """Unpaired, the spread between recordings would swamp a 5-point shift; paired, it is the whole story."""
    base = [rec(f"r{i}", 100 + 100 * i) for i in range(8)]
    eng = [rec(f"r{i}", 150 + 100 * i) for i in range(8)]
    v, (lo, hi) = paired_bootstrap(eng, base, pooled_live)
    assert v == pytest.approx(0.05)
    assert lo == pytest.approx(0.05) and hi == pytest.approx(0.05)


def test_resampling_is_joint_not_independent():
    """One recording much worse on the engine: the interval must reach zero-ish and the value, never go negative."""
    base = [rec(f"r{i}", 200) for i in range(10)]
    eng = [rec(f"r{i}", 200) for i in range(9)] + [rec("r9", 700)]
    v, (lo, hi) = paired_bootstrap(eng, base, pooled_live)
    assert v == pytest.approx(0.05)
    assert lo >= 0 and hi > v


def test_recordings_are_matched_by_name_not_order():
    base = [rec("a", 100), rec("b", 300)]
    eng = [rec("b", 300), rec("a", 100)]
    v, (lo, hi) = paired_bootstrap(eng, base, pooled_live)
    assert v == 0 and lo == 0 and hi == 0


def test_a_recording_missing_from_either_side_is_refused():
    with pytest.raises(ValueError, match="c"):
        paired_bootstrap([rec("a", 1), rec("c", 1)], [rec("a", 1)], pooled_live)


def test_summary_has_the_differences_the_writeup_reports():
    base = [rec(f"r{i}", 100, bare_err=300, split=(False, True)) for i in range(4)]
    eng = [rec(f"r{i}", 200, bare_err=300, split=(True, True)) for i in range(4)]
    s = paired_summary(eng, base)
    assert s["recordings"] == 4
    assert s["der_live_diff"]["value"] == pytest.approx(0.10)
    assert s["der_bare_diff"]["value"] == pytest.approx(0.0)
    assert s["monologue_split_rate_diff"]["value"] == pytest.approx(0.5)
    for k in ("der_live_diff", "der_bare_diff", "monologue_split_rate_diff"):
        lo, hi = s[k]["ci95"]
        assert not math.isnan(lo) and lo <= s[k]["value"] <= hi
