"""Low-bit Ultra builds (#203): which bits each encoder weight gets in the mixed 2/4/6 build. Pure, no coremltools."""
import pytest

from edacc_eval.lowbit import UNIFORM_BITS, average_bits, block_index, mixed_plan

# Const names as the mobius fp16 export names them (torch.jit trace of NeMo's ConformerEncoder, then coremltools).
N = 24


def names(n=N):
    out = ["pre_encode_conv_0_weight_to_fp16", "pre_encode_out_weight_to_fp16"]
    for i in range(n):
        out += [f"layers_{i}_feed_forward1_linear1_weight_to_fp16", f"layers_{i}_feed_forward1_linear2_weight_to_fp16",
                f"layers_{i}_self_attn_linear_q_weight_to_fp16", f"layers_{i}_self_attn_linear_k_weight_to_fp16",
                f"layers_{i}_self_attn_linear_v_weight_to_fp16", f"layers_{i}_self_attn_linear_out_weight_to_fp16",
                f"layers_{i}_self_attn_linear_pos_weight_to_fp16",
                f"layers_{i}_conv_pointwise_conv1_weight_to_fp16", f"layers_{i}_conv_pointwise_conv2_weight_to_fp16",
                f"layers_{i}_feed_forward2_linear1_weight_to_fp16", f"layers_{i}_feed_forward2_linear2_weight_to_fp16"]
    return out


def test_uniform_variants_are_the_ticket_bit_widths():
    assert UNIFORM_BITS == {"ultra-pal6": 6, "ultra-pal4": 4, "ultra-pal3": 3, "ultra-pal2": 2}


@pytest.mark.parametrize("name,idx", [
    ("layers_0_self_attn_linear_q_weight_to_fp16", 0),
    ("encoder_layers_23_conv_pointwise_conv1_weight", 23),
    ("model.layers.11.feed_forward2.linear1.weight", 11),
    ("pre_encode_out_weight_to_fp16", None),
    ("players_3_weight", None),          # 'layers' must be a whole path segment
    ("layers_7x_weight", None),
])
def test_block_index(name, idx):
    assert block_index(name) == idx


def test_mixed_plan_edges_six_attention_four_rest_two():
    plan = mixed_plan(names())
    assert plan["pre_encode_conv_0_weight_to_fp16"] == 6
    assert plan["layers_0_feed_forward1_linear1_weight_to_fp16"] == 6
    assert plan[f"layers_{N - 1}_conv_pointwise_conv2_weight_to_fp16"] == 6
    assert plan["layers_5_self_attn_linear_q_weight_to_fp16"] == 4
    assert plan["layers_5_self_attn_linear_pos_weight_to_fp16"] == 4
    assert plan["layers_5_feed_forward1_linear1_weight_to_fp16"] == 2
    assert plan["layers_5_conv_pointwise_conv1_weight_to_fp16"] == 2
    assert set(plan.values()) == {2, 4, 6}
    assert len(plan) == len(names())


def test_mixed_plan_depth_comes_from_the_names_not_a_constant():
    plan = mixed_plan(names(n=4))
    assert plan["layers_3_feed_forward1_linear1_weight_to_fp16"] == 6
    assert plan["layers_2_feed_forward1_linear1_weight_to_fp16"] == 2


def test_mixed_plan_refuses_names_it_cannot_read():
    # A renamed export must fail loudly, not silently become a uniform 6-bit (or 2-bit) build.
    with pytest.raises(ValueError, match="no conformer block"):
        mixed_plan(["weight_a", "weight_b"])


def test_mixed_plan_refuses_unknown_weights_inside_a_block():
    with pytest.raises(ValueError, match="layers_3_mystery"):
        mixed_plan(names(n=6) + ["layers_3_mystery_weight_to_fp16"])


def test_average_bits_is_weighted_by_weight_count():
    assert average_bits({"a": 2, "b": 6}, {"a": 3, "b": 1}) == pytest.approx(3.0)
    with pytest.raises(ValueError):
        average_bits({"a": 2}, {})


def test_mixed_plan_average_on_ultra_shapes_is_under_three_bits():
    # FastConformer-XL shapes (d_model 1024, ff 4096): the mix lands near 2.7 bits, the "about 2.5" the research asked for.
    sizes = {}
    for n in names():
        if "feed_forward" in n:
            sizes[n] = 1024 * 4096
        elif "self_attn" in n:
            sizes[n] = 1024 * 1024
        elif "pointwise_conv1" in n:
            sizes[n] = 2048 * 1024
        else:
            sizes[n] = 1024 * 1024
    avg = average_bits(mixed_plan(names()), sizes)
    assert 2.5 < avg < 3.0


def test_compressor_offers_every_build_and_imports_without_coremltools():
    # The eval venv has no coremltools; the variant list must still be importable and match the plan's names.
    import importlib.util
    from pathlib import Path

    from edacc_eval.lowbit import MIXED_NAME

    spec = importlib.util.spec_from_file_location("compress_parakeet",
                                                  Path(__file__).resolve().parents[1] / "compress_parakeet.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert set(mod.VARIANTS) == set(UNIFORM_BITS) | {MIXED_NAME}
