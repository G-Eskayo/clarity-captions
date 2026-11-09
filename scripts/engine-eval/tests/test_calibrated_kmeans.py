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


def test_coreml_const_names():
    assert cu.coreml_const("encoder.layers.11.self_attn.linear_q") == "layers_11_self_attn_linear_q_weight_to_fp16"
    assert cu.coreml_const("encoder.pre_encode.conv.0") == "pre_encode_conv_0_weight_to_fp16"
