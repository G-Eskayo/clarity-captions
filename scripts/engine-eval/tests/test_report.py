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


def test_write_report_with_latency_and_hosts(tmp_path):
    from edacc_eval.report import write_report
    shards = tmp_path / "shards"; (shards / "shard-001").mkdir(parents=True)
    (shards / "index.json").write_text(json.dumps({"n_shards": 2, "shards": ["shard-001", "shard-002"]}))
    (shards / "shard-001" / "manifest.jsonl").write_text(
        "\n".join(json.dumps(m | {"file": f"audio/{m['clip_id']}.wav"}) for m in manifest_rows()) + "\n")
    res = tmp_path / "results"; (res / "latency").mkdir(parents=True)
    rows = []
    for host in ("m4", "old"):
        for c, h in (("c1", "hello there"), ("c2", "i have three kids"), ("c3", "good morning")):
            rows.append(r(c, "sherpa", h) | {"host": host, "repeat": 1 if host == "m4" else 2})
    (res / "sherpa-shard-001.jsonl").write_text("\n".join(json.dumps(x) for x in rows) + "\n")
    lat = [{"kind": "timing", "clip_id": "c1", "words": [{"w": "hello", "start": 0.1, "end": 0.5},
                                                         {"w": "there", "start": 0.6, "end": 1.0}]},
           {"kind": "stream", "clip_id": "c1", "engine": "e", "model": "m", "method": "growing window",
            "updates": [{"t": 0.8, "text": "hello"}, {"t": 1.4, "text": "hello there"}]}]
    (res / "latency" / "latency-shard-001.jsonl").write_text("\n".join(json.dumps(x) for x in lat) + "\n")
    out = tmp_path / "r.md"
    s = write_report(shards, res, out, tmp_path / "r.json")
    md = out.read_text()
    assert "| sherpa | m4 |" in md and "| sherpa | old |" in md
    assert "Live latency" in md and "Mac numbers, not iPhone numbers" in md
    assert s.latency["engines"]["e (m)"]["median"] == 0.35
    assert "nan" not in md.lower()


def test_by_length_buckets():
    from edacc_eval.report import length_bucket
    assert [length_bucket(x) for x in (0.2, 1.0, 4.99, 5.0, 30.0, 30.01)] == \
        ["under 1 s", "1-5 s", "1-5 s", "5-30 s", "5-30 s", "over 30 s"]
    man = manifest_rows()
    man[0]["audio_seconds"] = 0.5
    rows = [r("c1", "a", ""), r("c2", "a", "i have three kids"), r("c3", "a", "good morning")]
    s = score(man, rows)
    assert s.by_length["a"]["under 1 s"].wer == 1.0
    assert s.by_length["a"]["1-5 s"].wer == 0.0
    md = build_report(s, meta={"shards_done": 1, "shards_total": 2})
    assert "## By clip length" in md and "| under 1 s |" in md


def test_dropped_engine_does_not_shrink_the_comparison():
    from edacc_eval import report
    man = manifest_rows()
    rows = [r(c, "a", h) for c, h in (("c1", "hello there"), ("c2", "i have three kids"), ("c3", "good morning"))]
    rows.append(r("c1", "whisperkit", "hello"))  # dropped engine only ran on c1
    s = score(man, rows, dropped={"whisperkit": "dropped after shard 1: slow"})
    assert s.clips_compared == 3                     # active engines decide the common clips
    assert s.overall["whisperkit"].clips == 1 and s.overall["whisperkit"].wer == 0.5
    md = build_report(s, meta={"shards_done": 2, "shards_total": 2})
    assert "dropped after shard 1: slow" in md
    assert report.DROPPED.get("whisperkit")           # the real config marks WhisperKit dropped
