"""ivrit.ai eval sets (#201 follow-up): parquet rows to the shard format, audio to 16 kHz mono. Temp dirs only."""
import io
import json

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
import pytest
import soundfile as sf

from edacc_eval.ivrit import SETS, build_ivrit_shards, clip_id_for
from edacc_eval.shards import read_manifest


def wav_bytes(seconds=1.0, sr=16000, channels=1):
    t = np.arange(int(seconds * sr)) / sr
    mono = (0.3 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
    data = np.stack([mono] * channels, axis=1) if channels > 1 else mono
    buf = io.BytesIO()
    sf.write(buf, data, sr, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def make_parquet(path, rows):
    """rows: (uuid, audio path, text, audio bytes), the layout of ivrit-ai/eval-d1 and eval-whatsapp."""
    path.parent.mkdir(parents=True, exist_ok=True)
    table = pa.table({
        "audio": [{"bytes": b, "path": p} for _, p, _, b in rows],
        "uuid": [u for u, _, _, _ in rows],
        "text": [t for _, _, t, _ in rows],
    })
    pq.write_table(table, path)


def test_known_sets_and_their_revisions_are_pinned():
    assert set(SETS) == {"eval-d1", "eval-whatsapp"}
    for s in SETS.values():
        assert len(s.revision) == 40 and s.repo.startswith("ivrit-ai/")


def test_clip_ids_are_prefixed_and_filesystem_safe():
    assert clip_id_for("eval-d1", "Mindset/ 1.mp3") == "eval-d1-Mindset_1"
    assert clip_id_for("eval-whatsapp", "54") == "eval-whatsapp-54"


def test_build_writes_manifest_audio_and_index(tmp_path):
    pq_path = tmp_path / "corpus" / "eval-d1" / "test-00000-of-00001.parquet"
    make_parquet(pq_path, [
        ("Mindset/ 1", "1.mp3", 'שלום, ד"ר כהן.\nכן.', wav_bytes(2.0, 44100, channels=2)),
        ("Mindset/ 2", "2.mp3", "מה שלומך?", wav_bytes(1.0)),
    ])
    summary = build_ivrit_shards(pq_path, tmp_path / "shards", "eval-d1")
    assert summary["clips"] == 2 and summary["shards"] == ["shard-001"] and summary["set"] == "eval-d1"
    assert summary["revision"] == SETS["eval-d1"].revision and summary["audio_hours"] == round(3.0 / 3600, 3)
    out = tmp_path / "shards" / "eval-d1"
    assert json.loads((out / "index.json").read_text()) == summary
    rows = read_manifest(out / "shard-001", check_audio=True)
    assert [r["clip_id"] for r in rows] == ["eval-d1-Mindset_1", "eval-d1-Mindset_2"]
    r = rows[0]
    assert r["set"] == "eval-d1" and r["accent"] == "eval-d1" and r["group"] == r["clip_id"]
    assert r["reference"] == 'שלום, ד"ר כהן.\nכן.'  # raw: the #202 normaliser does the rest, on both sides
    assert r["language"] == "he" and r["locale"] == ["he-IL"] and r["audio_seconds"] == 2.0
    data, sr = sf.read(out / "shard-001" / r["file"])
    assert sr == 16000 and data.ndim == 1 and abs(len(data) - 32000) <= 1  # 44.1 kHz stereo -> 16 kHz mono


def test_duplicate_ids_are_refused(tmp_path):
    pq_path = tmp_path / "d.parquet"
    make_parquet(pq_path, [("1", "1.ogg", "x", wav_bytes()), ("1", "1.ogg", "y", wav_bytes())])
    with pytest.raises(ValueError, match="duplicate"):
        build_ivrit_shards(pq_path, tmp_path / "shards", "eval-whatsapp")


def test_undecodable_audio_fails_loudly(tmp_path):
    pq_path = tmp_path / "d.parquet"
    make_parquet(pq_path, [("1", "1.ogg", "x", b"not audio")])
    with pytest.raises(Exception):
        build_ivrit_shards(pq_path, tmp_path / "shards", "eval-whatsapp")
    assert not (tmp_path / "shards" / "eval-whatsapp" / "index.json").exists()


def test_unknown_set_is_refused(tmp_path):
    with pytest.raises(KeyError):
        build_ivrit_shards(tmp_path / "x.parquet", tmp_path / "shards", "eval-nope")


def test_rerun_is_idempotent(tmp_path):
    pq_path = tmp_path / "d.parquet"
    make_parquet(pq_path, [("7", "7.ogg", "בוקר טוב", wav_bytes(0.5))])
    a = build_ivrit_shards(pq_path, tmp_path / "shards", "eval-whatsapp")
    b = build_ivrit_shards(pq_path, tmp_path / "shards", "eval-whatsapp")
    assert a == b and not list((tmp_path / "shards").rglob("*.tmp"))


def test_cli_cuts_a_set(tmp_path, capsys):
    from edacc_eval.cli import main
    pq_path = tmp_path / "d.parquet"
    make_parquet(pq_path, [("3", "3.ogg", "כן", wav_bytes(0.5))])
    assert main(["ivrit-shards", "--parquet", str(pq_path), "--out", str(tmp_path / "s"), "--set", "eval-whatsapp"]) == 0
    assert json.loads(capsys.readouterr().out)["clips"] == 1
