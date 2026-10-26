"""chrF with group bootstrap, paired differences, mean bootstrap, speed summaries (#159)."""
import math

import pytest

sacrebleu = pytest.importorskip("sacrebleu")

from translation_eval.score import (bootstrap_mean, chrf_bootstrap, corpus_chrf, paired_chrf_diff, segment_stats,
                                    speed_summary)

HYPS = ["el gato está en la casa", "hola mundo", "una frase totalmente distinta", "buenos días"]
REFS = ["el gato está en casa", "hola, mundo", "otra oración", "buenos días"]
GROUPS = ["a", "a", "b", "c"]


def test_corpus_chrf_matches_sacrebleu():
    stats = [segment_stats(h, r) for h, r in zip(HYPS, REFS)]
    assert corpus_chrf(stats) == pytest.approx(sacrebleu.corpus_chrf(HYPS, [REFS]).score)


def test_perfect_translation_scores_100_and_empty_scores_0():
    assert corpus_chrf([segment_stats("buenos días", "buenos días")]) == pytest.approx(100.0)
    assert corpus_chrf([segment_stats("", "buenos días")]) == pytest.approx(0.0)


def test_bootstrap_ci_brackets_point_and_is_deterministic():
    stats = [segment_stats(h, r) for h, r in zip(HYPS, REFS)]
    point, lo, hi = chrf_bootstrap(stats, GROUPS, n_boot=300, seed=159)
    assert lo <= point <= hi
    assert (point, lo, hi) == chrf_bootstrap(stats, GROUPS, n_boot=300, seed=159)


def test_bootstrap_with_one_group_has_zero_width():
    stats = [segment_stats(h, r) for h, r in zip(HYPS, REFS)]
    point, lo, hi = chrf_bootstrap(stats, ["only"] * 4, n_boot=50)
    assert lo == pytest.approx(point) and hi == pytest.approx(point)


def test_bootstrap_rejects_length_mismatch():
    with pytest.raises(ValueError):
        chrf_bootstrap([segment_stats("a", "a")], ["g1", "g2"])


def test_paired_diff_of_identical_systems_is_exactly_zero():
    stats = [segment_stats(h, r) for h, r in zip(HYPS, REFS)]
    d, lo, hi = paired_chrf_diff(stats, stats, GROUPS, n_boot=200)
    assert (d, lo, hi) == (0.0, 0.0, 0.0)


def test_paired_diff_sign_follows_better_system():
    good = [segment_stats(r, r) for r in REFS]
    bad = [segment_stats(h, r) for h, r in zip(HYPS, REFS)]
    d, lo, hi = paired_chrf_diff(good, bad, GROUPS, n_boot=200)
    assert d > 0 and lo >= 0 and hi >= lo  # a resample of only the shared perfect group gives exactly 0


def test_paired_diff_excludes_zero_with_many_groups():
    refs = [f"frase número {i} de la prueba" for i in range(40)]
    good = [segment_stats(r, r) for r in refs]
    bad = [segment_stats("algo distinto", r) for r in refs]
    d, lo, hi = paired_chrf_diff(good, bad, [str(i) for i in range(40)], n_boot=200)
    assert 0 < lo <= d <= hi


def test_bootstrap_mean_groups_and_nan_on_empty():
    m, lo, hi = bootstrap_mean([1.0, 1.0, 0.0], ["a", "a", "b"], n_boot=200)
    assert m == pytest.approx(2 / 3) and 0.0 <= lo <= m <= hi <= 1.0
    assert all(math.isnan(x) for x in bootstrap_mean([], [], n_boot=10))


def test_speed_summary_skips_warmup_and_reports_ms():
    secs = [9.0] * 5 + [0.010, 0.020, 0.030, 0.040, 0.100]
    s = speed_summary(secs, warmup=5)
    assert s["n"] == 5 and s["median_ms"] == pytest.approx(30.0) and s["p95_ms"] == pytest.approx(100.0, rel=0.2)


def test_speed_summary_of_too_few_lines_is_none():
    assert speed_summary([0.1, 0.2], warmup=5) is None
