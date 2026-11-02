"""A small ONNX → Core ML (MIL) translator for fixed-shape graphs, written for the ivrit.ai zipformer (#220).

coremltools dropped its ONNX front end, and the zipformer's PyTorch definition lives in icefall, which this repo does
not run. The ONNX export is a plain graph, so this reads it as data and rebuilds it in MIL.

Every input shape is fixed (batch 1, one 1.28 s chunk, fixed-size states), so the export's shape arithmetic (Shape,
Gather on shapes, Range, ConstantOfShape, ...) is computed here once, in numpy, and only the tensor maths becomes MIL
ops. Each op has a numpy implementation, used whenever all its inputs are known; feeding real arrays for every input
therefore evaluates the whole graph in numpy, which is the reference the Core ML build is checked against.

int64 has no place in Core ML: int64 values become int32 (every index and length here is far below 2**31).
Time and memory are O(nodes) to translate; the numpy reference is one pass over the graph.
"""
from __future__ import annotations

import functools
from dataclasses import dataclass
from typing import Any, Callable

import numpy as np

ONNX_DTYPES = {1: np.float32, 6: np.int32, 7: np.int64, 9: np.bool_, 10: np.float16, 11: np.float64}


class Unsupported(Exception):
    pass


@dataclass
class Live:
    """A tensor known only at run time: a MIL var with its static shape."""
    var: Any
    shape: tuple
    dtype: Any  # numpy dtype of the values (int32 for any integer, float32, bool)


def _attrs(node) -> dict:
    from onnx import helper
    return {a.name: helper.get_attribute_value(a) for a in node.attribute}


def _np_dtype_for_mil(dtype) -> Any:
    dtype = np.dtype(dtype)
    if dtype.kind in "iu":
        return np.int32
    if dtype.kind == "b":
        return np.bool_
    return np.float32


def _const(v: np.ndarray, like: Any = None):
    """A numpy value as a MIL const, cast to the live tensor's dtype when combined with one."""
    from coremltools.converters.mil import Builder as mb
    dt = like.dtype if isinstance(like, Live) else _np_dtype_for_mil(v.dtype)
    v = np.asarray(v).astype(dt)
    return mb.const(val=v if v.ndim else v.reshape(()))


def _mil(x, like: Any = None):
    return x.var if isinstance(x, Live) else _const(np.asarray(x), like)


def _mil_dtype(dt) -> str:
    return {np.dtype(np.float32): "fp32", np.dtype(np.int32): "int32", np.dtype(np.bool_): "bool"}[np.dtype(dt)]


def _live(var, shape, dtype) -> Live:
    return Live(var, tuple(int(d) for d in shape), np.dtype(dtype))


def _broadcast(*shapes) -> tuple:
    return tuple(np.broadcast_shapes(*[tuple(s) for s in shapes]))


def _shape(x) -> tuple:
    return x.shape if isinstance(x, Live) else np.shape(x)


def _dtype(x):
    return x.dtype if isinstance(x, Live) else _np_dtype_for_mil(np.asarray(x).dtype)


# --- numpy semantics (opset 13) -------------------------------------------------------------------------------------

def _np_slice(x, starts, ends, axes=None, steps=None):
    x = np.asarray(x)
    axes = list(range(len(starts))) if axes is None else [int(a) % x.ndim for a in axes]
    steps = [1] * len(starts) if steps is None else steps
    idx = [slice(None)] * x.ndim
    for s, e, a, st in zip(starts, ends, axes, steps):
        idx[a] = np.arange(x.shape[a])[slice(int(s), int(e), int(st))]  # numpy clamps out-of-range ends
    for ax, ind in enumerate(idx):
        if not isinstance(ind, slice):
            x = np.take(x, ind, axis=ax)
    return x


def _np_reshape_target(in_shape, shape) -> tuple:
    out = [in_shape[i] if int(d) == 0 else int(d) for i, d in enumerate(shape)]
    if -1 in out:
        known = int(np.prod([d for d in out if d != -1]))
        out[out.index(-1)] = int(np.prod(in_shape)) // known
    return tuple(out)


def _np_conv(x, w, b, a) -> np.ndarray:
    """Grouped N-d convolution by im2col; slow but only for the reference and constant folding."""
    x, w = np.asarray(x, np.float64), np.asarray(w, np.float64)
    nd = x.ndim - 2
    strides = a.get("strides", [1] * nd)
    dil = a.get("dilations", [1] * nd)
    pads = a.get("pads", [0] * (2 * nd))
    g = a.get("group", 1)
    x = np.pad(x, [(0, 0), (0, 0)] + [(pads[i], pads[i + nd]) for i in range(nd)])
    n, c = x.shape[:2]
    oc, icg = w.shape[:2]
    ks = w.shape[2:]
    out_sp = [(x.shape[2 + i] - dil[i] * (ks[i] - 1) - 1) // strides[i] + 1 for i in range(nd)]
    out = np.zeros((n, oc, *out_sp))
    ocg = oc // g
    for gi in range(g):
        xs = x[:, gi * icg:(gi + 1) * icg]
        ws = w[gi * ocg:(gi + 1) * ocg]
        for kidx in np.ndindex(*ks):
            sl = tuple(slice(kidx[i] * dil[i], kidx[i] * dil[i] + strides[i] * (out_sp[i] - 1) + 1, strides[i])
                       for i in range(nd))
            patch = xs[(slice(None), slice(None)) + sl]                      # n, icg, *out
            out[:, gi * ocg:(gi + 1) * ocg] += np.einsum("nc...,oc->no...", patch, ws[(slice(None), slice(None)) + kidx])
    if b is not None:
        out += np.asarray(b).reshape((1, -1) + (1,) * nd)
    return out.astype(np.float32)


def _np_cast(x, to):
    return np.asarray(x).astype(ONNX_DTYPES[to])


def _np_div(a, b):
    a, b = np.asarray(a), np.asarray(b)
    if a.dtype.kind in "iu" and b.dtype.kind in "iu":
        return np.trunc(a / b).astype(np.result_type(a, b))
    return a / b


def _softmax(x, axis):
    e = np.exp(x - np.max(x, axis=axis, keepdims=True))
    return e / np.sum(e, axis=axis, keepdims=True)


def _np_gather_elements(x, idx, axis):
    idx = np.where(idx < 0, idx + x.shape[axis], idx)
    return np.take_along_axis(np.asarray(x), idx, axis=axis)


def _reduce_axes(node, ins, a, ndim):
    axes = a.get("axes")
    if axes is None and len(ins) > 1 and ins[1] is not None:
        axes = [int(v) for v in np.asarray(ins[1]).ravel()]
    if axes is None or len(axes) == 0:
        if a.get("noop_with_empty_axes", 0):
            return None
        axes = list(range(ndim))
    return [int(v) % ndim for v in axes]


NUMPY: dict[str, Callable] = {
    "Add": lambda i, a: np.add(i[0], i[1]),
    "Sub": lambda i, a: np.subtract(i[0], i[1]),
    "Mul": lambda i, a: np.multiply(i[0], i[1]),
    "Div": lambda i, a: _np_div(i[0], i[1]),
    "Pow": lambda i, a: np.power(i[0], i[1]).astype(np.asarray(i[0]).dtype),
    "MatMul": lambda i, a: np.matmul(i[0], i[1]),
    "Gemm": lambda i, a: (a.get("alpha", 1.0) * np.matmul(i[0].T if a.get("transA") else i[0],
                                                         i[1].T if a.get("transB") else i[1])
                          + (a.get("beta", 1.0) * i[2] if len(i) > 2 else 0)).astype(np.float32),
    "Neg": lambda i, a: np.negative(i[0]),
    "Abs": lambda i, a: np.abs(i[0]),
    "Exp": lambda i, a: np.exp(i[0]),
    "Log": lambda i, a: np.log(i[0]),
    "Tanh": lambda i, a: np.tanh(i[0]),
    "Sigmoid": lambda i, a: (1 / (1 + np.exp(-i[0]))).astype(np.asarray(i[0]).dtype),
    "Relu": lambda i, a: np.maximum(i[0], 0),
    "Max": lambda i, a: functools.reduce(np.maximum, [np.asarray(v) for v in i]),
    "Clip": lambda i, a: np.clip(i[0], i[1] if len(i) > 1 and i[1] is not None else None,
                                 i[2] if len(i) > 2 and i[2] is not None else None),
    "Equal": lambda i, a: np.equal(i[0], i[1]),
    "LessOrEqual": lambda i, a: np.less_equal(i[0], i[1]),
    "GreaterOrEqual": lambda i, a: np.greater_equal(i[0], i[1]),
    "Where": lambda i, a: np.where(i[0], i[1], i[2]),
    "Cast": lambda i, a: _np_cast(i[0], a["to"]),
    "Shape": lambda i, a: np.array(np.shape(i[0]), dtype=np.int64),
    "Gather": lambda i, a: np.take(i[0], np.asarray(i[1]), axis=a.get("axis", 0)),
    "GatherElements": lambda i, a: _np_gather_elements(i[0], np.asarray(i[1]), a.get("axis", 0)),
    "Unsqueeze": lambda i, a: np.expand_dims(i[0], tuple(int(v) for v in np.asarray(i[1]).ravel())),
    "Squeeze": lambda i, a: np.squeeze(i[0], tuple(int(v) for v in np.asarray(i[1]).ravel())) if len(i) > 1
    else np.squeeze(i[0]),
    "Concat": lambda i, a: np.concatenate([np.asarray(v) for v in i], axis=a["axis"]),
    "Slice": lambda i, a: _np_slice(i[0], *[None if v is None else np.asarray(v).ravel() for v in i[1:]]),
    "Reshape": lambda i, a: np.reshape(i[0], _np_reshape_target(np.shape(i[0]), np.asarray(i[1]).ravel())),
    "Transpose": lambda i, a: np.transpose(i[0], a.get("perm")),
    "Expand": lambda i, a: np.broadcast_to(i[0], _broadcast(np.shape(i[0]), np.asarray(i[1]).ravel())).copy(),
    "Tile": lambda i, a: np.tile(i[0], np.asarray(i[1]).ravel()),
    "Range": lambda i, a: np.arange(np.asarray(i[0]).item(), np.asarray(i[1]).item(), np.asarray(i[2]).item(),
                                    dtype=np.asarray(i[0]).dtype),
    "ConstantOfShape": lambda i, a: np.full(np.asarray(i[0]).ravel(), _value_attr(a)),
    "Softmax": lambda i, a: _softmax(np.asarray(i[0]), a.get("axis", -1)),
    "Conv": lambda i, a: _np_conv(i[0], i[1], i[2] if len(i) > 2 else None, a),
    "ReduceMean": lambda i, a: _np_reduce(np.mean, i, a),
    "ReduceSum": lambda i, a: _np_reduce(np.sum, i, a),
}


def _np_reduce(fn, i, a):
    x = np.asarray(i[0])
    axes = _reduce_axes(None, i, a, x.ndim)
    if axes is None:
        return x
    return fn(x, axis=tuple(axes), keepdims=bool(a.get("keepdims", 1))).astype(x.dtype)


def _value_attr(a):
    from onnx import numpy_helper
    v = a.get("value")
    return np.float32(0) if v is None else numpy_helper.to_array(v).ravel()[0]


# --- MIL (run-time) implementations ---------------------------------------------------------------------------------

def _mil_binary(op: str):
    def f(node, i, a):
        from coremltools.converters.mil import Builder as mb
        x, y = i[0], i[1]
        like = x if isinstance(x, Live) else y
        dt = like.dtype
        out_shape = _broadcast(_shape(x), _shape(y))
        if op == "real_div" and np.dtype(dt).kind == "i":
            op_ = "floor_div"  # ONNX truncates; every integer divided here is non-negative
        else:
            op_ = op
        out_dt = np.bool_ if op in ("equal", "less_equal", "greater_equal") else dt
        return _live(getattr(mb, op_)(x=_mil(x, like), y=_mil(y, like)), out_shape, out_dt)
    return f


def _mil_unary(op: str):
    def f(node, i, a):
        from coremltools.converters.mil import Builder as mb
        x = i[0]
        return _live(getattr(mb, op)(x=x.var), x.shape, x.dtype)
    return f


def _m_neg(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    return _live(mb.mul(x=x.var, y=_const(np.array(-1), x)), x.shape, x.dtype)


def _m_pow(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x, p = i
    if not isinstance(p, Live) and np.all(np.asarray(p) == 2):
        return _live(mb.mul(x=x.var, y=x.var), x.shape, x.dtype)
    return _mil_binary("pow")(node, i, a)


def _m_matmul(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x, y = i
    xs, ys = _shape(x), _shape(y)
    if isinstance(x, Live) and not isinstance(y, Live) and np.ndim(y) == 2:
        w = np.asarray(y, np.float32)
        return _live(mb.linear(x=x.var, weight=w.T.copy()), (*xs[:-1], ys[-1]), x.dtype)
    out = np.matmul(np.zeros(xs, np.float32), np.zeros(ys, np.float32)).shape
    return _live(mb.matmul(x=_mil(x, y), y=_mil(y, x)), out, np.float32)


def _m_gemm(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x, w = i[0], np.asarray(i[1], np.float32)
    if a.get("transA") or not isinstance(x, Live) or isinstance(i[1], Live):
        raise Unsupported("Gemm with transA or a run-time weight")
    w = (w if a.get("transB") else w.T) * a.get("alpha", 1.0)
    b = np.asarray(i[2], np.float32) * a.get("beta", 1.0) if len(i) > 2 else np.zeros(w.shape[0], np.float32)
    return _live(mb.linear(x=x.var, weight=w.copy(), bias=b), (*x.shape[:-1], w.shape[0]), np.float32)


def _m_max(node, i, a):
    from coremltools.converters.mil import Builder as mb
    acc = i[0]
    for y in i[1:]:
        like = acc if isinstance(acc, Live) else y
        acc = _live(mb.maximum(x=_mil(acc, like), y=_mil(y, like)), _broadcast(_shape(acc), _shape(y)), like.dtype)
    return acc


def _m_clip(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    v = x.var
    if len(i) > 1 and i[1] is not None:
        v = mb.maximum(x=v, y=_const(np.asarray(i[1]), x))
    if len(i) > 2 and i[2] is not None:
        v = mb.minimum(x=v, y=_const(np.asarray(i[2]), x))
    return _live(v, x.shape, x.dtype)


def _m_where(node, i, a):
    from coremltools.converters.mil import Builder as mb
    c, x, y = i
    like = x if isinstance(x, Live) else (y if isinstance(y, Live) else None)
    if like is None:  # only the condition is live
        dt = _np_dtype_for_mil(np.result_type(np.asarray(x), np.asarray(y)))
        like = Live(None, (), np.dtype(dt))
    cond = c.var if isinstance(c, Live) else _const(np.asarray(c, bool))
    shape = _broadcast(_shape(c), _shape(x), _shape(y))
    return _live(mb.select(cond=cond, a=_mil(x, like), b=_mil(y, like)), shape, like.dtype)


def _m_cast(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    dt = np.dtype(_np_dtype_for_mil(ONNX_DTYPES[a["to"]]))
    if dt == x.dtype:
        return x
    return _live(mb.cast(x=x.var, dtype=_mil_dtype(dt)), x.shape, dt)


def _norm_axes(axes, ndim):
    return [int(v) % ndim for v in np.asarray(axes).ravel()]


def _m_gather(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x, idx = i
    axis = a.get("axis", 0) % len(_shape(x))
    xs = _shape(x)
    if isinstance(idx, Live):
        out = (*xs[:axis], *idx.shape, *xs[axis + 1:])
        return _live(mb.gather(x=_mil(x), indices=idx.var, axis=axis), out, _dtype(x))
    ind = np.asarray(idx)
    ind = np.where(ind < 0, ind + xs[axis], ind).astype(np.int32)
    out = (*xs[:axis], *ind.shape, *xs[axis + 1:])
    if ind.ndim == 0:
        v = mb.gather(x=x.var, indices=np.array([int(ind)], np.int32), axis=axis)
        return _live(mb.squeeze(x=v, axes=[axis]), out, x.dtype)
    return _live(mb.gather(x=x.var, indices=ind, axis=axis), out, x.dtype)


def _m_gather_elements(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x, idx = i
    axis = a.get("axis", 0) % len(_shape(x))
    if isinstance(idx, Live):
        ind = idx.var
    else:
        ind = np.asarray(idx)
        ind = np.where(ind < 0, ind + _shape(x)[axis], ind).astype(np.int32)
    return _live(mb.gather_along_axis(x=_mil(x), indices=ind, axis=axis), _shape(idx), _dtype(x))


def _m_unsqueeze(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    nd = len(x.shape) + np.asarray(i[1]).size
    axes = sorted(_norm_axes(i[1], nd))
    out = list(x.shape)
    for ax in axes:
        out.insert(ax, 1)
    return _live(mb.expand_dims(x=x.var, axes=axes), out, x.dtype)


def _m_squeeze(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    axes = _norm_axes(i[1], len(x.shape)) if len(i) > 1 else [k for k, d in enumerate(x.shape) if d == 1]
    out = [d for k, d in enumerate(x.shape) if k not in axes]
    return _live(mb.squeeze(x=x.var, axes=axes), out, x.dtype)


def _m_concat(node, i, a):
    from coremltools.converters.mil import Builder as mb
    like = next(v for v in i if isinstance(v, Live))
    shapes = [_shape(v) for v in i]
    axis = a["axis"] % len(shapes[0])
    out = list(shapes[0])
    out[axis] = sum(s[axis] for s in shapes)
    vals = [_mil(v, like) for v in i if np.prod(_shape(v)) > 0]
    if len(vals) == 1:
        return _live(vals[0], out, like.dtype)
    return _live(mb.concat(values=vals, axis=axis), out, like.dtype)


def _m_slice(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    starts, ends = np.asarray(i[1]).ravel(), np.asarray(i[2]).ravel()
    axes = _norm_axes(i[3], len(x.shape)) if len(i) > 3 and i[3] is not None else list(range(len(starts)))
    steps = np.asarray(i[4]).ravel() if len(i) > 4 and i[4] is not None else np.ones(len(starts), int)
    v, shape = x.var, list(x.shape)
    begin, end, stride = [0] * len(shape), list(shape), [1] * len(shape)
    gathers = []
    for s, e, ax, st in zip(starts, ends, axes, steps):
        r = range(*slice(int(s), int(e), int(st)).indices(shape[ax]))
        if int(st) == 1:
            begin[ax], end[ax] = r.start, max(r.start, r.stop)
        else:
            gathers.append((ax, np.array(list(r), np.int32)))
    out = [e - b for b, e in zip(begin, end)]
    if out != shape:
        v = mb.slice_by_index(x=v, begin=begin, end=end, stride=stride)
    for ax, ind in gathers:
        v = mb.gather(x=v, indices=ind, axis=ax)
        out[ax] = len(ind)
    return _live(v, out, x.dtype)


def _m_reshape(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    out = _np_reshape_target(x.shape, np.asarray(i[1]).ravel())
    return _live(mb.reshape(x=x.var, shape=np.array(out, np.int32)), out, x.dtype)


def _m_transpose(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    perm = a.get("perm") or list(range(len(x.shape)))[::-1]
    return _live(mb.transpose(x=x.var, perm=list(perm)), [x.shape[p] for p in perm], x.dtype)


def _m_tile_to(x: Live, target) -> Live:
    from coremltools.converters.mil import Builder as mb
    v, shape = x.var, list(x.shape)
    if len(target) > len(shape):
        shape = [1] * (len(target) - len(shape)) + shape
        v = mb.reshape(x=v, shape=np.array(shape, np.int32))
    reps = [t // s for t, s in zip(target, shape)]
    if any(r != 1 for r in reps):
        v = mb.tile(x=v, reps=reps)
    return _live(v, target, x.dtype)


def _m_expand(node, i, a):
    x = i[0]
    return _m_tile_to(x, _broadcast(x.shape, np.asarray(i[1]).ravel()))


def _m_tile(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x, reps = i[0], [int(r) for r in np.asarray(i[1]).ravel()]
    return _live(mb.tile(x=x.var, reps=reps), [d * r for d, r in zip(x.shape, reps)], x.dtype)


def _m_softmax(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x = i[0]
    return _live(mb.softmax(x=x.var, axis=a.get("axis", -1)), x.shape, x.dtype)


def _m_reduce(op):
    def f(node, i, a):
        from coremltools.converters.mil import Builder as mb
        x = i[0]
        axes = _reduce_axes(node, i, a, len(x.shape))
        if axes is None:
            return x
        keep = bool(a.get("keepdims", 1))
        out = [1 if k in axes else d for k, d in enumerate(x.shape)] if keep else \
              [d for k, d in enumerate(x.shape) if k not in axes]
        return _live(getattr(mb, op)(x=x.var, axes=axes, keep_dims=keep), out, x.dtype)
    return f


def _m_conv(node, i, a):
    from coremltools.converters.mil import Builder as mb
    x, w = i[0], np.asarray(i[1], np.float32)
    if isinstance(i[1], Live):
        raise Unsupported("Conv with a run-time weight")
    nd = len(x.shape) - 2
    pads = a.get("pads", [0] * (2 * nd))
    strides = a.get("strides", [1] * nd)
    dil = a.get("dilations", [1] * nd)
    mil_pad = [p for k in range(nd) for p in (pads[k], pads[k + nd])]
    kw = dict(x=x.var, weight=w, strides=strides, pad_type="custom", pad=mil_pad, dilations=dil,
              groups=a.get("group", 1))
    if len(i) > 2 and i[2] is not None:
        kw["bias"] = np.asarray(i[2], np.float32)
    out_sp = [(x.shape[2 + k] + pads[k] + pads[k + nd] - dil[k] * (w.shape[2 + k] - 1) - 1) // strides[k] + 1
              for k in range(nd)]
    return _live(mb.conv(**kw), (x.shape[0], w.shape[0], *out_sp), np.float32)


MIL: dict[str, Callable] = {
    "Add": _mil_binary("add"), "Sub": _mil_binary("sub"), "Mul": _mil_binary("mul"), "Div": _mil_binary("real_div"),
    "Equal": _mil_binary("equal"), "LessOrEqual": _mil_binary("less_equal"),
    "GreaterOrEqual": _mil_binary("greater_equal"),
    "Pow": _m_pow, "MatMul": _m_matmul, "Gemm": _m_gemm, "Neg": _m_neg, "Abs": _mil_unary("abs"),
    "Exp": _mil_unary("exp"), "Log": _mil_unary("log"), "Tanh": _mil_unary("tanh"), "Sigmoid": _mil_unary("sigmoid"),
    "Relu": _mil_unary("relu"), "Max": _m_max, "Clip": _m_clip, "Where": _m_where, "Cast": _m_cast,
    "Gather": _m_gather, "GatherElements": _m_gather_elements, "Unsqueeze": _m_unsqueeze, "Squeeze": _m_squeeze,
    "Concat": _m_concat, "Slice": _m_slice, "Reshape": _m_reshape, "Transpose": _m_transpose, "Expand": _m_expand,
    "Tile": _m_tile, "Softmax": _m_softmax, "ReduceMean": _m_reduce("reduce_mean"),
    "ReduceSum": _m_reduce("reduce_sum"), "Conv": _m_conv,
}


# --- the walk -------------------------------------------------------------------------------------------------------

def initial_values(model) -> dict:
    from onnx import numpy_helper
    return {t.name: numpy_helper.to_array(t) for t in model.graph.initializer}


def walk(model, values: dict) -> dict:
    """Evaluates the graph over `values` (name → numpy array or Live). Nodes whose inputs are all numpy are computed
    in numpy; the rest become MIL ops (which must run inside a MIL Function context). Returns every value."""
    from onnx import numpy_helper
    for node in model.graph.node:
        a = _attrs(node)
        if node.op_type == "Constant":
            values[node.output[0]] = numpy_helper.to_array(a["value"])
            continue
        ins = [values[n] if n else None for n in node.input]
        live = any(isinstance(v, Live) for v in ins)
        if node.op_type == "Shape":
            out = np.array(_shape(ins[0]), dtype=np.int64)
        elif not live:
            fn = NUMPY.get(node.op_type)
            if fn is None:
                raise Unsupported(node.op_type)
            out = fn(ins, a)
        else:
            fn = MIL.get(node.op_type)
            if fn is None:
                raise Unsupported(f"{node.op_type} on a run-time tensor ({node.name})")
            out = fn(node, ins, a)
        values[node.output[0]] = out
    return values


def evaluate(model, feeds: dict) -> dict:
    """The numpy reference: every graph output for concrete inputs."""
    values = {**initial_values(model), **{k: np.asarray(v) for k, v in feeds.items()}}
    walk(model, values)
    return {o.name: values[o.name] for o in model.graph.output}


def to_program(model, input_shapes: dict, opset=None, rename: Callable[[str], str] = lambda s: s):
    """A MIL Program with fixed input shapes ({name: (shape, numpy dtype)}). Integer inputs become int32 and boolean
    outputs are cast to int32. Output names pass through `rename` (Core ML names must be identifiers)."""
    import coremltools as ct
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.mil import Function, Program
    from coremltools.converters.mil.mil import types as mtypes

    opset = opset or ct.target.iOS18
    placeholders = {}
    for name, (shape, dt) in input_shapes.items():
        mt = mtypes.int32 if np.dtype(dt).kind in "iu" else mtypes.fp32
        placeholders[rename(name)] = mb.placeholder(shape=list(shape), dtype=mt)
    with Function(placeholders, opset_version=opset) as fn:
        values = initial_values(model)
        for name, (shape, dt) in input_shapes.items():
            values[name] = _live(fn.inputs[rename(name)], shape, _np_dtype_for_mil(dt))
        walk(model, values)
        outs = []
        for o in model.graph.output:
            v = values[o.name]
            if not isinstance(v, Live):
                raise Unsupported(f"output {o.name} is a constant")
            var = v.var if v.dtype != np.bool_ else mb.cast(x=v.var, dtype="int32")
            outs.append(mb.identity(x=var, name=rename(o.name)))
        fn.set_outputs(outs)
    prog = Program()
    prog.add_function("main", fn)
    return prog
