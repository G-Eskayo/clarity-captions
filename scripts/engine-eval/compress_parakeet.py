#!/usr/bin/env python3
"""Compressed Parakeet Ultra encoders for the size test (#150 "[E] Switch captions to Parakeet Ultra").

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

import coremltools as ct
import coremltools.optimize.coreml as cto

NOTICE = ("Parakeet Ultra weights: moondream/parakeet-ultra (CC BY 4.0), a post-training of NVIDIA "
          "parakeet-tdt-0.6b-v3 (CC BY 4.0). Core ML build: FluidInference/parakeet-ultra-coreml. Compressed for "
          "Seal Speak's size test; changes: encoder weight compression only.\n")

VARIANTS = {
    # name: (description, config factory)
    "ultra-pal6": ("6-bit k-means palettization, per grouped channel (group 16), data-free",
                   lambda w: cto.OpPalettizerConfig(mode="kmeans", nbits=6, granularity="per_grouped_channel",
                                                    group_size=16, num_kmeans_workers=w, weight_threshold=2048)),
    "ultra-pal4": ("4-bit k-means palettization, per grouped channel (group 16), data-free",
                   lambda w: cto.OpPalettizerConfig(mode="kmeans", nbits=4, granularity="per_grouped_channel",
                                                    group_size=16, num_kmeans_workers=w, weight_threshold=2048)),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("fp16", type=Path)
    ap.add_argument("--base", type=Path, required=True, help="published parakeet-ultra-coreml folder")
    ap.add_argument("--out", type=Path, required=True, help="models/variants directory")
    ap.add_argument("--variants", default="ultra-pal6,ultra-pal4")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--sizes", type=Path, required=True, help="sizes.json to upsert")
    a = ap.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from edacc_eval.sizes import record

    record(a.sizes, "ultra-fp16-encoder-only", a.fp16, f"fp16 encoder as exported (iOS 18 target), not run; "
           f"coremltools {ct.__version__}", "CC BY 4.0")
    model = ct.models.MLModel(str(a.fp16), skip_model_load=True)
    for name in a.variants.split(","):
        desc, cfg = VARIANTS[name]
        dst = a.out / name
        if (dst / "variant.json").exists():
            print(f"{name}: already built"); continue
        t0 = time.time()
        q = cto.palettize_weights(model, config=cto.OptimizationConfig(global_config=cfg(a.workers)))
        pkg = a.out / f"{name}-encoder.mlpackage"
        q.save(str(pkg))
        compiled = Path(ct.utils.compile_model(str(pkg)))
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(a.base, dst, ignore=shutil.ignore_patterns("Encoder.mlmodelc", ".cache", "*.mlpackage"))
        shutil.move(str(compiled), str(dst / "Encoder.mlmodelc"))
        shutil.rmtree(pkg)
        (dst / "NOTICE.txt").write_text(NOTICE)
        method = f"{desc}; coremltools {ct.__version__}; encoder only, other components as published"
        (dst / "variant.json").write_text(json.dumps({"asr_version": "ultra", "method": method}, indent=2) + "\n")
        row = record(a.sizes, name, dst, method, "CC BY 4.0 (attribution in NOTICE.txt)",
                     encoder=dst / "Encoder.mlmodelc")
        print(f"{name}: {time.time() - t0:.0f}s, {row['disk_bytes'] / 1e6:.0f} MB on disk, "
              f"{row['zipped_bytes'] / 1e6:.0f} MB zipped", flush=True)


if __name__ == "__main__":
    main()
