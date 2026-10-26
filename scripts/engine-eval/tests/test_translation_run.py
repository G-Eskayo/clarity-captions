"""Resumable translation loop writing #145 result lines (#159)."""
import json

from edacc_eval.results import load_results
from translation_eval.run import run_lines

ROWS = [{"id": f"s{i}", "set": "flores", "group": "g", "source": f"line {i}", "reference": "r"} for i in range(4)]


def test_writes_one_result_line_per_segment_and_repeat(tmp_path):
    out = tmp_path / "r" / "opus.jsonl"
    summary = run_lines(ROWS, out, engine="opus-mt", model="en-es", version="1", repeats=2,
                        translate=lambda s: s.upper(), host="h")
    rows, stats = load_results([out])
    assert summary == {"done": 8, "total": 8, "errors": 0}
    assert stats.corrupt == 0 and len(rows) == 8
    first = rows[0]
    assert first["hypothesis"] == "LINE 0" and first["accent"] == "flores" and first["audio_seconds"] == 0
    assert first["processing_seconds"] >= 0


def test_resume_skips_done_and_survives_a_truncated_last_line(tmp_path):
    out = tmp_path / "opus.jsonl"
    calls = []

    def tr(s):
        calls.append(s)
        return s

    run_lines(ROWS[:2], out, engine="e", model="m", version="1", repeats=1, translate=tr, host="h")
    with out.open("a", encoding="utf-8") as fh:
        fh.write('{"clip_id": "s2", "engi')  # crash mid-write
    calls.clear()
    summary = run_lines(ROWS, out, engine="e", model="m", version="1", repeats=1, translate=tr, host="h")
    assert calls == ["line 2", "line 3"]
    rows, stats = load_results([out])
    assert [r["clip_id"] for r in rows] == ["s0", "s1", "s2", "s3"] and stats.corrupt == 1
    assert summary["done"] == 4


def test_one_failing_segment_does_not_stop_the_run(tmp_path):
    out = tmp_path / "e.jsonl"

    def tr(s):
        if s == "line 1":
            raise RuntimeError("boom")
        return s

    summary = run_lines(ROWS, out, engine="e", model="m", version="1", repeats=1, translate=tr, host="h")
    assert summary["errors"] == 1
    assert [json.loads(l)["clip_id"] for l in out.read_text().splitlines()] == ["s0", "s2", "s3"]


def test_batch_translator_receives_pending_lines_in_order(tmp_path):
    out = tmp_path / "b.jsonl"
    seen = []

    def batch(lines):
        seen.append(list(lines))
        return [l[::-1] for l in lines]

    run_lines(ROWS, out, engine="e", model="m", version="1", repeats=1, translate=None, translate_batch=batch,
              batch_size=3, host="h")
    rows, _ = load_results([out])
    assert seen == [["line 0", "line 1", "line 2"], ["line 3"]]
    assert rows[3]["hypothesis"] == "3 enil"
