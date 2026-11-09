"""Low-bit Ultra builds (#203): which bits each encoder weight gets in the mixed 2/4/6 build. Pure, no coremltools."""
import pytest

from edacc_eval.lowbit import MIXED_PLANS, UNIFORM_BITS, average_bits, block_index, mixed_plan

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

    spec = importlib.util.spec_from_file_location("compress_parakeet",
                                                  Path(__file__).resolve().parents[1] / "compress_parakeet.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert set(mod.VARIANTS) == set(UNIFORM_BITS) | set(MIXED_PLANS)


def test_both_mixed_layouts_are_offered():
    # Decision mixed-layout on #219: build both.
    assert set(MIXED_PLANS) == {"ultra-mixed246", "ultra-mixed24"}


def test_lower_mixed_plan_edges_four_rest_two():
    plan = mixed_plan(names(), layout="ultra-mixed24")
    assert plan["pre_encode_conv_0_weight_to_fp16"] == 4
    assert plan["layers_0_self_attn_linear_q_weight_to_fp16"] == 4
    assert plan[f"layers_{N - 1}_feed_forward2_linear2_weight_to_fp16"] == 4
    assert plan["layers_5_self_attn_linear_q_weight_to_fp16"] == 2
    assert plan["layers_5_feed_forward1_linear1_weight_to_fp16"] == 2
    assert plan["layers_5_conv_pointwise_conv1_weight_to_fp16"] == 2
    assert set(plan.values()) == {2, 4}


def test_lower_mixed_plan_still_refuses_unknown_weights_inside_a_block():
    with pytest.raises(ValueError, match="layers_3_mystery"):
        mixed_plan(names(n=6) + ["layers_3_mystery_weight_to_fp16"], layout="ultra-mixed24")


def test_unknown_layout_is_refused():
    with pytest.raises(KeyError):
        mixed_plan(names(), layout="ultra-mixed99")


def test_lower_mixed_plan_average_on_ultra_shapes_is_near_two_point_two():
    sizes = {n: 1024 * (4096 if "feed_forward" in n else 2048 if "pointwise_conv1" in n else 1024) for n in names()}
    avg = average_bits(mixed_plan(names(), layout="ultra-mixed24"), sizes)
    assert 2.0 < avg < 2.3
    assert avg < average_bits(mixed_plan(names()), sizes)


# --- #272: bit plan from measured sensitivity --------------------------------------------------------------------

from edacc_eval.lowbit import plan_from_sensitivity  # noqa: E402


def sens(deltas, params, base=0.010, low=4):
    """deltas: group -> extra rel error at `low` bits; each group holds one weight named after it."""
    groups = {g: [f"{g}.w"] for g in deltas}
    rows = {"all@6": {"rel_error": base}}
    rows.update({f"{g}@{low}": {"rel_error": base + d} for g, d in deltas.items()})
    sizes = {f"{g}.w": params[g] for g in deltas}
    return {"meta": {"groups": groups, "base_bits": 6}, "rows": rows}, sizes


def test_promotes_the_most_sensitive_per_weight_first():
    s, sizes = sens({"a": 0.05, "b": 0.01, "c": 0.002}, {"a": 100, "b": 100, "c": 100})
    plan, _ = plan_from_sensitivity(s, sizes, target_bits=4 + 2 / 3)   # room for exactly one group at 6
    assert plan == {"a.w": 6, "b.w": 4, "c.w": 4}


def test_cost_is_per_weight_not_per_group():
    # big group a hurts more in total but far less per weight than small group b
    s, sizes = sens({"a": 0.04, "b": 0.03}, {"a": 1000, "b": 10})
    plan, _ = plan_from_sensitivity(s, sizes, target_bits=4.05)
    assert plan["b.w"] == 6 and plan["a.w"] == 4


def test_never_exceeds_the_bit_budget():
    rng = __import__("random").Random(7)
    d = {f"g{i}": rng.random() for i in range(40)}
    p = {f"g{i}": rng.randint(10, 1000) for i in range(40)}
    s, sizes = sens(d, p)
    for t in (4.0, 4.3, 4.75, 5.5):
        plan, _ = plan_from_sensitivity(s, sizes, target_bits=t)
        assert average_bits(plan, sizes) <= t + 1e-9


def test_budget_at_or_below_low_is_all_low_and_at_high_is_all_high():
    s, sizes = sens({"a": 0.1, "b": 0.2}, {"a": 5, "b": 5})
    assert set(plan_from_sensitivity(s, sizes, target_bits=4)[0].values()) == {4}
    assert set(plan_from_sensitivity(s, sizes, target_bits=6)[0].values()) == {6}


def test_missing_measurement_is_refused():
    s, sizes = sens({"a": 0.1, "b": 0.2}, {"a": 5, "b": 5})
    del s["rows"]["b@4"]
    with pytest.raises(ValueError):
        plan_from_sensitivity(s, sizes, target_bits=5)


def test_weight_outside_every_group_is_refused():
    s, sizes = sens({"a": 0.1}, {"a": 5})
    sizes["stray.w"] = 3
    with pytest.raises(ValueError):
        plan_from_sensitivity(s, sizes, target_bits=5)


def test_ties_break_by_name_so_the_plan_is_reproducible():
    s, sizes = sens({"b": 0.1, "a": 0.1}, {"a": 10, "b": 10})
    plan, _ = plan_from_sensitivity(s, sizes, target_bits=5)
    assert plan == {"a.w": 6, "b.w": 4}
