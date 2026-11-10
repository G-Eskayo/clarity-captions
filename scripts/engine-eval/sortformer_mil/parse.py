"""Parse the MIL text inside a compiled Core ML model (`model.mil`) into plain Python statements (#271 step 2).

The Sortformer we ship is only published compiled (FluidInference `v3/fp16/Sortformer_v2.1.mlmodelc`): coremltools
can't load or compress a compiled model, and the one `.mlpackage` beside it is an older, different export. But the
compiled model is MIL text plus weight files, so it can be rebuilt as an editable program from the bytes we ship,
with no re-export (`build.py`). This half is pure Python: every line must parse, an unknown line or an undefined name
is an error, never skipped.
"""
from __future__ import annotations

import ast
import re
from dataclasses import dataclass, field


class MilParseError(ValueError):
    pass


@dataclass(frozen=True)
class Blob:
    """A const stored in a weight file: path relative to the model folder, byte offset of its blob header."""
    path: str
    offset: int
    dtype: str
    shape: tuple


@dataclass
class Statement:
    op: str
    outputs: list                # variable names, left of `=`
    output_types: list           # (dtype, shape) per output
    op_name: str                 # the op's own name attribute
    args: dict = field(default_factory=dict)   # name -> variable name, or a tuple of them
    value: object = None         # const only: a literal (scalar or nested list) or a Blob


@dataclass
class Function:
    opset: str
    inputs: list                 # (name, dtype, shape)
    outputs: list
    statements: list


_TYPE = re.compile(r"^tensor<(\w+), \[([0-9, ]*)\]>$")
_HEX = re.compile(r"[-+]?0x[0-9a-fA-F]*\.?[0-9a-fA-F]*p[-+]?\d+")
_FUNC = re.compile(r"^\s*func main<(\w+)>\((.*)\) \{\s*$")
_RET = re.compile(r"^\s*\} -> \((.*)\);\s*$")
_OPNAME = re.compile(r'\[name = tensor<string, \[\]>\("([^"]*)"\)')
_BLOB = re.compile(r'^BLOBFILE\(path = tensor<string, \[\]>\("@model_path/([^"]+)"\), offset = tensor<uint64, \[\]>\((\d+)\)\)$')


def parse_type(text: str) -> tuple:
    m = _TYPE.match(text.strip())
    if not m:
        raise MilParseError(f"not a tensor type: {text!r}")
    dims = tuple(int(d) for d in m.group(2).split(",") if d.strip())
    return m.group(1), dims


def _shape_of(v) -> tuple:
    if isinstance(v, list):
        if not v:
            return (0,)
        inner = {_shape_of(x) for x in v}
        if len(inner) != 1:
            raise MilParseError("ragged literal")
        return (len(v),) + inner.pop()
    return ()


def parse_literal(dtype: str, shape: tuple, text: str):
    """A const's inline value: hex floats exact, MIL true/false, nested lists checked against the declared shape."""
    text = text.strip()
    if dtype == "string":
        v = ast.literal_eval(text)
        if not isinstance(v, str):
            raise MilParseError(f"not a string: {text!r}")
        return v
    py = _HEX.sub(lambda m: repr(float.fromhex(m.group(0))), text)
    py = re.sub(r"\btrue\b", "True", re.sub(r"\bfalse\b", "False", py))
    py = re.sub(r"(?<![\w.])(-?)inf\b", r'float("\1inf")', py)
    py = re.sub(r"\bnan\b", 'float("nan")', py)
    try:
        v = eval(py, {"__builtins__": {}, "float": float})  # noqa: S307 - only literals survive the rewrites above
    except Exception as e:  # noqa: BLE001
        raise MilParseError(f"bad literal {text[:60]!r}: {e}") from e
    if _shape_of(v) != tuple(shape):
        raise MilParseError(f"literal shape {_shape_of(v)} != declared {shape}")
    return v


def _split_top(text: str, sep: str = ",") -> list:
    """Split on `sep` outside (), [], <> and quotes."""
    out, depth, cur, quote = [], 0, [], False
    for ch in text:
        if ch == '"':
            quote = not quote
        elif not quote:
            if ch in "([<":
                depth += 1
            elif ch in ")]>":
                depth -= 1
            elif ch == sep and depth == 0:
                out.append("".join(cur).strip())
                cur = []
                continue
        cur.append(ch)
    if "".join(cur).strip():
        out.append("".join(cur).strip())
    return out


def _typed_name(text: str) -> tuple:
    """`tensor<fp16, [1, 2]> name` -> (name, dtype, shape)."""
    i = text.rfind(" ")
    if i < 0:
        raise MilParseError(f"expected '<type> <name>': {text!r}")
    dtype, shape = parse_type(text[:i])
    return text[i + 1:].strip(), dtype, shape


def _matching(text: str, start: int) -> int:
    """Index of the bracket closing the one at `start`."""
    open_ch = text[start]
    close_ch = {"(": ")", "[": "]"}[open_ch]
    depth, quote = 0, False
    for i in range(start, len(text)):
        ch = text[i]
        if ch == '"':
            quote = not quote
        elif not quote:
            if ch == open_ch:
                depth += 1
            elif ch == close_ch:
                depth -= 1
                if depth == 0:
                    return i
    raise MilParseError("unbalanced brackets")


def parse_statement(line: str) -> Statement:
    line = line.strip()
    if not line.endswith(";"):
        raise MilParseError(f"not a statement: {line[:80]!r}")
    eq = line.find(" = ")
    if eq < 0:
        raise MilParseError(f"not a statement: {line[:80]!r}")
    lhs = [_typed_name(t) for t in _split_top(line[:eq])]
    rhs = line[eq + 3:-1]
    m = re.match(r"(\w+)\(", rhs)
    if not m:
        raise MilParseError(f"no op call: {rhs[:80]!r}")
    op = m.group(1)
    close = _matching(rhs, m.end() - 1)
    argtext, attrs = rhs[m.end():close], rhs[close + 1:]
    nm = _OPNAME.search(attrs)
    if not attrs.startswith("[") or not nm:
        raise MilParseError(f"op without a name attribute: {rhs[:80]!r}")
    st = Statement(op=op, outputs=[n for n, _, _ in lhs], output_types=[(d, s) for _, d, s in lhs], op_name=nm.group(1))
    if op == "const":
        if argtext.strip() or len(lhs) != 1:
            raise MilParseError(f"odd const: {line[:80]!r}")
        vi = attrs.find("val = ")
        if vi < 0:
            raise MilParseError(f"const without val: {line[:80]!r}")
        val = attrs[vi + 6:]
        p = val.find("(")
        dtype, shape = parse_type(val[:p])
        if (dtype, shape) != (lhs[0][1], lhs[0][2]):
            raise MilParseError(f"const type differs from its variable: {line[:80]!r}")
        inner = val[p + 1:_matching(val, p)]
        b = _BLOB.match(inner)
        st.value = Blob(b.group(1), int(b.group(2)), dtype, shape) if b else parse_literal(dtype, shape, inner)
        return st
    for part in _split_top(argtext):
        k, _, v = part.partition(" = ")
        v = v.strip()
        if not k or not v:
            raise MilParseError(f"bad argument {part!r}")
        if v.startswith("("):
            st.args[k.strip()] = tuple(x.strip() for x in _split_top(v[1:-1]))
        elif re.fullmatch(r"\w+", v):
            st.args[k.strip()] = v
        else:
            raise MilParseError(f"inline argument values are not expected: {part!r}")
    return st


def parse_function(text: str) -> Function:
    """The single `main` function of a model.mil, checked: every argument names an input or an earlier output."""
    lines = text.splitlines()
    fstart = next((i for i, l in enumerate(lines) if _FUNC.match(l)), None)
    if fstart is None:
        raise MilParseError("no `func main` in this model.mil")
    fm = _FUNC.match(lines[fstart])
    inputs = [_typed_name(t) for t in _split_top(fm.group(2))]
    known = {n for n, _, _ in inputs}
    statements, outputs = [], None
    for line in lines[fstart + 1:]:
        r = _RET.match(line)
        if r:
            outputs = [x.strip() for x in r.group(1).split(",")]
            break
        if not line.strip():
            continue
        st = parse_statement(line)
        for v in st.args.values():
            for name in (v if isinstance(v, tuple) else (v,)):
                if name not in known:
                    raise MilParseError(f"{st.op_name}: argument {name!r} is not defined before use")
        known.update(st.outputs)
        statements.append(st)
    if outputs is None:
        raise MilParseError("function has no return line")
    missing = [o for o in outputs if o not in known]
    if missing:
        raise MilParseError(f"returns undefined {missing}")
    return Function(opset=fm.group(1), inputs=[(n, d, s) for n, d, s in inputs], outputs=outputs, statements=statements)
