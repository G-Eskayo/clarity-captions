"""Size bookkeeping for the compression test (#150). Temp dirs only."""
import json
import os

from edacc_eval.sizes import dir_bytes, record, zipped_bytes


def make(tmp_path):
    d = tmp_path / "model"
    (d / "Encoder.mlmodelc" / "weights").mkdir(parents=True)
    (d / "Encoder.mlmodelc" / "weights" / "weight.bin").write_bytes(b"\0" * 100_000)  # very compressible
    (d / "vocab.json").write_bytes(os.urandom(5_000))  # not compressible
    return d


def test_dir_bytes_counts_every_file(tmp_path):
    d = make(tmp_path)
    assert dir_bytes(d) == 105_000
    assert dir_bytes(d / "vocab.json") == 5_000


def test_zipped_is_smaller_for_compressible_and_cleans_up(tmp_path):
    d = make(tmp_path)
    before = set(os.listdir(__import__("tempfile").gettempdir()))
    z = zipped_bytes(d)
    assert 5_000 < z < 20_000
    assert set(os.listdir(__import__("tempfile").gettempdir())) - before == set()


def test_symlinks_not_followed(tmp_path):
    d = make(tmp_path)
    (d / "loop").symlink_to(d)
    assert dir_bytes(d) == 105_000


def test_record_upserts(tmp_path):
    d = make(tmp_path)
    out = tmp_path / "sizes.json"
    record(out, "m", d, "int8", "CC BY 4.0", encoder=d / "Encoder.mlmodelc")
    record(out, "m", d, "int8 again", "CC BY 4.0")
    data = json.loads(out.read_text())
    assert list(data) == ["m"] and data["m"]["method"] == "int8 again" and data["m"]["disk_bytes"] == 105_000


def test_include_limits_to_listed_components_and_missing_raises(tmp_path):
    import pytest
    d = make(tmp_path)
    assert dir_bytes(d, ["vocab.json"]) == 5_000
    assert dir_bytes(d, ["Encoder.mlmodelc", "vocab.json"]) == 105_000
    with pytest.raises(FileNotFoundError):
        dir_bytes(d, ["Missing.mlmodelc"])
