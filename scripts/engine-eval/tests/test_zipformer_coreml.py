"""The zipformer's Core ML path (#220): the ONNX → MIL translator, op by op against its own numpy reference, and the
streaming greedy decoder against fakes. The translator tests compile real Core ML models, so they need coremltools
and onnx (the conversion venv) and macOS; elsewhere they skip."""
import platform

import numpy as np
import pytest

from zipformer_coreml import decode as zd


# --- decoding ---------------------------------------------------------------------------------------------------------

def test_windows_are_141_frames_128_apart_and_drop_a_partial_tail():
    assert list(zd.windows(140)) == []
    assert list(zd.windows(141)) == [(0, 141)]
    assert list(zd.windows(141 + 127)) == [(0, 141)]
    assert list(zd.windows(141 + 128)) == [(0, 141), (128, 269)]


def test_padding_adds_two_chunks_and_half_a_second_like_the_217_harness():
    out = zd.pad_for_streaming(np.ones(1000, np.float32))
    assert len(out) == 1000 + int(2 * 1.28 * 16000) + 8000
    assert np.all(out[1000:] == 0)


class FakeModel:
    """An encoder whose frame t of chunk c carries a scripted token; the joiner reads it back unless the decoder
    context already ends with it, so a scripted repeat is emitted only once per frame."""

    def __init__(self, script):
        self.script = script  # chunk index → {frame: token}
        self.contexts = []
        self.calls = 0

    def encode(self, window, states):
        assert window.shape == (1, zd.WINDOW, 80)
        out = np.zeros((1, zd.OUT_FRAMES, 4), np.float32)
        for t, k in self.script.get(self.calls, {}).items():
            out[0, t, 0] = k
        self.calls += 1
        return out, [s + 1 for s in states]

    def decode(self, context):
        self.contexts.append(context.tolist())
        return np.array([[float(context[0, -1])]], np.float32)

    def join(self, enc, dec):
        logits = np.zeros((1, 10), np.float32)
        logits[0, int(enc[0, 0])] = 1.0
        return logits


def test_greedy_emits_one_token_per_frame_and_shifts_the_context():
    fake = FakeModel({0: {3: 5, 10: 7}, 1: {0: 5}})
    frames = np.zeros((141 + 128, 80), np.float32)
    seen, emitted = [], []
    toks = zd.greedy(frames, fake.encode, fake.decode, fake.join, [0], on_chunk=lambda i, t: seen.append((i, list(t))),
                     on_token=lambda i, t: emitted.append((i, t)))
    assert toks == [5, 7, 5]
    assert fake.contexts == [[[-1, 0]], [[0, 5]], [[5, 7]], [[7, 5]]]
    assert seen == [(0, [5, 7]), (1, [5, 7, 5])]
    assert emitted == [(0, 3), (0, 10), (1, 0)]


def test_greedy_rejects_an_encoder_with_the_wrong_chunk_length():
    def encode(w, s):
        return np.zeros((1, 64, 4), np.float32), s
    with pytest.raises(ValueError, match="expected 32"):
        zd.greedy(np.zeros((141, 80), np.float32), encode, lambda c: np.zeros((1, 4)), lambda e, d: np.zeros((1, 3)),
                  [])


def test_tokens_to_text_joins_pieces_and_skips_unknown_ids(tmp_path):
    p = tmp_path / "tokens.txt"
    p.write_text("<blk> 0\n▁של 1\nום 2\n▁שלום 3\n", encoding="utf-8")
    table = zd.read_tokens(p)
    assert zd.to_text([3, 1, 2, 99], table) == "שלום שלום"


def test_token_latency_is_the_wait_to_the_chunk_end_plus_that_chunks_compute():
    from zipformer_coreml.run import token_latencies
    events = [("tok", 0, 0), ("tok", 0, 31), (0, 0.05, 2), ("tok", 1, 15), (1, 0.03, 3)]
    lat, compute = token_latencies(events)
    assert compute == [0.05, 0.03]
    np.testing.assert_allclose(lat, [1.28 - 0.04 + 0.05, 0.0 + 0.05, 1.28 - 0.64 + 0.03])


# --- the translator ---------------------------------------------------------------------------------------------------

onnx = pytest.importorskip("onnx")
ct = pytest.importorskip("coremltools")
needs_mac = pytest.mark.skipif(platform.system() != "Darwin", reason="Core ML predicts on macOS only")

from onnx import TensorProto, helper, numpy_helper  # noqa: E402

from zipformer_coreml import onnx_mil  # noqa: E402

F, I64, BOOL = TensorProto.FLOAT, TensorProto.INT64, TensorProto.BOOL


def _model(nodes, inputs, outputs, inits=()):
    g = helper.make_graph(nodes, "t", [helper.make_tensor_value_info(n, t, s) for n, t, s in inputs],
                          [helper.make_tensor_value_info(n, t, None) for n, t in outputs],
                          [numpy_helper.from_array(v, n) for n, v in inits])
    return helper.make_model(g, opset_imports=[helper.make_opsetid("", 13)])


def _run_both(m, feeds, atol=1e-4):
    ref = onnx_mil.evaluate(m, feeds)
    shapes = {k: (v.shape, v.dtype) for k, v in feeds.items()}
    prog = onnx_mil.to_program(m, shapes)
    ml = ct.convert(prog, convert_to="mlprogram", compute_precision=ct.precision.FLOAT32,
                    compute_units=ct.ComputeUnit.CPU_ONLY, minimum_deployment_target=ct.target.iOS18)
    got = ml.predict({k: (v.astype(np.int32) if v.dtype.kind in "iu" else v) for k, v in feeds.items()})
    for name, want in ref.items():
        want = np.asarray(want)
        np.testing.assert_allclose(np.asarray(got[name]).reshape(want.shape), want.astype(np.float64), atol=atol,
                                   err_msg=name)
    return ref


rng = np.random.default_rng(0)


@needs_mac
def test_elementwise_and_linear_ops_match_numpy():
    x = rng.standard_normal((1, 6, 8)).astype(np.float32)
    w = rng.standard_normal((8, 5)).astype(np.float32)
    nodes = [helper.make_node("MatMul", ["x", "w"], ["mm"]),
             helper.make_node("Sigmoid", ["mm"], ["s"]),
             helper.make_node("Mul", ["s", "mm"], ["sw"]),
             helper.make_node("Pow", ["sw", "two"], ["sq"]),
             helper.make_node("Abs", ["mm"], ["ab"]),
             helper.make_node("Add", ["ab", "one"], ["ab1"]),
             helper.make_node("Log", ["ab1"], ["lg"]),
             helper.make_node("Neg", ["lg"], ["ng"]),
             helper.make_node("Exp", ["ng"], ["ex"]),
             helper.make_node("Div", ["ex", "two"], ["dv"]),
             helper.make_node("Sub", ["dv", "sq"], ["sb"]),
             helper.make_node("Max", ["sb", "one"], ["mx"]),
             helper.make_node("Tanh", ["mx"], ["y"]),
             helper.make_node("Softmax", ["mm"], ["sm"], axis=-1),
             helper.make_node("ReduceMean", ["mm"], ["rm"], axes=[2], keepdims=1)]
    m = _model(nodes, [("x", F, [1, 6, 8])], [("y", F), ("sm", F), ("rm", F)],
               [("w", w), ("two", np.array(2.0, np.float32)), ("one", np.array(1.0, np.float32))])
    _run_both(m, {"x": x})


@needs_mac
def test_shape_arithmetic_folds_to_constants_and_reshapes_transpose_slice_work():
    x = rng.standard_normal((4, 1, 12)).astype(np.float32)
    nodes = [helper.make_node("Shape", ["x"], ["shp"]),
             helper.make_node("Gather", ["shp", "zero"], ["t"], axis=0),
             helper.make_node("Unsqueeze", ["t", "ax0"], ["t1"]),
             helper.make_node("Concat", ["t1", "three", "four"], ["newshape"], axis=0),
             helper.make_node("Reshape", ["x", "newshape"], ["r"]),
             helper.make_node("Transpose", ["r"], ["tr"], perm=[1, 0, 2]),
             helper.make_node("Slice", ["tr", "s_start", "s_end", "s_axes"], ["sl"]),
             helper.make_node("Slice", ["tr", "r_start", "r_end", "r_axes", "r_steps"], ["rev"]),
             helper.make_node("Squeeze", ["sl", "ax0"], ["sq"]),
             helper.make_node("Tile", ["sq", "reps"], ["tl"]),
             helper.make_node("Expand", ["x", "eshape"], ["ex"])]
    i64 = lambda *v: np.array(v, np.int64)  # noqa: E731
    m = _model(nodes, [("x", F, [4, 1, 12])], [("tr", F), ("sl", F), ("rev", F), ("tl", F), ("ex", F)],
               [("zero", np.array(0, np.int64)), ("ax0", i64(0)), ("three", i64(3)), ("four", i64(4)),
                ("s_start", i64(1, 1)), ("s_end", i64(2, 9223372036854775807)), ("s_axes", i64(0, 2)),
                ("r_start", i64(-1)), ("r_end", i64(-9223372036854775807)), ("r_axes", i64(1)), ("r_steps", i64(-1)),
                ("reps", i64(2, 1)), ("eshape", i64(2, 4, 3, 12))])
    _run_both(m, {"x": x})


@needs_mac
def test_integer_masks_where_cast_and_gathers_match_numpy():
    lens = np.array([5], np.int64)
    x = rng.standard_normal((1, 8, 3)).astype(np.float32)
    nodes = [helper.make_node("Range", ["r0", "r8", "r1"], ["rng"]),
             helper.make_node("Unsqueeze", ["lens", "ax1"], ["l2"]),
             helper.make_node("LessOrEqual", ["l2", "rng"], ["le"]),
             helper.make_node("Cast", ["le"], ["lei"], to=6),
             helper.make_node("Add", ["lens", "r8"], ["newlens"]),
             helper.make_node("Div", ["newlens", "r2"], ["half"]),
             helper.make_node("Equal", ["lei", "r1i"], ["eq"]),
             helper.make_node("Unsqueeze", ["eq", "ax2"], ["eq3"]),
             helper.make_node("Where", ["eq3", "neg", "x"], ["masked"]),
             helper.make_node("GatherElements", ["x", "gidx"], ["ge"], axis=1),
             helper.make_node("Gather", ["x", "gi"], ["g"], axis=1),
             helper.make_node("ReduceSum", ["x"], ["rs"], keepdims=0)]
    m = _model(nodes, [("x", F, [1, 8, 3]), ("lens", I64, [1])],
               [("lei", TensorProto.INT32), ("half", I64), ("masked", F), ("ge", F), ("g", F), ("rs", F)],
               [("r0", np.array(0, np.int64)), ("r8", np.array(8, np.int64)), ("r1", np.array(1, np.int64)),
                ("r2", np.array(2, np.int64)), ("r1i", np.array(1, np.int32)), ("ax1", np.array([1], np.int64)),
                ("ax2", np.array([2], np.int64)), ("neg", np.array(-1000.0, np.float32)),
                ("gidx", rng.integers(0, 8, (1, 4, 3)).astype(np.int64)), ("gi", np.array([7, 0, -1], np.int64))])
    _run_both(m, {"x": x, "lens": lens})


@needs_mac
def test_grouped_and_pointwise_convs_gemm_and_embedding_match_numpy():
    x = rng.standard_normal((1, 6, 20)).astype(np.float32)
    x2 = rng.standard_normal((1, 2, 9, 7)).astype(np.float32)
    y = np.array([[-1, 3]], np.int64)
    emb = rng.standard_normal((10, 4)).astype(np.float32)
    nodes = [helper.make_node("Conv", ["x", "dw", "db"], ["c1"], group=6, kernel_shape=[5], pads=[4, 0]),
             helper.make_node("Conv", ["x2", "w2", "b2"], ["c2"], kernel_shape=[3, 3], strides=[2, 1],
                              pads=[0, 1, 0, 1]),
             helper.make_node("Clip", ["y", "zero"], ["yc"]),
             helper.make_node("Gather", ["emb", "yc"], ["e"], axis=0),
             helper.make_node("GreaterOrEqual", ["y", "zero"], ["ok"]),
             helper.make_node("Cast", ["ok"], ["okf"], to=1),
             helper.make_node("Unsqueeze", ["okf", "ax2"], ["ok3"]),
             helper.make_node("Mul", ["e", "ok3"], ["em"]),
             helper.make_node("Relu", ["em"], ["er"]),
             helper.make_node("Reshape", ["er", "flat"], ["ef"]),
             helper.make_node("Gemm", ["ef", "gw", "gb"], ["gm"], transB=1)]
    m = _model(nodes, [("x", F, [1, 6, 20]), ("x2", F, [1, 2, 9, 7]), ("y", I64, [1, 2])],
               [("c1", F), ("c2", F), ("gm", F)],
               [("dw", rng.standard_normal((6, 1, 5)).astype(np.float32)), ("db", rng.standard_normal(6).astype(np.float32)),
                ("w2", rng.standard_normal((3, 2, 3, 3)).astype(np.float32)),
                ("b2", rng.standard_normal(3).astype(np.float32)), ("zero", np.array(0, np.int64)), ("emb", emb),
                ("ax2", np.array([2], np.int64)), ("flat", np.array([1, 8], np.int64)),
                ("gw", rng.standard_normal((5, 8)).astype(np.float32)), ("gb", rng.standard_normal(5).astype(np.float32))])
    ref = _run_both(m, {"x": x, "x2": x2, "y": y})
    assert ref["c1"].shape == (1, 6, 20) and ref["c2"].shape == (1, 3, 4, 7)


def test_an_unknown_op_on_a_live_tensor_is_named():
    m = _model([helper.make_node("Erf", ["x"], ["y"])], [("x", F, [2])], [("y", F)])
    with pytest.raises(onnx_mil.Unsupported, match="Erf"):
        onnx_mil.to_program(m, {"x": ((2,), np.float32)})
