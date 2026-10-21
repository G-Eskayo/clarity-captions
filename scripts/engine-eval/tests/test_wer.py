"""Adversarial tests for the WER scorer: (S + D + I) / N, docs/testing/test-plan.md §3."""
import math

import pytest

from edacc_eval.wer import align_counts, bootstrap_ci, pooled_wer


def test_identical():
    c = align_counts("a b c", "a b c")
    assert (c.sub, c.dele, c.ins, c.n) == (0, 0, 0, 3)


def test_empty_hypothesis_is_all_deletions():
    c = align_counts("one two three", "")
    assert (c.sub, c.dele, c.ins, c.n) == (0, 3, 0, 3)
    assert c.errors / c.n == 1.0


def test_extra_words_are_insertions_and_wer_can_exceed_one():
    c = align_counts("hi", "hi there my good friend")
    assert (c.sub, c.dele, c.ins, c.n) == (0, 0, 4, 1)
    assert c.errors / c.n == 4.0


def test_substitution():
    c = align_counts("the cat sat", "the bat sat")
    assert (c.sub, c.dele, c.ins) == (1, 0, 0)


def test_mixed():
    # ref: a b c d ; hyp: a x c d e -> 1 sub (b->x), 1 ins (e)
    c = align_counts("a b c d", "a x c d e")
    assert (c.sub, c.dele, c.ins, c.n) == (1, 0, 1, 4)


def test_empty_reference_counts_insertions_with_zero_n():
    c = align_counts("", "hello")
    assert (c.n, c.ins) == (0, 1)


def test_minimum_edit_distance_not_greedy():
    c = align_counts("a b a b", "b a b a")
    assert c.errors == 2


def test_pooled_not_mean_of_rates():
    counts = [align_counts("a", "b"), align_counts("a b c d e f g h i j", "a b c d e f g h i j")]
    # mean of per-clip rates would be 0.5; pooled is 1/11
    assert pooled_wer(counts) == pytest.approx(1 / 11)


def test_pooled_wer_with_no_words_is_nan():
    assert math.isnan(pooled_wer([]))
    assert math.isnan(pooled_wer([align_counts("", "")]))


def test_bootstrap_ci_brackets_point_and_is_deterministic():
    groups = {f"s{i}": (i % 3, 10) for i in range(30)}  # errors, words per speaker
    lo, hi = bootstrap_ci(groups, n_boot=500, seed=7)
    point = sum(e for e, _ in groups.values()) / sum(n for _, n in groups.values())
    assert lo <= point <= hi
    assert (lo, hi) == bootstrap_ci(groups, n_boot=500, seed=7)


def test_bootstrap_single_speaker_is_degenerate():
    lo, hi = bootstrap_ci({"only": (2, 10)}, n_boot=200, seed=1)
    assert lo == hi == pytest.approx(0.2)


def test_bootstrap_empty():
    lo, hi = bootstrap_ci({}, n_boot=10, seed=1)
    assert math.isnan(lo) and math.isnan(hi)
