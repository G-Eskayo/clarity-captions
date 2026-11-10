"""Sortformer builds for #271 step 2, from the shipped compiled model.

  python -m sortformer_mil.cli rebuild --model Sortformer_v2.1.mlmodelc --out DIR [--opset ios18]
      rebuilds the shipped pipeline from its own MIL and weights: DIR/Sortformer_v2.1.mlpackage + .mlmodelc
  python -m sortformer_mil.cli parity --a A.mlmodelc --b B.mlmodelc [--n 24]
      the same seeded inputs through both; max differences per output and how often the speaker decisions differ
  python -m sortformer_mil.cli compress --model Sortformer_v2.1.mlmodelc --recipe pal6 --out DIR2
      rebuilds, compresses the head's weights (the pre-encoder stays as shipped) and compiles; recipes in RECIPES

Runs in the mobius conversion venv (coremltools 9.0b1). Never reads audio: calibration and scoring are elsewhere.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np

NAME = "Sortformer_v2.1"
HERE = Path(__file__).resolve().parent

# Head-only weight compression recipes. Chosen per bit width on calibration recordings, never on scored ones (#271).
RECIPES = {
    # 8-bit
    "pal8": dict(kind="palettize", nbits=8, granularity="per_tensor", opset="ios16"),
    "pal8g": dict(kind="palettize", nbits=8, granularity="per_grouped_channel", group_size=16, opset="ios18"),
    "int8": dict(kind="linear", dtype="int8", granularity="per_channel", opset="ios16"),
    # 6-bit
    "pal6": dict(kind="palettize", nbits=6, granularity="per_tensor", opset="ios16"),
    "pal6g": dict(kind="palettize", nbits=6, granularity="per_grouped_channel", group_size=16, opset="ios18"),
}
WEIGHT_THRESHOLD = 2048   # tensors smaller than this (biases, norms) stay 16-bit, as for Parakeet (#150)


def tree_sha(path: Path) -> str:
    h = hashlib.sha256()
    for f in sorted(p for p in path.rglob("*") if p.is_file()):
        h.update(str(f.relative_to(path)).encode())
        h.update(hashlib.sha256(f.read_bytes()).digest())
    return h.hexdigest()


def size_mb(path: Path) -> float:
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file()) / 2**20


def _compile(pkg: Path, out: Path) -> Path:
    import coremltools as ct
    if out.exists():
        shutil.rmtree(out)
    built = Path(ct.utils.compile_model(str(pkg)))
    shutil.move(str(built), str(out))
    return out


def cmd_rebuild(a) -> int:
    from .build import load_metadata, pipeline, rebuild
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    pre, head = rebuild(Path(a.model), a.opset)
    p = pipeline(pre, head, load_metadata(HERE / "metadata.json"))
    pkg = out / f"{NAME}.mlpackage"
    if pkg.exists():
        shutil.rmtree(pkg)
    p.save(str(pkg))
    mlc = _compile(pkg, out / f"{NAME}.mlmodelc")
    info = {"source": str(a.model), "source_tree_sha256": tree_sha(Path(a.model)), "opset": a.opset or "as shipped",
            "package_mb": round(size_mb(pkg), 1), "compiled_mb": round(size_mb(mlc), 1),
            "compiled_tree_sha256": tree_sha(mlc), "seconds": round(time.time() - t0, 1)}
    (out / "build.json").write_text(json.dumps(info, indent=2))
    print(json.dumps(info))
    return 0


def _inputs(rng, i: int) -> dict:
    # Seeded inputs spanning the states the app reaches: empty and full caches, short and full chunks.
    fifo_n = [0, 40, 17, 40][i % 4]
    cache_n = [0, 0, 94, 188][i % 4]
    chunk_n = [112, 112, 64, 112][i % 4]
    f = lambda *s: (rng.standard_normal(s) * 2 - 4).astype(np.float32)  # noqa: E731 - log-mel-like range
    return {"chunk": f(1, 112, 128), "chunk_lengths": np.array([chunk_n], np.int32),
            "fifo": rng.standard_normal((1, 40, 512)).astype(np.float32), "fifo_lengths": np.array([fifo_n], np.int32),
            "spkcache": rng.standard_normal((1, 188, 512)).astype(np.float32),
            "spkcache_lengths": np.array([cache_n], np.int32)}


def cmd_parity(a) -> int:
    import coremltools as ct
    units = {"cpu": ct.ComputeUnit.CPU_ONLY, "all": ct.ComputeUnit.ALL}[a.units]
    ma = ct.models.CompiledMLModel(a.a, compute_units=units)
    mb_ = ct.models.CompiledMLModel(a.b, compute_units=units)
    rng = np.random.default_rng(271)
    worst: dict = {}
    flips = total = 0
    for i in range(a.n):
        x = _inputs(rng, i)
        ya, yb = ma.predict(x), mb_.predict(x)
        if set(ya) != set(yb):
            print(f"outputs differ: {sorted(ya)} vs {sorted(yb)}")
            return 1
        for k in ya:
            d = float(np.max(np.abs(np.asarray(ya[k], np.float64) - np.asarray(yb[k], np.float64))))
            worst[k] = max(worst.get(k, 0.0), d)
        pa, pb = np.asarray(ya["speaker_preds"]) > 0.5, np.asarray(yb["speaker_preds"]) > 0.5
        flips += int(np.sum(pa != pb))
        total += pa.size
    res = {"units": a.units, "inputs": a.n, "max_abs_diff": worst, "speaker_decisions_differing": flips,
           "speaker_decisions": total}
    print(json.dumps(res))
    if a.exact and any(v != 0.0 for v in worst.values()):
        return 1
    return 0


def cmd_compress(a) -> int:
    """Rebuild from the shipped model (the code the parity gate passed) and compress the head in memory."""
    import coremltools.optimize.coreml as cto
    from .build import load_metadata, pipeline, rebuild
    r = RECIPES[a.recipe]
    t0 = time.time()
    pre, head = rebuild(Path(a.model), r["opset"])
    if r["kind"] == "palettize":
        kw = dict(mode="kmeans", nbits=r["nbits"], granularity=r["granularity"], weight_threshold=WEIGHT_THRESHOLD,
                  num_kmeans_workers=1)   # a worker pool crashed in #150
        if "group_size" in r:
            kw["group_size"] = r["group_size"]
        head_c = cto.palettize_weights(head, cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(**kw)))
    else:
        cfg = cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(
            mode="linear_symmetric", dtype=r["dtype"], granularity=r["granularity"], weight_threshold=WEIGHT_THRESHOLD))
        head_c = cto.linear_quantize_weights(head, cfg)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    p = pipeline(pre, head_c, load_metadata(HERE / "metadata.json"))
    dst = out / f"{NAME}.mlpackage"
    if dst.exists():
        shutil.rmtree(dst)
    p.save(str(dst))
    mlc = _compile(dst, out / f"{NAME}.mlmodelc")
    if not a.keep_package:
        shutil.rmtree(dst)            # rebuilt in seconds from the shipped model; the compiled model is what runs
    info = {"recipe": a.recipe, **r, "weight_threshold": WEIGHT_THRESHOLD, "source": str(a.model),
            "source_tree_sha256": tree_sha(Path(a.model)), "compiled_mb": round(size_mb(mlc), 1),
            "compiled_tree_sha256": tree_sha(mlc), "seconds": round(time.time() - t0, 1)}
    (out / "build.json").write_text(json.dumps(info, indent=2))
    print(json.dumps(info))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="sortformer_mil")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("rebuild")
    r.add_argument("--model", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--opset", choices=["ios16", "ios17", "ios18"])
    p = sub.add_parser("parity")
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    p.add_argument("--n", type=int, default=24)
    p.add_argument("--units", choices=["cpu", "all"], default="cpu")
    p.add_argument("--exact", action="store_true", help="fail unless every output is bit-identical")
    c = sub.add_parser("compress")
    c.add_argument("--model", required=True, help="the shipped Sortformer_v2.1.mlmodelc")
    c.add_argument("--keep-package", action="store_true")
    c.add_argument("--recipe", choices=sorted(RECIPES), required=True)
    c.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    return {"rebuild": cmd_rebuild, "parity": cmd_parity, "compress": cmd_compress}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
