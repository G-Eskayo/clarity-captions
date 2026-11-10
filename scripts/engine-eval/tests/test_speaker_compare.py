"""A compressed build against fp16 on the same recordings: paired difference and the ticket's ship rule (#271)."""
import pytest

from speaker_eval.compare import Verdict, paired_bootstrap, ship_rule
from speaker_eval.der import DerCounts
from speaker_eval.score import RecScore, pooled


def rec(name, live_err, ref=1000, delays=(0.6,)):
    d = DerCounts(ref, live_err, 0, 0)
    return RecScore(recording=name, live=d, raw=d, bare=d, floor=d, ref_speakers=4, shown_speakers=4, bare_speakers=4,
                    monologues=[], first_label_s=1.0, line_delays=list(delays), unlabeled_lines=0, lines=1,
                    audio_s=60, wall_s=3, chunk_p95_ms=5, chunk_max_ms=9, chunk_audio_ms=85.3, peak_mb=100, load_s=0.2)


def test_identical_builds_differ_by_exactly_zero():
    base = [rec(f"r{i}", 100 + 10 * i) for i in range(8)]
    v, lo, hi = paired_bootstrap(base, base, lambda x: pooled(x, "live"))
    assert (v, lo, hi) == (0.0, 0.0, 0.0)


def test_a_uniformly_worse_build_has_a_ci_above_zero():
    base = [rec(f"r{i}", 100 + 37 * i) for i in range(10)]
    worse = [rec(f"r{i}", 120 + 37 * i) for i in range(10)]          # +2 points on every recording
    v, lo, hi = paired_bootstrap(base, worse, lambda x: pooled(x, "live"))
    assert v == pytest.approx(0.02) and lo == pytest.approx(0.02) and hi == pytest.approx(0.02)


def test_pairs_must_be_the_same_recordings():
    with pytest.raises(ValueError):
        paired_bootstrap([rec("a", 1)], [rec("b", 1)], lambda x: pooled(x, "live"))


def test_ship_rule_needs_ci_overlap_and_latency_within_ten_percent():
    base = {"der_live": {"value": 0.24, "ci95": [0.204, 0.273]}, "line_first_label_median_s": {"value": 0.62}}
    ok = {"der_live": {"value": 0.25, "ci95": [0.21, 0.28]}, "line_first_label_median_s": {"value": 0.68}}
    assert ship_rule(base, ok) == Verdict(der_ci_overlaps=True, latency_within_10pct=True)
    slow = {"der_live": {"value": 0.25, "ci95": [0.21, 0.28]}, "line_first_label_median_s": {"value": 0.69}}
    assert ship_rule(base, slow).latency_within_10pct is False         # 0.69 > 1.1 * 0.62 = 0.682
    worse = {"der_live": {"value": 0.32, "ci95": [0.28, 0.36]}, "line_first_label_median_s": {"value": 0.6}}
    assert ship_rule(base, worse).der_ci_overlaps is False
    assert ship_rule(base, ok).passes and not ship_rule(base, worse).passes
