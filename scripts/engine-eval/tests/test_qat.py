"""#272 step 4: quantisation-aware training (QAT). The trained weights must still pack exactly (at most 2**bits values
per 16-channel group) and training must reach both the lookup tables and the weights. These tests try to break that.
Needs torch (mobius env)."""
import json
import os
import tempfile
from pathlib import Path

import pytest

torch = pytest.importorskip("torch")
qat = pytest.importorskip("qat_ultra")
cu = pytest.importorskip("calibrated_ultra")


def _per_group_unique(w, group=16):
    flat = w.reshape(w.shape[0], -1)
    return [len(torch.unique(flat[s:s + group])) for s in range(0, w.shape[0], group)]


@pytest.mark.parametrize("shape", [(64, 128), (37, 50), (16, 4, 3), (1, 4096)])
def test_forward_uses_only_table_values(shape):
    torch.manual_seed(0)
    w = torch.randn(shape)
    fp = qat.FakePalette(w, 4)
    q = fp(w)
    assert q.shape == w.shape
    assert max(_per_group_unique(q)) <= 16
    rows = fp.lut.detach()[torch.arange(shape[0]) // 16]          # every value is in its own group's table
    flat = q.detach().reshape(shape[0], -1)
    assert all(bool(torch.isin(flat[r], rows[r]).all()) for r in range(shape[0]))


def test_starts_from_the_data_free_kmeans():
    torch.manual_seed(1)
    w = torch.randn(48, 96)
    q = qat.FakePalette(w, 4)(w).detach()
    ref = cu.kmeans_groups(w, 4)
    assert float(((q - w) ** 2).mean()) <= float(((ref - w) ** 2).mean()) * 1.0001


def test_assignment_is_nearest_centroid():
    torch.manual_seed(2)
    w = torch.randn(32, 40)
    fp = qat.FakePalette(w, 3)
    with torch.no_grad():
        fp.lut.add_(torch.randn_like(fp.lut) * 0.3)              # move the tables, then reassign
    fp.refresh(w)
    lut = fp.lut.detach()[torch.arange(32) // 16]                 # [out, k]
    d = (w.reshape(32, -1, 1) - lut[:, None, :]).abs()
    brute = torch.gather(lut, 1, d.argmin(-1))
    assert torch.allclose(fp(w).detach().reshape(32, -1), brute)


def test_gradient_reaches_weights_and_tables():
    torch.manual_seed(3)
    lin = torch.nn.Linear(40, 32, bias=False)
    qat.attach(lin, "weight", 4)
    lin(torch.randn(8, 40)).pow(2).sum().backward()
    p = lin.parametrizations.weight
    assert p.original.grad is not None and float(p.original.grad.abs().sum()) > 0
    assert p[0].lut.grad is not None and float(p[0].lut.grad.abs().sum()) > 0


def _toy(bits):
    torch.manual_seed(4)
    teacher = torch.nn.Linear(64, 32)
    net = torch.nn.Module()
    net.encoder = torch.nn.Sequential(torch.nn.Linear(64, 32))
    net.encoder[0].load_state_dict(teacher.state_dict())
    qat.attach(net.encoder[0], "weight", bits)
    x = torch.randn(512, 64) * torch.logspace(-1, 1, 64)           # uneven input scales: data-free k-means is not optimal
    return net, x, teacher(x).detach()


def test_fixed_assignment_training_lowers_the_task_loss_and_stays_packable():
    """The default (tables + free parameters, assignments fixed) must beat its data-free starting point."""
    net, x, y = _toy(4)
    lin = net.encoder[0]
    loss0 = float(((lin(x) - y) ** 2).mean())
    free = qat.free_params(net, "small")
    assert list(free) == ["encoder.0.bias"]                       # the latent weight and the table are not "free"
    opt = torch.optim.Adam([lin.parametrizations.weight[0].lut, *free.values()], lr=1e-3)
    for _ in range(600):
        opt.zero_grad()
        ((lin(x) - y) ** 2).mean().backward()
        opt.step()
    loss1 = float(((lin(x) - y) ** 2).mean())
    assert loss1 < 0.95 * loss0, (loss0, loss1)
    w = qat.quantized_weights(lin)["weight"]
    assert max(_per_group_unique(w)) <= 16


def test_latent_training_stays_packable():
    """Straight-through latent weights (off by default: they made this toy worse) must still pack after reassignment."""
    net, x, y = _toy(2)
    lin = net.encoder[0]
    opt = torch.optim.SGD([lin.parametrizations.weight.original], lr=1e-2)
    for _ in range(50):
        opt.zero_grad()
        ((lin(x) - y) ** 2).mean().backward()
        opt.step()
        qat.refresh_all(lin)
    assert max(_per_group_unique(qat.quantized_weights(lin)["weight"])) <= 4


def test_quantized_weights_are_fp16_and_packable_after_the_cast():
    torch.manual_seed(5)
    lin = torch.nn.Linear(300, 33, bias=False)
    qat.attach(lin, "weight", 4)
    with torch.no_grad():                                          # two table entries 1 fp16 ulp apart must not split
        lin.parametrizations.weight[0].lut[:, 1] = lin.parametrizations.weight[0].lut[:, 0] + 1e-6
    w = qat.quantized_weights(lin)["weight"]
    assert w.dtype == torch.float16
    assert max(_per_group_unique(w)) <= 16


def test_check_packable_rejects_too_many_values():
    w = torch.arange(16 * 40, dtype=torch.float32).reshape(16, 40)
    with pytest.raises(ValueError):
        qat.check_packable("x", w, 4)
    qat.check_packable("y", torch.zeros(16, 40), 4)


def test_librispeech_manifest_reads_the_tree():
    import numpy as np
    import soundfile as sf

    with tempfile.TemporaryDirectory() as d:
        root = Path(d) / "LibriSpeech" / "dev-clean" / "84" / "121123"
        root.mkdir(parents=True)
        sf.write(root / "84-121123-0000.flac", np.zeros(32000, dtype="float32"), 16000)
        sf.write(root / "84-121123-0001.flac", np.zeros(8000, dtype="float32"), 16000)
        (root / "84-121123.trans.txt").write_text("84-121123-0000 GO DO YOU HEAR\n84-121123-0001 BUT IN LESS\n")
        out = Path(d) / "dev"
        n = qat.librispeech_manifest(Path(d) / "LibriSpeech", "dev-clean", out)
        rows = [json.loads(l) for l in (out / "manifest.jsonl").read_text().splitlines()]
        assert n == 2 and [r["clip_id"] for r in rows] == ["84-121123-0000", "84-121123-0001"]
        assert rows[0]["reference"] == "go do you hear" and rows[0]["speaker"] == "84"
        assert abs(rows[0]["audio_seconds"] - 2.0) < 1e-6
        assert (out / rows[0]["file"]).resolve() == (root / "84-121123-0000.flac").resolve()
        assert not os.path.isabs(rows[0]["file"])
        clips = cu.calib_clips(out, None, min_seconds=0.1)        # the same format the sensitivity sweep reads
        assert [c["clip_id"] for c in clips] == ["84-121123-0000", "84-121123-0001"]


def test_librispeech_manifest_refuses_a_missing_transcript_line():
    import numpy as np
    import soundfile as sf

    with tempfile.TemporaryDirectory() as d:
        root = Path(d) / "LibriSpeech" / "dev-clean" / "1" / "2"
        root.mkdir(parents=True)
        sf.write(root / "1-2-0000.flac", np.zeros(1600, dtype="float32"), 16000)
        (root / "1-2.trans.txt").write_text("1-2-0001 WRONG ID\n")
        with pytest.raises(ValueError):
            qat.librispeech_manifest(Path(d) / "LibriSpeech", "dev-clean", Path(d) / "out")


def test_spend_guard():
    assert not qat.over_budget(started=0.0, now=3599.0, hours=1.0)
    assert qat.over_budget(started=0.0, now=3600.0, hours=1.0)
    assert not qat.over_budget(started=0.0, now=1e9, hours=0)       # 0 = no limit (CPU dry run)


def test_batches_by_seconds_and_never_drops_a_clip():
    rows = [{"clip_id": str(i), "audio_seconds": s} for i, s in enumerate([5, 1, 30, 2, 9, 9, 40])]
    bs = qat.duration_batches(rows, batch_seconds=20, seed=0)
    ids = sorted(int(r["clip_id"]) for b in bs for r in b)
    assert ids == list(range(7))
    for b in bs:                                                   # over the cap only as a batch of one long clip
        assert sum(r["audio_seconds"] for r in b) <= 20 or len(b) == 1
