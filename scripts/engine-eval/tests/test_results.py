"""Result-line store: resume keys, duplicates, corrupt lines (#145)."""
import json

from edacc_eval.results import ResultKey, done_keys, load_results


def line(clip="c1", engine="apple", model="m", repeat=1, hyp="hi", **kw):
    d = dict(clip_id=clip, shard=1, accent="Irish English", engine=engine, model=model, engine_version="1",
             repeat=repeat, hypothesis=hyp, audio_seconds=2.0, processing_seconds=0.1, host="h",
             finished_at="2026-10-21T00:00:00Z")
    d.update(kw)
    return json.dumps(d, ensure_ascii=False)


def write(tmp_path, name, lines):
    p = tmp_path / name
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


def test_missing_file_means_nothing_done(tmp_path):
    assert done_keys(tmp_path / "nope.jsonl") == set()


def test_done_keys(tmp_path):
    p = write(tmp_path, "r.jsonl", [line(), line(repeat=2), line(clip="c2", engine="whisper")])
    assert done_keys(p) == {ResultKey("c1", "apple", "m", 1), ResultKey("c1", "apple", "m", 2),
                            ResultKey("c2", "whisper", "m", 1)}


def test_corrupt_and_truncated_lines_skipped(tmp_path):
    p = write(tmp_path, "r.jsonl", [line(), "{not json", "", line(clip="c2"), '{"clip_id": "c3", "engin'])
    rows, stats = load_results([p])
    assert [r["clip_id"] for r in rows] == ["c1", "c2"]
    assert stats.corrupt == 2


def test_line_missing_required_field_is_corrupt(tmp_path):
    bad = json.loads(line())
    del bad["hypothesis"]
    p = write(tmp_path, "r.jsonl", [json.dumps(bad), line(clip="c2")])
    rows, stats = load_results([p])
    assert [r["clip_id"] for r in rows] == ["c2"]
    assert stats.corrupt == 1


def test_duplicate_result_first_wins(tmp_path):
    p = write(tmp_path, "r.jsonl", [line(hyp="first"), line(hyp="second")])
    rows, stats = load_results([p])
    assert len(rows) == 1 and rows[0]["hypothesis"] == "first"
    assert stats.duplicates == 1


def test_duplicates_across_files(tmp_path):
    a = write(tmp_path, "a.jsonl", [line(hyp="a")])
    b = write(tmp_path, "b.jsonl", [line(hyp="b"), line(clip="c9")])
    rows, stats = load_results([a, b])
    assert sorted(r["clip_id"] for r in rows) == ["c1", "c9"]
    assert stats.duplicates == 1


def test_empty_hypothesis_is_valid_result(tmp_path):
    p = write(tmp_path, "r.jsonl", [line(hyp="")])
    rows, _ = load_results([p])
    assert rows[0]["hypothesis"] == ""


def test_unicode_hypothesis_round_trips(tmp_path):
    p = write(tmp_path, "r.jsonl", [line(hyp="Hạ Long café ✓")])
    rows, _ = load_results([p])
    assert rows[0]["hypothesis"] == "Hạ Long café ✓"


def test_non_object_json_is_corrupt(tmp_path):
    p = write(tmp_path, "r.jsonl", ["[1,2]", "42", line()])
    rows, stats = load_results([p])
    assert len(rows) == 1 and stats.corrupt == 2


def test_compare_hypotheses_across_machines(tmp_path):
    from edacc_eval.results import compare_hypotheses
    a = write(tmp_path, "a.jsonl", [line("c1", engine="s", hyp="x"), line("c2", engine="s", hyp="y"),
                                    line("c3", engine="s", hyp="z")])
    b = write(tmp_path, "b.jsonl", [line("c1", engine="s", hyp="x"), line("c2", engine="s", hyp="Y"),
                                    line("c9", engine="s", hyp="q"), line("c1", engine="other", hyp="no")])
    r = compare_hypotheses([a], [b], "s")
    assert r == {"compared": 2, "identical": 1, "differ": ["c2"]}
