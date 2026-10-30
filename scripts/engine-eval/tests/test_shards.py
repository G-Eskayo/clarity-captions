"""Shard maker: stratified assignment, exclusions, manifests, resampling (#145). Temp dirs only."""
import io
import json
from pathlib import Path

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
import pytest
import soundfile as sf

from edacc_eval.shards import (Clip, assign_shards, build_shards, build_shards_staged, clip_id_for, fetch_each,
                               match_earlier_results, read_manifest, shard_count)


def wav_bytes(seconds=1.0, sr=32000, freq=440.0):
    t = np.arange(int(seconds * sr)) / sr
    buf = io.BytesIO()
    sf.write(buf, (0.3 * np.sin(2 * np.pi * freq * t)).astype(np.float32), sr, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def make_parquet(path, rows):
    table = pa.table({
        "speaker": [r["speaker"] for r in rows],
        "text": [r["text"] for r in rows],
        "accent": [r["accent"] for r in rows],
        "raw_accent": [r["accent"] for r in rows],
        "gender": ["female"] * len(rows),
        "l1": [r.get("l1", "English") for r in rows],
        "audio": [{"bytes": wav_bytes(r.get("sec", 1.0)), "path": r["path"]} for r in rows],
    })
    pq.write_table(table, path)


def clip(cid, accent, sec=1.0):
    return Clip(clip_id=cid, split="test", speaker="s", accent=accent, l1="x", gender="f",
                reference="hi", audio_seconds=sec, source_file="f", row=0)


def test_shard_count():
    assert shard_count(total_seconds=3600 * 32.7, target_hours=1.0) == 33
    assert shard_count(total_seconds=10, target_hours=1.0) == 1
    assert shard_count(total_seconds=0, target_hours=1.0) == 1


def test_clip_id():
    assert clip_id_for("test", "EDACC-C08-1.wav") == "test-EDACC-C08-1"
    assert clip_id_for("validation", "dir/x y.wav") == "validation-x_y"


def test_assign_is_stratified_and_deterministic():
    clips = [clip(f"a{i:02d}", "A") for i in range(10)] + [clip(f"b{i:02d}", "B") for i in range(4)]
    shards = assign_shards(clips, n_shards=4)
    assert len(shards) == 4
    for s in shards:
        assert {c.accent for c in s} == {"A", "B"}  # every shard samples every accent with >= n clips
    assert sorted(c.clip_id for s in shards for c in s) == sorted(c.clip_id for c in clips)
    assert [[c.clip_id for c in s] for s in shards] == \
        [[c.clip_id for c in s] for s in assign_shards(list(reversed(clips)), n_shards=4)]


def test_rare_accent_not_lost():
    clips = [clip(f"a{i}", "A") for i in range(8)] + [clip("z0", "Z")]
    shards = assign_shards(clips, n_shards=4)
    assert sum(1 for s in shards for c in s if c.accent == "Z") == 1


def test_duplicate_clip_ids_refused():
    with pytest.raises(ValueError, match="duplicate"):
        assign_shards([clip("x", "A"), clip("x", "B")], n_shards=1)


def test_build_shards_end_to_end(tmp_path):
    corpus = tmp_path / "corpus" / "data"
    corpus.mkdir(parents=True)
    make_parquet(corpus / "test-00000-of-00001.parquet", [
        {"speaker": "S1", "text": "HELLO THERE", "accent": "Irish English", "path": "EDACC-C01-1.wav", "sec": 1.5},
        {"speaker": "S2", "text": "IGNORE_TIME_SEGMENT_IN_SCORING", "accent": "Irish English", "path": "EDACC-C01-2.wav"},
        {"speaker": "S2", "text": "<NO-SPEECH>", "accent": "Irish English", "path": "EDACC-C01-3.wav"},
        {"speaker": "S2", "text": "Hạ LONG <LAUGH>", "accent": "Vietnamese", "path": "EDACC-C01-4.wav"},
    ])
    make_parquet(corpus / "validation-00000-of-00001.parquet", [
        {"speaker": "S3", "text": "YES", "accent": "Kenyan English", "path": "EDACC-C02-1.wav", "sec": 0.5},
    ])
    out = tmp_path / "shards"
    summary = build_shards(corpus, out, target_hours=1.0)
    assert summary["n_shards"] == 1
    assert summary["clips"] == 3
    assert summary["excluded"] == {"ignore_marker": 1, "empty_reference": 1}
    manifest = read_manifest(out / "shard-001")
    ids = sorted(c["clip_id"] for c in manifest)
    assert ids == ["test-EDACC-C01-1", "test-EDACC-C01-4", "validation-EDACC-C02-1"]
    first = next(c for c in manifest if c["clip_id"] == "test-EDACC-C01-1")
    assert first["reference"] == "HELLO THERE" and first["accent"] == "Irish English"
    data, sr = sf.read(out / "shard-001" / first["file"])
    assert sr == 16000 and data.ndim == 1
    assert first["audio_seconds"] == pytest.approx(1.5, abs=0.01)
    assert len(data) == pytest.approx(24000, abs=2)
    viet = next(c for c in manifest if c["accent"] == "Vietnamese")
    assert viet["reference"] == "Hạ LONG <LAUGH>"  # raw reference kept; normalization happens at scoring
    index = json.loads((out / "index.json").read_text())
    assert index["shards"] == ["shard-001"]


def test_build_shards_is_rerunnable(tmp_path):
    corpus = tmp_path / "c"
    corpus.mkdir()
    make_parquet(corpus / "test-0.parquet", [
        {"speaker": "S1", "text": "HI", "accent": "A", "path": "x1.wav"},
    ])
    out = tmp_path / "s"
    build_shards(corpus, out, target_hours=1.0)
    build_shards(corpus, out, target_hours=1.0)
    assert len(read_manifest(out / "shard-001")) == 1


def test_read_manifest_missing_clip_audio_is_reported(tmp_path):
    d = tmp_path / "shard-001"
    (d / "audio").mkdir(parents=True)
    (d / "manifest.jsonl").write_text(json.dumps({"clip_id": "a", "file": "audio/a.wav"}) + "\n")
    with pytest.raises(FileNotFoundError, match="a.wav"):
        read_manifest(d, check_audio=True)


def three_parquets(corpus):
    """Enough clips over three files that a small target gives several shards."""
    corpus.mkdir(parents=True)
    accents = ["Irish English", "Vietnamese", "Kenyan English"]
    k = 0
    for f, split in enumerate(["test", "test", "validation"]):
        rows = []
        for j in range(5):
            k += 1
            rows.append({"speaker": f"S{k % 4}", "text": f"WORD NUMBER {k}", "accent": accents[k % 3],
                         "path": f"EDACC-C{f:02d}-{j}.wav", "sec": 0.5 + 0.1 * j})
        rows.append({"speaker": "S9", "text": "IGNORE_TIME_SEGMENT_IN_SCORING", "accent": "Irish English",
                     "path": f"EDACC-C{f:02d}-x.wav"})
        make_parquet(corpus / f"{split}-{f:05d}-of-00003.parquet", rows)


def shard_tree(out):
    """Every file under out, with WAV contents, so two builds can be compared exactly."""
    return {str(p.relative_to(out)): p.read_bytes() for p in sorted(out.rglob("*")) if p.is_file()}


def test_staged_build_matches_the_all_at_once_build(tmp_path):
    corpus = tmp_path / "corpus"
    three_parquets(corpus)
    a, b = tmp_path / "a", tmp_path / "b"
    sa = build_shards(corpus, a, target_hours=1.5 / 3600)
    sb = build_shards_staged(sorted(corpus.glob("*.parquet")), b, target_hours=1.5 / 3600)
    assert sa["n_shards"] > 2
    assert sa == sb
    assert shard_tree(a) == shard_tree(b)


def test_staged_build_needs_only_one_parquet_at_a_time(tmp_path):
    corpus = tmp_path / "corpus"
    three_parquets(corpus)
    src = sorted(corpus.glob("*.parquet"))
    dl = tmp_path / "dl"
    seen = []

    def fake_fetch(url, dest):
        seen.append(len(list(dl.glob("*"))))  # what is already on disk when the next file arrives
        dest.write_bytes(Path(url).read_bytes())

    out = tmp_path / "out"
    summary = build_shards_staged(fetch_each([str(p) for p in src], dl, fetch=fake_fetch), out,
                                  target_hours=1.5 / 3600)
    assert seen == [0, 0, 0]
    assert list(dl.glob("*")) == []
    assert summary == build_shards(corpus, tmp_path / "ref", target_hours=1.5 / 3600)
    assert not (out / "_staging").exists()


def test_fetch_each_keeps_the_original_file_name_and_removes_partials(tmp_path):
    dl = tmp_path / "dl"

    def broken(url, dest):
        dest.write_bytes(b"half")
        raise OSError("connection reset")

    gen = fetch_each(["https://example.invalid/data/test-00000-of-00010-abc.parquet?download=true"], dl, fetch=broken)
    with pytest.raises(OSError):
        next(gen)
    assert list(dl.glob("*")) == []

    got = []
    for p in fetch_each(["https://example.invalid/data/test-00000-of-00010-abc.parquet"], dl,
                        fetch=lambda u, d: d.write_bytes(b"x")):
        got.append(p.name)
    assert got == ["test-00000-of-00010-abc.parquet"]


def test_staged_build_is_rerunnable(tmp_path):
    corpus = tmp_path / "corpus"
    three_parquets(corpus)
    out = tmp_path / "out"
    build_shards_staged(sorted(corpus.glob("*.parquet")), out, target_hours=1.5 / 3600)
    first = shard_tree(out)
    build_shards_staged(sorted(corpus.glob("*.parquet")), out, target_hours=1.5 / 3600)
    assert shard_tree(out) == first


def test_match_earlier_results_finds_moved_and_missing_clips(tmp_path):
    corpus = tmp_path / "corpus"
    three_parquets(corpus)
    out = tmp_path / "out"
    build_shards_staged(sorted(corpus.glob("*.parquet")), out, target_hours=1.5 / 3600)
    results = tmp_path / "results"
    results.mkdir()
    for d in sorted(out.glob("shard-*")):
        k = int(d.name.split("-")[1])
        with (results / f"apple-{d.name}.jsonl").open("w") as fh:
            for c in read_manifest(d):
                fh.write(json.dumps({"clip_id": c["clip_id"], "shard": k, "engine": "e"}) + "\n")
    assert match_earlier_results(out, results) == {"shards": len(list(out.glob("shard-*"))),
                                                   "clips": 15, "moved": [], "missing": [], "extra": []}
    first = sorted(results.glob("*.jsonl"))[0]
    lines = first.read_text().splitlines()
    moved = json.loads(lines[0]); moved["shard"] = 99
    first.write_text("\n".join([json.dumps(moved)] + lines[1:] + [json.dumps({"clip_id": "ghost", "shard": 1})]) + "\n")
    got = match_earlier_results(out, results)
    assert got["moved"] == [moved["clip_id"]] and got["missing"] == ["ghost"] and got["extra"] == []
