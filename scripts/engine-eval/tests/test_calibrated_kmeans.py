"""#272 k-means used for the calibrated builds. Core ML's palettize mode "unique" packs a weight exactly only if every
16-output-channel group holds at most 2**bits distinct values; these tests try to break that. Needs torch (mobius env)."""
import pytest

torch = pytest.importorskip("torch")
cu = pytest.importorskip("calibrated_ultra")


@pytest.mark.parametrize("shape", [(64, 128), (37, 50), (16, 4, 3, 3), (1, 4096)])
@pytest.mark.parametrize("bits", [2, 3, 4, 6])
def test_every_group_has_at_most_2_pow_bits_values(shape, bits):
    torch.manual_seed(0)
    w = torch.randn(shape)
    r = cu.kmeans_groups(w, bits)
    assert r.shape == w.shape and r.dtype == w.dtype
    flat = r.reshape(shape[0], -1)
    for s in range(0, shape[0], cu.GROUP):
        assert len(torch.unique(flat[s:s + cu.GROUP])) <= 1 << bits


def test_more_bits_never_worse():
    torch.manual_seed(1)
    w = torch.randn(128, 256) * torch.rand(128, 1)
    errs = [float(((cu.kmeans_groups(w, b) - w) ** 2).mean()) for b in (2, 3, 4, 6)]
    assert errs == sorted(errs, reverse=True)


@pytest.mark.parametrize("bits", [2, 3, 4])
def test_as_good_as_coremltools_own_kmeans(bits):
    """The data-free builds use coremltools' k-means; ours must not be a worse quantiser (within 10% MSE) at the low
    widths it is used for. At 6 bits it is 6-23% worse on real Ultra weights, so builds take every >= 6-bit weight from
    coremltools' own k-means (calibrated_ultra.split_plan)."""
    import numpy as np
    from coremltools.optimize.coreml._quantization_passes import palettize_weights as pw

    torch.manual_seed(4)
    w = torch.randn(64, 512) * torch.rand(64, 1) + 0.05 * torch.randn(64, 512) ** 3
    ours = float(((cu.kmeans_groups(w, bits) - w) ** 2).mean())
    ref = 0.0
    a = w.numpy()
    for s in range(0, 64, cu.GROUP):
        g = a[s:s + cu.GROUP]
        lut, idx = pw._get_lut_and_indices(g, "KMEANS", bits, None)
        ref += float(((lut.reshape(-1)[idx.reshape(g.shape)] - g) ** 2).sum())
    ref /= a.size
    assert ours <= ref * 1.10, (ours, ref)


def test_importance_pins_the_weights_that_matter():
    """Fewer dominant weights than centroids: weighted k-means must reproduce them almost exactly."""
    torch.manual_seed(2)
    w = torch.randn(16, 512)
    imp = torch.ones_like(w)
    imp[0, :3] = 1e9                                  # 3 dominant weights in the group, 4 centroids at 2 bits
    plain = cu.kmeans_groups(w, 2)
    weighted = cu.kmeans_groups(w, 2, importance=imp)
    assert float(((weighted - w)[0, :3] ** 2).sum()) < 1e-4
    assert float(((weighted - w)[0, :3] ** 2).sum()) < float(((plain - w)[0, :3] ** 2).sum())


def test_constant_and_tiny_groups_survive():
    w = torch.zeros(20, 9)
    w[16:] = 3.0                                      # second group is a short, padded one
    r = cu.kmeans_groups(w, 4)
    assert torch.equal(r, w)


def test_codes_round_trip():
    torch.manual_seed(3)
    w = torch.randn(40, 30)
    lut, idx = cu.kmeans_codes(w, 3)
    assert idx.dtype == torch.uint8 and int(idx.max()) < 8
    assert torch.equal(cu.decode_codes(lut, idx, w.shape), cu.kmeans_groups(w, 3))


def test_wide_weights_go_to_coremltools_and_low_ones_to_ours():
    plan = {"encoder.layers.0.self_attn.linear_q": 6, "encoder.layers.0.conv.pointwise_conv1": 4,
            "encoder.pre_encode.conv.0": 8, "encoder.layers.3.feed_forward1.linear1": 3}
    ours, theirs = cu.split_plan(plan)
    assert ours == {"encoder.layers.0.conv.pointwise_conv1": 4, "encoder.layers.3.feed_forward1.linear1": 3}
    assert theirs == {"encoder.layers.0.self_attn.linear_q": 6, "encoder.pre_encode.conv.0": 8}


def test_weight_key_matches_by_content_not_name():
    import numpy as np
    w = torch.randn(32, 64)
    assert cu.weight_key(w.numpy()) == cu.weight_key(w.numpy().astype(np.float16))   # export stores fp16
    assert cu.weight_key(w.numpy()) != cu.weight_key((w + 1e-2).numpy())
    assert cu.weight_key(w.numpy()) != cu.weight_key(w.numpy().T.copy())


def test_identical_weights_are_refused():
    lin = torch.nn.Linear(64, 64)
    twin = torch.nn.Linear(64, 64)
    twin.weight.data.copy_(lin.weight.data)
    with pytest.raises(ValueError):
        cu.torch_keys({"a": lin, "b": twin})


@pytest.mark.parametrize("bits", [3, 4])
def test_data_free_build_clustering_is_coremltools_exactly(bits):
    """A data-free build must reproduce the shipped builds' clustering value for value (same algorithm, same seed),
    so any difference in a calibrated build comes from calibration alone. Measured 2026-11-09: our own Lloyd's
    k-means had the same MSE yet scored 0.62 points worse than ultra-pal4 on shard 1."""
    import numpy as np
    from coremltools.optimize.coreml._quantization_passes import palettize_weights as pw

    torch.manual_seed(5)
    w = torch.randn(48, 1000) * 0.05                  # 16,000 per group: coremltools' kmeans1d branch, as real weights
    w[3, 7] = 0.9                                      # an outlier, as real weights have
    ours = cu.kmeans_sklearn(w, bits, workers=2).numpy()
    a = w.numpy().astype(np.float16)
    for s in range(0, 48, cu.GROUP):
        g = a[s:s + cu.GROUP]
        lut, idx = pw._get_lut_and_indices(g, "KMEANS", bits, None)
        ref = lut.reshape(-1)[idx.reshape(g.shape)].astype(np.float32)
        assert np.allclose(ours[s:s + cu.GROUP], ref, atol=1e-3), s
    small = torch.randn(32, 300) * 0.05               # 4,800 per group: the sklearn branch
    ours = cu.kmeans_sklearn(small, bits, workers=2).numpy()
    a = small.numpy().astype(np.float16)
    for s in range(0, 32, cu.GROUP):
        lut, idx = pw._get_lut_and_indices(a[s:s + cu.GROUP], "KMEANS", bits, None)
        assert np.allclose(ours[s:s + cu.GROUP], lut.reshape(-1)[idx.reshape(16, -1)].astype(np.float32), atol=1e-3)


def test_sample_weights_change_the_clustering():
    torch.manual_seed(6)
    w = torch.randn(16, 400)
    imp = torch.ones_like(w)
    imp[0, :3] = 1e6
    plain = cu.kmeans_sklearn(w, 2, workers=2)
    weighted = cu.kmeans_sklearn(w, 2, importance=imp, workers=2)
    assert float(((weighted - w)[0, :3] ** 2).sum()) < float(((plain - w)[0, :3] ** 2).sum())


def test_converter_folded_weights_are_never_quantised_in_torch():
    plan = {"encoder.layers.0.conv.depthwise_conv": 4, "encoder.layers.0.self_attn.linear_pos": 4,
            "encoder.layers.0.self_attn.linear_q": 4}
    ours, theirs = cu.split_plan(plan)
    assert ours == {"encoder.layers.0.self_attn.linear_q": 4}
    assert set(theirs) == {"encoder.layers.0.conv.depthwise_conv", "encoder.layers.0.self_attn.linear_pos"}


def test_fisher_cache_dtype_keeps_real_sized_importances():
    """Squared gradients are ~1e-12..1e-3; fp16 turned 98% of them into zeros or subnormals (2026-11-09)."""
    v = torch.tensor([1e-12, 3e-9, 5e-7, 2e-4, 0.15])
    back = v.to(torch.bfloat16).float()
    assert (back > 0).all()
    assert torch.allclose(back, v, rtol=1e-2)


def test_importance_weighting_survives_tiny_and_huge_ratios():
    import numpy as np
    torch.manual_seed(7)
    w = torch.randn(16, 1000) * 0.05
    imp = torch.rand(16, 1000) * 1e-9
    imp[0, :5] = 1e-2                                  # seven orders of magnitude apart, as real Fisher values
    imp[1, :100] = 0                                   # and exact zeros
    r = cu.kmeans_sklearn(w, 4, importance=imp, workers=2)
    assert torch.isfinite(r).all()
    assert len(np.unique(r[:16].numpy().astype(np.float16))) <= 16
