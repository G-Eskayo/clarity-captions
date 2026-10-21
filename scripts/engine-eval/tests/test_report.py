"""Scoring + report: same clips for every engine, missing clips, determinism, speed (#145)."""
import json
import math

from edacc_eval.report import build_report, score


def manifest_rows():
    return [
        {"clip_id": "c1", "speaker": "s1", "accent": "Irish English", "reference": "HELLO THERE", "audio_seconds": 2.0},
        {"clip_id": "c2", "speaker": "s2", "accent": "Irish English", "reference": "UM I HAVE THREE KIDS", "audio_seconds": 3.0},
        {"clip_id": "c3", "speaker": "s3", "accent": "Kenyan English", "reference": "GOOD MORNING", "audio_seconds": 1.0},
    ]


def r(clip, engine, hyp, repeat=1, proc=0.1, audio=2.0, model="m"):
    return {"clip_id": clip, "engine": engine, "model": model, "engine_version": "1", "repeat": repeat,
            "hypothesis": hyp, "audio_seconds": audio, "processing_seconds": proc, "accent": "x", "shard": 1}


def test_perfect_engine_scores_zero_with_normalization():
    rows = [r("c1", "a", "Hello there."), r("c2", "a", "I have 3 kids"), r("c3", "a", "Good morning!")]
    s = score(manifest_rows(), rows)
    assert s.overall["a"].wer == 0.0
    assert s.clips_compared == 3


def test_only_clips_every_engine_finished_are_compared():
    rows = [r("c1", "a", "hello there"), r("c2", "a", "i have three kids"), r("c3", "a", "good morning"),
            r("c1", "b", "hello"), r("c2", "b", "i have three kids")]  # b missing c3
    s = score(manifest_rows(), rows)
    assert s.clips_compared == 2
    assert s.overall["a"].n == 6 and s.overall["b"].n == 6
    assert s.overall["b"].wer == 1 / 6
    assert "Kenyan English" not in s.by_accent["a"]


def test_result_for_unknown_clip_ignored():
    rows = [r("c1", "a", "hello there"), r("zzz", "a", "ghost")]
    s = score(manifest_rows()[:1], rows)
    assert s.clips_compared == 1


def test_empty_hypothesis_counts_as_deletions():
    s = score(manifest_rows()[:1], [r("c1", "a", "")])
    assert s.overall["a"].wer == 1.0


def test_determinism_and_repeat_one_is_primary():
    rows = [r("c1", "a", "hello there", repeat=1), r("c1", "a", "hello there", repeat=2),
            r("c1", "b", "hello there", repeat=1), r("c1", "b", "hello where", repeat=2)]
    s = score(manifest_rows()[:1], rows)
    assert s.overall["b"].wer == 0.0  # repeat 1
    assert s.determinism["a"].identical == 1 and s.determinism["a"].clips == 1
    assert s.determinism["b"].identical == 0
    assert s.determinism["b"].wer_max == 0.5


def test_speed_over_all_repeats():
    rows = [r("c1", "a", "hello there", repeat=1, proc=1.0, audio=2.0),
            r("c1", "a", "hello there", repeat=2, proc=0.0, audio=2.0)]
    s = score(manifest_rows()[:1], rows)
    assert s.speed["a"].rtf == 0.25


def test_engine_label_includes_model():
    rows = [r("c1", "parakeet", "hello there", model="v2"), r("c1", "parakeet", "hello", model="ultra")]
    s = score(manifest_rows()[:1], rows)
    assert set(s.overall) == {"parakeet (v2)", "parakeet (ultra)"}


def test_no_results_report_still_renders(tmp_path):
    md = build_report(score(manifest_rows(), []), meta={"shards_done": 0, "shards_total": 33})
    assert "No results yet" in md
    assert "nan" not in md.lower()


def test_report_renders_tables(tmp_path):
    rows = [r("c1", "a", "hello there"), r("c2", "a", "i have three"), r("c3", "a", "good morning")]
    md = build_report(score(manifest_rows(), rows), meta={"shards_done": 1, "shards_total": 33})
    assert "| a |" in md or "| a" in md
    assert "Irish English" in md and "Kenyan English" in md
    assert "15%" in md and "30%" in md
    assert "nan" not in md.lower()
