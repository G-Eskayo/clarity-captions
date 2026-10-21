"""Generic resumable runner loop (used by sherpa-onnx on the 2012 mini) with a fake engine (#145)."""
import json

from edacc_eval.results import load_results
from edacc_eval.runner import run_loop


def shard(tmp_path, ids=("a", "b", "c"), missing=()):
    d = tmp_path / "shard-001"
    (d / "audio").mkdir(parents=True)
    rows = []
    for i in ids:
        if i not in missing:
            (d / "audio" / f"{i}.wav").write_bytes(b"RIFF")
        rows.append({"clip_id": i, "file": f"audio/{i}.wav", "accent": "A", "audio_seconds": 1.0})
    return d, rows


class Fake:
    def __init__(self, fail_on=()):
        self.calls = []
        self.fail_on = set(fail_on)

    def __call__(self, path):
        self.calls.append(path.stem)
        if path.stem in self.fail_on:
            raise RuntimeError("boom")
        return f"text {path.stem}"


def go(d, rows, results, fake, repeats=2):
    return run_loop(rows, d, results, engine="fake", model="m1", version="0", repeats=repeats, transcribe=fake,
                    shard_number=1, host="test")


def test_runs_every_clip_every_repeat(tmp_path):
    d, rows = shard(tmp_path)
    res = tmp_path / "r.jsonl"
    fake = Fake()
    summary = go(d, rows, res, fake)
    got, _ = load_results([res])
    assert len(got) == 6 and summary["done"] == 6
    assert {(r["clip_id"], r["repeat"]) for r in got} == {(c, k) for c in "abc" for k in (1, 2)}
    assert all(r["hypothesis"] == f"text {r['clip_id']}" for r in got)


def test_resume_skips_done(tmp_path):
    d, rows = shard(tmp_path)
    res = tmp_path / "r.jsonl"
    go(d, rows, res, Fake(), repeats=1)
    fake = Fake()
    go(d, rows, res, fake, repeats=2)
    assert sorted(fake.calls) == ["a", "b", "c"]  # only repeat 2 ran
    got, stats = load_results([res])
    assert len(got) == 6 and stats.duplicates == 0


def test_truncated_last_line_does_not_corrupt_next_append(tmp_path):
    d, rows = shard(tmp_path)
    res = tmp_path / "r.jsonl"
    go(d, rows, res, Fake(), repeats=1)
    with res.open("a") as fh:
        fh.write('{"clip_id": "a", "eng')  # crash mid-write, no newline
    go(d, rows, res, Fake(), repeats=2)
    got, stats = load_results([res])
    assert len(got) == 6 and stats.corrupt == 1


def test_missing_audio_is_skipped_and_reported(tmp_path):
    d, rows = shard(tmp_path, missing=("b",))
    res = tmp_path / "r.jsonl"
    summary = go(d, rows, res, Fake(), repeats=1)
    got, _ = load_results([res])
    assert sorted(r["clip_id"] for r in got) == ["a", "c"]
    assert summary["errors"] == 1


def test_engine_error_on_one_clip_does_not_stop_shard(tmp_path):
    d, rows = shard(tmp_path)
    res = tmp_path / "r.jsonl"
    summary = go(d, rows, res, Fake(fail_on={"b"}), repeats=1)
    got, _ = load_results([res])
    assert sorted(r["clip_id"] for r in got) == ["a", "c"] and summary["errors"] == 1


def test_line_fields(tmp_path):
    d, rows = shard(tmp_path, ids=("a",))
    res = tmp_path / "r.jsonl"
    go(d, rows, res, Fake(), repeats=1)
    row = json.loads(res.read_text().splitlines()[0])
    for k in ("clip_id", "shard", "accent", "engine", "model", "engine_version", "repeat", "hypothesis",
              "audio_seconds", "processing_seconds", "host", "finished_at"):
        assert k in row
    assert row["processing_seconds"] >= 0


def test_status_callback(tmp_path):
    d, rows = shard(tmp_path)
    seen = []
    run_loop(rows, d, tmp_path / "r.jsonl", engine="fake", model="m", version="0", repeats=1, transcribe=Fake(),
             shard_number=1, host="t", on_progress=lambda done, total, eta: seen.append((done, total)))
    assert seen[-1] == (3, 3)
