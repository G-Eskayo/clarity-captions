"""The zipformer's ONNX → MIL translator (#220), op by op against its own numpy reference, and compression. These
compile real Core ML models, so they need coremltools and onnx (the conversion venv) and macOS; elsewhere they skip."""
import platform

import numpy as np
import pytest

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


@needs_mac
def test_compression_leaves_the_2d_front_end_at_full_precision():
    """At 4 and 2 bits a compressed front end silenced the encoder (#220); compression must skip it."""
    from zipformer_coreml import convert as zc
    nodes = [helper.make_node("Conv", ["x", "w2"], ["c2"], kernel_shape=[3, 3], pads=[1, 1, 1, 1]),
             helper.make_node("Reshape", ["c2", "flat"], ["f"]),
             helper.make_node("MatMul", ["f", "w"], ["y"])]
    m = _model(nodes, [("x", F, [1, 1, 8, 8])], [("y", F)],
               [("w2", rng.standard_normal((64, 1, 3, 3)).astype(np.float32)), ("flat", np.array([1, 4096], np.int64)),
                ("w", rng.standard_normal((4096, 32)).astype(np.float32))])
    base = zc._convert(onnx_mil.to_program(m, {"x": ((1, 1, 8, 8), np.float32)}), "fp16")
    assert zc.front_end_ops(base) == [o.name for f in base._mil_program.functions.values() for o in f.operations
                                       if o.op_type == "conv"]
    pal = zc.compress(base, "pal4")
    ops = [o.op_type for f in pal._mil_program.functions.values() for o in f.operations]
    assert ops.count("constexpr_lut_to_dense") == 1, "only the linear weight is palettized"
