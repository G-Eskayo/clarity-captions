"""Convert the ivrit.ai zipformer's ONNX export to Core ML, then compress the encoder (#220).

    python -m zipformer_coreml.convert --onnx-dir <dir with encoder.onnx decoder.onnx joiner.onnx config.json>
        --out <dir> [--variants fp16 int8 pal6 pal4 pal3 pal2]

Writes <out>/<variant>/{Encoder,Decoder,Joiner}.mlpackage plus tokens.txt is copied by the caller. Every variant
shares the fp16 decoder and joiner (about 3.5 MB together); only the encoder (65 of the 66M parameters) is
compressed. Compression is weight-only, post-training, with no calibration audio:
- int8: linear 8-bit, per output channel (the Core ML counterpart of sherpa-onnx's int8 build);
- palN: k-means palettization to 2**N values, one lookup table per group of 16 output channels.
Method and results: docs/perf/hebrew-coreml-design.md.
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import numpy as np

from . import onnx_mil
from .decode import CONTEXT_SIZE, WINDOW

VARIANTS = ("fp32", "fp16", "int8", "pal6", "pal4", "pal3", "pal2")
GROUP = 16  # output channels per palettization lookup table


def encoder_inputs(config: dict) -> dict:
    """{name: (shape, dtype)} with batch 1: x, every state from config.json, then processed_lens."""
    shapes = {"x": ((1, WINDOW, config["feature_dim"]), np.float32)}
    for s in config["states"]:
        shape = tuple(1 if d in ("N", -1) else int(d) for d in s["shape"])
        shapes[s["name"]] = (shape, np.int64 if s["type"].startswith("int") else np.float32)
    return shapes


def init_states(config: dict) -> dict:
    return {k: np.zeros(shape, np.int32 if np.dtype(dt).kind in "iu" else np.float32)
            for k, (shape, dt) in encoder_inputs(config).items() if k != "x"}


def _convert(prog, precision: str):
    import coremltools as ct
    return ct.convert(prog, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                      compute_precision=ct.precision.FLOAT32 if precision == "fp32" else ct.precision.FLOAT16,
                      compute_units=ct.ComputeUnit.ALL)


def compress(model, variant: str):
    import coremltools.optimize.coreml as cto
    if variant in ("fp32", "fp16"):
        return model
    if variant == "int8":
        cfg = cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(
            mode="linear_symmetric", dtype="int8", granularity="per_channel"))
        return cto.linear_quantize_weights(model, cfg)
    if variant.startswith("pal"):
        bits = int(variant[3:])
        cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(
            mode="kmeans", nbits=bits, granularity="per_grouped_channel", group_size=GROUP))
        return cto.palettize_weights(model, cfg)
    raise ValueError(variant)


def build(onnx_dir: Path, out: Path, variants=("fp16",)) -> dict:
    """Returns {variant: {part: bytes on disk}}."""
    import onnx
    onnx_dir, out = Path(onnx_dir), Path(out)
    config = json.loads((onnx_dir / "config.json").read_text())
    enc = onnx.load(str(onnx_dir / "encoder.onnx"))
    enc_prog = onnx_mil.to_program(enc, encoder_inputs(config))
    dec_prog = onnx_mil.to_program(onnx.load(str(onnx_dir / "decoder.onnx")), {"y": ((1, CONTEXT_SIZE), np.int64)})
    join_prog = onnx_mil.to_program(onnx.load(str(onnx_dir / "joiner.onnx")),
                                    {"encoder_out": ((1, 512), np.float32), "decoder_out": ((1, 512), np.float32)})
    sizes = {}
    base = {}
    for v in variants:
        precision = "fp32" if v == "fp32" else "fp16"
        if precision not in base:
            base[precision] = (_convert(enc_prog, precision), _convert(dec_prog, precision),
                               _convert(join_prog, precision))
        e, d, j = base[precision]
        dest = out / v
        dest.mkdir(parents=True, exist_ok=True)
        parts = {"Encoder": compress(e, v), "Decoder": d, "Joiner": j}
        sizes[v] = {}
        for name, m in parts.items():
            p = dest / f"{name}.mlpackage"
            if p.exists():
                shutil.rmtree(p)
            m.save(str(p))
            sizes[v][name] = sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
        if (onnx_dir / "tokens.txt").exists():
            shutil.copy(onnx_dir / "tokens.txt", dest / "tokens.txt")
        (dest / "sizes.json").write_text(json.dumps(sizes[v], indent=2) + "\n")
    return sizes


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--onnx-dir", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--variants", nargs="+", default=["fp16"], choices=VARIANTS)
    a = ap.parse_args(argv)
    print(json.dumps(build(a.onnx_dir, a.out, a.variants), indent=2))


if __name__ == "__main__":
    main()
