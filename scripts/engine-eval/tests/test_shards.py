"""Shard maker: stratified assignment, exclusions, manifests, resampling (#145). Temp dirs only."""
import io
import json

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
import pytest
import soundfile as sf

from edacc_eval.shards import Clip, assign_shards, build_shards, clip_id_for, read_manifest, shard_count


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
