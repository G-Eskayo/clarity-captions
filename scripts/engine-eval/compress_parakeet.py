#!/usr/bin/env python3
"""Compressed Parakeet Ultra encoders for the size test (#150 "[E] Switch captions to Parakeet Ultra") and the
low-bit test (#203 "2-bit north star, English first": 3-bit, 2-bit and mixed 2/4/6-bit).

Input: the fp16 Ultra encoder .mlpackage exported with FluidInference/mobius
(models/stt/parakeet-redux/coreml/export_encoder_fp16.py --name ultra, iOS 18 target), and the published
FluidInference/parakeet-ultra-coreml folder for the other components. Output: one folder per variant under
--out, each a drop-in FluidAudio `.ultra` model folder (Encoder.mlmodelc replaced) plus variant.json.

Weights stay CC BY 4.0 (moondream/parakeet-ultra, from NVIDIA parakeet-tdt-0.6b-v3); attribution travels with
every variant (NOTICE.txt). Run inside the mobius v3 env (coremltools 9.0b1).
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

NOTICE = ("Parakeet Ultra weights: moondream/parakeet-ultra (CC BY 4.0), a post-training of NVIDIA "
          "parakeet-tdt-0.6b-v3 (CC BY 4.0). Core ML build: FluidInference/parakeet-ultra-coreml. Compressed for "
          "Seal Speak's size test; changes: encoder weight compression only.\n")

def _pal(nbits: int, workers: int):
    import coremltools.optimize.coreml as cto

    return cto.OpPalettizerConfig(mode="kmeans", nbits=nbits, granularity="per_grouped_channel", group_size=16,
                                  num_kmeans_workers=workers, weight_threshold=2048)


# name: description. Uniform builds take their width from edacc_eval.lowbit.UNIFORM_BITS; the mixed one is per weight.
VARIANTS = {
    "ultra-pal6": "6-bit k-means palettization, per grouped channel (group 16), data-free",
    "ultra-pal4": "4-bit k-means palettization, per grouped channel (group 16), data-free",
    "ultra-pal3": "3-bit k-means palettization, per grouped channel (group 16), data-free",
    "ultra-pal2": "2-bit k-means palettization, per grouped channel (group 16), data-free",
    "ultra-mixed246": ("mixed k-means palettization, per grouped channel (group 16), data-free: front end and first and "
                       "last conformer blocks 6-bit, attention 4-bit, middle feed-forward and convolution 2-bit"),
}


def _config(name: str, model, workers: int):
    """(OptimizationConfig, average bits) for one variant."""
    import coremltools.optimize.coreml as cto
    from edacc_eval.lowbit import MIXED_NAME, UNIFORM_BITS, average_bits, mixed_plan

    if name in UNIFORM_BITS:
        return cto.OptimizationConfig(global_config=_pal(UNIFORM_BITS[name], workers)), float(UNIFORM_BITS[name])
    assert name == MIXED_NAME, name
    meta = cto.get_weights_metadata(model, weight_threshold=2048)
    plan = mixed_plan(list(meta))
    avg = average_bits(plan, {n: int(m.val.size) for n, m in meta.items()})
    print(f"{name}: {len(plan)} weights, " + ", ".join(f"{b}-bit {sum(v == b for v in plan.values())}"
                                                       for b in (6, 4, 2)) + f", average {avg:.2f} bits", flush=True)
    return cto.OptimizationConfig(op_name_configs={n: _pal(b, workers) for n, b in plan.items()}), avg


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("fp16", type=Path)
    ap.add_argument("--base", type=Path, required=True, help="published parakeet-ultra-coreml folder")
    ap.add_argument("--out", type=Path, required=True, help="models/variants directory")
    ap.add_argument("--variants", default="ultra-pal6,ultra-pal4")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--sizes", type=Path, required=True, help="sizes.json to upsert")
    a = ap.parse_args()
    import coremltools as ct
    import coremltools.optimize.coreml as cto

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from edacc_eval.sizes import record

    record(a.sizes, "ultra-fp16-encoder-only", a.fp16, f"fp16 encoder as exported (iOS 18 target), not run; "
           f"coremltools {ct.__version__}", "CC BY 4.0")
    model = ct.models.MLModel(str(a.fp16), skip_model_load=True)
    for name in a.variants.split(","):
        desc = VARIANTS[name]
        dst = a.out / name
        if (dst / "variant.json").exists():
            print(f"{name}: already built"); continue
        t0 = time.time()
        config, avg = _config(name, model, a.workers)
        q = cto.palettize_weights(model, config=config)
        pkg = a.out / f"{name}-encoder.mlpackage"
        q.save(str(pkg))
        compiled = Path(ct.utils.compile_model(str(pkg)))
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(a.base, dst, ignore=shutil.ignore_patterns("Encoder.mlmodelc", ".cache", "*.mlpackage"))
        shutil.move(str(compiled), str(dst / "Encoder.mlmodelc"))
        shutil.rmtree(pkg)
        (dst / "NOTICE.txt").write_text(NOTICE)
        method = f"{desc}; {avg:.2f} bits per encoder weight on average; coremltools {ct.__version__}; encoder only, other components as published"
        (dst / "variant.json").write_text(json.dumps({"asr_version": "ultra", "method": method}, indent=2) + "\n")
        row = record(a.sizes, name, dst, method, "CC BY 4.0 (attribution in NOTICE.txt)",
                     encoder=dst / "Encoder.mlmodelc")
        print(f"{name}: {time.time() - t0:.0f}s, {row['disk_bytes'] / 1e6:.0f} MB on disk, "
              f"{row['zipped_bytes'] / 1e6:.0f} MB zipped", flush=True)


if __name__ == "__main__":
    main()
