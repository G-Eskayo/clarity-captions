"""Streaming latency analysis: reference word times, first-correct times, first text (#145)."""
import math

import pytest

from edacc_eval.latency import (clip_latency, percentile, reference_word_times, summarize, timing_words)
from edacc_eval.wer import align_pairs, matched_reference


def test_align_pairs_basic():
    assert align_pairs(["a", "b", "c"], ["a", "x", "c", "d"]) == [(0, 0), (1, 1), (2, 2), (None, 3)]
    assert align_pairs([], ["a"]) == [(None, 0)]
    assert align_pairs(["a"], []) == [(0, None)]
    assert matched_reference(["a", "b", "c"], ["a", "x", "c"]) == {0, 2}


def test_timing_words_splits_normalized_forms():
    words = timing_words([{"w": "Yeah,", "start": 0.0, "end": 0.4}, {"w": "10", "start": 0.5, "end": 0.9},
                          {"w": "um", "start": 1.0, "end": 1.2}])
    assert [w for w, _, _ in words] == ["yeah", "ten"]  # filler dropped by the normalizer
    assert words[1][1:] == (0.5, 0.9)


def test_timing_words_multiword_expansion_splits_time():
    words = timing_words([{"w": "21", "start": 1.0, "end": 2.0}])
    assert [w for w, _, _ in words] == ["twenty", "one"]
    assert words[0][1:] == (1.0, 1.5) and words[1][1:] == (1.5, 2.0)


def test_reference_word_times_matched_and_interpolated():
    ref = ["i", "have", "three", "kids"]
    tw = [("i", 0.1, 0.2), ("have", 0.3, 0.5), ("free", 0.6, 0.8), ("kids", 0.9, 1.2)]
    times = reference_word_times(ref, tw, duration=1.5)
    assert times[0] == (0.1, 0.2) and times[2] == (0.6, 0.8)  # substitution still carries timing
    tw2 = [("i", 0.1, 0.2), ("kids", 0.9, 1.2)]
    t2 = reference_word_times(ref, tw2, duration=1.5)
    assert 0.2 <= t2[1][0] <= t2[1][1] <= t2[2][0] <= t2[2][1] <= 0.9  # gap filled in order


def test_reference_word_times_no_timing_spreads_over_clip():
    t = reference_word_times(["a", "b"], [], duration=2.0)
    assert t == [(0.0, 1.0), (1.0, 2.0)]


def test_word_latency_wrong_then_corrected():
    ref = ["hello", "there"]
    times = [(0.0, 0.5), (0.6, 1.0)]
    updates = [(0.7, "hello"), (1.2, "hello where"), (1.5, "hello there")]
    r = clip_latency(ref, times, updates)
    assert r.word_latencies == pytest.approx([0.2, 0.5])  # "there" first right at 1.5 - 1.0
    assert r.first_text == pytest.approx(0.2)            # 0.7 - end of first word 0.5
    assert r.final_correct == 2


def test_word_never_correct_excluded():
    r = clip_latency(["a", "b"], [(0, 0.5), (0.5, 1.0)], [(1.2, "a c")])
    assert r.final_correct == 1 and len(r.word_latencies) == 1 and r.ref_words == 2


def test_word_correct_early_but_wrong_in_final_excluded():
    r = clip_latency(["a", "b"], [(0, 0.5), (0.5, 1.0)], [(0.9, "a b"), (1.4, "a c")])
    assert r.final_correct == 1 and r.word_latencies == pytest.approx([0.4])


def test_updates_out_of_order_are_sorted_and_empty_updates_ignored():
    r = clip_latency(["a"], [(0, 0.5)], [(2.0, "a"), (0.8, ""), (1.0, "a")])
    assert r.word_latencies == pytest.approx([0.5]) and r.first_text == pytest.approx(0.5)


def test_no_updates():
    r = clip_latency(["a"], [(0, 0.5)], [])
    assert r.word_latencies == [] and r.first_text is None and r.final_correct == 0


def test_percentile():
    assert percentile([1, 2, 3, 4], 50) == 2.5
    assert percentile([5], 95) == 5
    assert math.isnan(percentile([], 50))


def test_summarize():
    from edacc_eval.latency import ClipLatency
    s = summarize([ClipLatency([0.2, 0.4], 0.3, 2, 3), ClipLatency([1.0], None, 1, 1)])
    assert s["words"] == 3 and s["median"] == pytest.approx(0.4)
    assert s["first_text_median"] == pytest.approx(0.3) and s["clips"] == 2
    assert s["final_correct_share"] == pytest.approx(3 / 4)
