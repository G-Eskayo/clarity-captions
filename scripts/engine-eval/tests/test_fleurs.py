"""FLEURS shard maker (#158): TSV parsing, gender-stratified shards, manifests, audio from the tarball. Temp dirs only."""
import io
import json
import tarfile

import numpy as np
import pytest
import soundfile as sf

from edacc_eval.fleurs import LANGUAGES, build_fleurs_shards, read_tsv
from edacc_eval.shards import read_manifest


def wav_bytes(seconds=1.0, sr=16000):
    t = np.arange(int(seconds * sr)) / sr
    buf = io.BytesIO()
    sf.write(buf, (0.3 * np.sin(2 * np.pi * 440 * t)).astype(np.float32), sr, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def tsv_line(sid, fname, raw, samples, gender):
    return "\t".join([str(sid), fname, raw, raw.lower(), "x | y |", str(samples), gender])


def make_corpus(root, config, rows, sr=16000, extra_member=None):
    d = root / config
    d.mkdir(parents=True)
    (d / "test.tsv").write_text("\n".join(tsv_line(*r[:5]) for r in rows) + "\n", encoding="utf-8")
    with tarfile.open(d / "test.tar.gz", "w:gz") as tar:
        for r in rows:
            data = wav_bytes(r[3] / 16000, sr)
            info = tarfile.TarInfo(f"test/{r[1]}")
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
        if extra_member:
            info = tarfile.TarInfo(extra_member)
            info.size = 3
            tar.addfile(info, io.BytesIO(b"abc"))


def test_languages_table():
    assert LANGUAGES["es"].config == "es_419" and LANGUAGES["es"].locales == ("es-MX", "es-US", "es-ES")
    assert LANGUAGES["fr"].locales == ("fr-FR",) and LANGUAGES["de"].config == "de_de"


def test_read_tsv_fields_and_ids(tmp_path):
    p = tmp_path / "t.tsv"
    p.write_text(tsv_line(1770, "123.wav", "¿Cierto?", 32000, "FEMALE") + "\n\n", encoding="utf-8")
    [c] = read_tsv(p, "es")
    assert c.clip_id == "es-test-123" and c.group == "es-1770" and c.reference == "¿Cierto?"
    assert c.audio_seconds == 2.0 and c.gender == "female" and c.file_name == "123.wav"


def test_read_tsv_refuses_duplicates_and_short_lines(tmp_path):
    p = tmp_path / "t.tsv"
    p.write_text(tsv_line(1, "a.wav", "x", 16000, "MALE") + "\n" + tsv_line(2, "a.wav", "y", 16000, "MALE") + "\n")
    with pytest.raises(ValueError, match="duplicate"):
        read_tsv(p, "es")
    p.write_text("1\ta.wav\tonly three\n")
    with pytest.raises(ValueError, match="line 1"):
        read_tsv(p, "es")


def test_build_shards_stratified_by_gender_with_manifests(tmp_path):
    rows = [(i // 2, f"{i}.wav", f"frase {i}", 16000 * 600, "FEMALE" if i % 2 else "MALE") for i in range(12)]
    make_corpus(tmp_path / "corpus", "es_419", rows, extra_member="test/._junk")
    summary = build_fleurs_shards(tmp_path / "corpus", tmp_path / "shards", ["es"], target_hours=1.0)
    es = summary["es"]
    assert es["clips"] == 12 and es["n_shards"] == 2 and es["sentences"] == 6
    out = tmp_path / "shards" / "es"
    index = json.loads((out / "index.json").read_text())
    assert index["language"] == "es" and index["shards"] == ["shard-001", "shard-002"]
    for name in index["shards"]:
        m = read_manifest(out / name, check_audio=True)
        assert len(m) == 6
        assert {r["gender"] for r in m} == {"female", "male"}  # both genders in every shard
        r = m[0]
        assert r["language"] == "es" and r["locale"] == ["es-MX", "es-US", "es-ES"] and r["group"].startswith("es-")
        assert r["file"] == f"audio/{r['clip_id']}.wav" and r["accent"] == "es_419"
        data, sr = sf.read(out / name / r["file"])
        assert sr == 16000 and data.ndim == 1


def test_build_shards_resamples_and_downmixes(tmp_path):
    make_corpus(tmp_path / "corpus", "fr_fr", [(1, "a.wav", "Bonjour", 16000, "MALE")], sr=48000)
    build_fleurs_shards(tmp_path / "corpus", tmp_path / "shards", ["fr"])
    data, sr = sf.read(tmp_path / "shards" / "fr" / "shard-001" / "audio" / "fr-test-a.wav")
    assert sr == 16000 and abs(len(data) - 16000) <= 1


def test_missing_audio_in_tarball_fails_loudly(tmp_path):
    make_corpus(tmp_path / "corpus", "de_de", [(1, "a.wav", "Hallo", 16000, "MALE")])
    tsv = tmp_path / "corpus" / "de_de" / "test.tsv"
    tsv.write_text(tsv.read_text() + tsv_line(2, "missing.wav", "Tschüss", 16000, "FEMALE") + "\n")
    with pytest.raises(FileNotFoundError, match="missing.wav"):
        build_fleurs_shards(tmp_path / "corpus", tmp_path / "shards", ["de"])


def test_rerun_is_idempotent(tmp_path):
    make_corpus(tmp_path / "corpus", "de_de", [(1, "a.wav", "Hallo", 16000, "MALE")])
    a = build_fleurs_shards(tmp_path / "corpus", tmp_path / "shards", ["de"])
    b = build_fleurs_shards(tmp_path / "corpus", tmp_path / "shards", ["de"])
    assert a == b
    assert not list((tmp_path / "shards").rglob("*.tmp"))


def test_hebrew_is_a_fleurs_language_for_201():
    from edacc_eval.fleurs import LANGUAGES
    assert LANGUAGES["he"].config == "he_il" and LANGUAGES["he"].locales == ("he-IL",)
