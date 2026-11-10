"""Rebuild a compiled Core ML model (.mlmodelc) as an editable .mlpackage from its own MIL text and weights (#271).

Same ops, same op order, same names, same weights (read from the model's own weight files through coremltools' blob
reader), converted with no graph passes, so the rebuilt model computes what the shipped one does. Every op's output
type and shape is checked against the type the compiled model declares for it. The parity gate (`cli.py parity`)
then compares outputs with the shipped model before anything is compressed.

Runs in a Python env with coremltools (the mobius conversion venv, coremltools 9.0b1).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import coremltools as ct
from coremltools import libmilstoragepython as storage
from coremltools.converters.mil.mil import Builder as mb
from coremltools.converters.mil.mil import Function as MilFunction
from coremltools.converters.mil.mil import Program, types

from .parse import Blob, MilParseError, parse_function

TARGETS = {"ios16": ct.target.iOS16, "ios17": ct.target.iOS17, "ios18": ct.target.iOS18}
MIL_TYPES = {"fp16": types.fp16, "fp32": types.fp32, "int32": types.int32, "bool": types.bool}
NP_TYPES = {"fp16": np.float16, "fp32": np.float32, "int32": np.int32, "bool": np.bool_, "uint64": np.uint64}
READERS = {"fp16": ("read_fp16_data", np.float16), "fp32": ("read_float_data", np.float32),
           "int32": ("read_int32_data", np.int32)}


def _const(st, folder: Path, readers: dict):
    v = st.value
    if isinstance(v, Blob):
        if v.dtype not in READERS:
            raise MilParseError(f"{st.op_name}: no blob reader for {v.dtype}")
        r = readers.get(v.path) or readers.setdefault(v.path, storage._BlobStorageReader(str(folder / v.path)))
        fn, npt = READERS[v.dtype]
        raw = np.asarray(getattr(r, fn)(v.offset))
        arr = raw.view(npt) if raw.dtype != npt else raw
        if arr.size != int(np.prod(v.shape)):
            raise MilParseError(f"{st.op_name}: blob has {arr.size} values, expected {v.shape}")
        return arr.reshape(v.shape).copy()
    dtype, shape = st.output_types[0]
    if dtype == "string":
        return v
    arr = np.array(v, dtype=NP_TYPES[dtype]).reshape(shape)
    # A scalar as a numpy scalar, not a 0-d array: coremltools' type inference misreads 0-d arrays (a split given
    # num_splits as a 0-d array kept the full width), while a numpy scalar keeps its dtype (fp16 stays fp16).
    return arr[()] if shape == () else arr


def _check(var, dtype: str, shape: tuple, where: str):
    want = MIL_TYPES.get(dtype)
    got_shape = tuple(int(d) for d in var.shape) if var.shape is not None else ()
    if want is not None and var.dtype != want:
        raise MilParseError(f"{where}: dtype {types.builtin_to_string(var.dtype)} != declared {dtype}")
    if got_shape != tuple(shape):
        raise MilParseError(f"{where}: shape {got_shape} != declared {shape}")


def build_program(mil_text: str, folder: Path, opset: str | None = None) -> Program:
    fn = parse_function(mil_text)
    target = TARGETS[opset or fn.opset]
    placeholders = {n: mb.placeholder(shape=s, dtype=MIL_TYPES[d]) for n, d, s in fn.inputs}
    readers: dict = {}
    with MilFunction(placeholders, opset_version=target) as f:
        env = dict(f.inputs)
        for st in fn.statements:
            if st.op == "const":
                out = mb.const(val=_const(st, folder, readers), name=st.outputs[0])
                outs = [out]
            else:
                kwargs = {k: (tuple(env[x] for x in v) if isinstance(v, tuple) else env[v]) for k, v in st.args.items()}
                single = len(st.outputs) == 1
                res = getattr(mb, st.op)(**kwargs, name=st.outputs[0] if single else st.op_name)
                outs = [res] if single else list(res)
            if len(outs) != len(st.outputs):
                raise MilParseError(f"{st.op_name}: {len(outs)} outputs, declared {len(st.outputs)}")
            for var, name, (dtype, shape) in zip(outs, st.outputs, st.output_types):
                if var.name != name:
                    var.name = name
                _check(var, dtype, shape, f"{st.op} {st.op_name} -> {name}")
                env[name] = var
        f.set_outputs([env[o] for o in fn.outputs])
    prog = Program()
    prog.add_function("main", f)
    return prog


def convert(prog: Program, opset: str) -> ct.models.MLModel:
    return ct.convert(prog, convert_to="mlprogram", minimum_deployment_target=TARGETS[opset],
                      compute_precision=ct.precision.FLOAT32, pass_pipeline=ct.PassPipeline.EMPTY,
                      skip_model_load=True)


def rebuild(compiled: Path, opset: str | None = None) -> tuple:
    """The two-model Sortformer pipeline (pre-encoder, head) as (pre, head) MLModels, each from its own MIL."""
    parts = []
    for sub in ("model0", "model1"):
        folder = compiled / sub
        text = (folder / "model.mil").read_text()
        op = opset or parse_function(text).opset
        parts.append(convert(build_program(text, folder, op), op))
    return tuple(parts)


def pipeline(pre: ct.models.MLModel, head: ct.models.MLModel, metadata: dict) -> ct.models.MLModel:
    p = ct.utils.make_pipeline(pre, head)
    for k, v in metadata.get("user_defined", {}).items():
        p.user_defined_metadata[k] = str(v)
    for attr in ("author", "license", "short_description", "version"):
        if metadata.get(attr):
            setattr(p, attr, metadata[attr])
    return p


def load_metadata(path: Path) -> dict:
    return json.loads(path.read_text()) if path.exists() else {}
