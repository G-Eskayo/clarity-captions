#!/usr/bin/env python3
"""Calibrated low-bit Parakeet Ultra (#272 "Parakeet Ultra smaller with no loss"), steps 1-3.

Runs inside the mobius v3 env (torch 2.7, NeMo 2.3, coremltools 9.0b1). Every step reads calibration audio only
from the held-out EdAcc calibration split (`edacc_eval.heldout`, recorded in docs/perf/edacc-heldout-split.json);
nothing here ever sees a scored clip.

  prep         nvidia v3 .nemo + moondream/parakeet-ultra weights -> one ultra.nemo; the downloads are deleted
  sensitivity  step 1: per-module error when that module alone drops from 6 to 4 (and 3) bits, everything else at
               6; encoder-output error and greedy WER on the calibration slice
  build        step 2: a bit plan (uniform or from sensitivity), data-free k-means or calibrated sensitive k-means
               (coremltools SKMPalettizer, Fisher-weighted with the TDT loss on calibration clips), exported to an
               fp16 Core ML encoder and packed exactly with palettize mode "unique"; a drop-in FluidAudio folder
  decoder      step 3: decoder + joint re-exported from the same weights, palettized, swapped into a build folder

Palettization matches the shipped builds: per grouped channel, 16 output channels per lookup table, weights with
2,048+ elements only (compress_parakeet.py).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

GROUP = 16
MIN_ELEMENTS = 2048


# ---------------------------------------------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------------------------------------------

def mobius_paths(convert: Path) -> tuple[Path, Path]:
    m = convert / "mobius" / "models" / "stt"
    return m / "parakeet-redux" / "coreml", m / "parakeet-tdt-v3-0.6b" / "coreml"


def load_ultra(nemo: Path):
    import nemo.collections.asr as nemo_asr
    import torch

    model = nemo_asr.models.EncDecRNNTBPEModel.restore_from(str(nemo), map_location="cpu")
    model.eval()
    torch.set_grad_enabled(False)
    return model


def cmd_prep(a) -> None:
    out = a.out
    if out.exists():
        print(f"{out} exists"); return
    redux, v3 = mobius_paths(a.convert)
    sys.path[:0] = [str(v3), str(redux)]
    os.environ.setdefault("HF_HOME", str(a.convert / "cache" / "hf"))
    import nemo.collections.asr as nemo_asr
    from redux_weights import load_into_nemo

    model = nemo_asr.models.EncDecRNNTBPEModel.from_pretrained("nvidia/parakeet-tdt-0.6b-v3", map_location="cpu")
    model.eval()
    load_into_nemo(model, a.hf_dir)
    tmp = out.with_suffix(".tmp.nemo")
    model.save_to(str(tmp))
    tmp.rename(out)
    print(f"saved {out} ({out.stat().st_size / 1e9:.2f} GB)")
    if a.drop_downloads:
        shutil.rmtree(a.convert / "cache" / "hf", ignore_errors=True)
        shutil.rmtree(a.hf_dir, ignore_errors=True)
        print("deleted the v3 download and the Ultra weights; ultra.nemo holds both")


# ---------------------------------------------------------------------------------------------------------------
# Weights: which encoder weights get palettized, and their k-means reconstructions
# ---------------------------------------------------------------------------------------------------------------

def palettizable(model) -> dict[str, "torch.nn.Module"]:
    """Encoder Linear/Conv modules whose weight Core ML would palettize (>= 2,048 elements)."""
    import torch

    out = {}
    for name, mod in model.encoder.named_modules():
        if isinstance(mod, (torch.nn.Linear, torch.nn.Conv1d, torch.nn.Conv2d)) and mod.weight.numel() >= MIN_ELEMENTS:
            out[f"encoder.{name}"] = mod
    return out


def _weighted_quantiles(sv, sw, qs):
    """Rows of sorted values sv with per-value weights sw: the values at cumulative-weight fractions qs."""
    import torch

    cw = torch.cumsum(sw, dim=1)
    cw = cw / cw[:, -1:]
    pos = torch.searchsorted(cw.contiguous(), qs.expand(sv.shape[0], -1).contiguous()).clamp_(max=sv.shape[1] - 1)
    return torch.gather(sv, 1, pos)


def kmeans_codes(w, nbits: int, group: int = GROUP, iters: int = 150, importance=None):
    """Per-grouped-channel 1-D k-means (weighted when importance is given): (lut [G, 2**nbits], idx uint8 [G, n]).

    w: [out, ...]. Each run of `group` output channels shares one table (the last group is padded by repeating the
    last row, then cut on decode). Lloyd's iterations, vectorised over groups, nearest centroid by searchsorted on
    sorted midpoints: O(iters * numel * log k). Two starts, the better kept per group (weighted squared error):
      - quantiles of the importance-weighted distribution (heavy weights start with their own centroid);
      - Panter-Dite companding: centroid density ~ (importance * p)^(1/3), the high-resolution optimum, which puts
        enough centroids in heavy tails (plain quantiles left 6-bit at 3.4x coremltools' error; tested);
      - an even grid from min to max (outlier-heavy groups).
    """
    import torch

    out = w.shape[0]
    flat = w.reshape(out, -1).float()
    k = 1 << nbits
    n_groups = math.ceil(out / group)
    pad = n_groups * group - out
    if pad:
        flat = torch.cat([flat, flat[-1:].expand(pad, -1)])
    g = flat.reshape(n_groups, -1).contiguous()
    wt = torch.ones_like(g)
    if importance is not None:
        ii = importance.reshape(out, -1).float().to(w.device)
        if pad:
            ii = torch.cat([ii, ii[-1:].expand(pad, -1)])
        wt = ii.reshape(n_groups, -1).clamp_min(1e-12).contiguous()
    n = g.shape[1]
    qs = torch.linspace(0, 1, k + 2, device=w.device)[1:-1]
    sv, order = torch.sort(g, dim=1)
    sw = torch.gather(wt, 1, order)
    del order
    starts = [_weighted_quantiles(sv, sw, qs)]
    m = max(1, n // (4 * k))                                    # local density from spacing over 2m neighbours
    lo = torch.cat([sv[:, :1].expand(-1, m), sv[:, :-m]], dim=1)
    hi = torch.cat([sv[:, m:], sv[:, -1:].expand(-1, m)], dim=1)
    span = (hi - lo).clamp_min(1e-12)
    dens = 1.0 / span                                           # ~ p, up to a per-row constant
    comp = (sw * dens).pow(1 / 3) / dens                        # sample weight giving centroid density (w p)^(1/3)
    starts.append(_weighted_quantiles(sv, comp, qs))
    starts.append(sv[:, :1] + (sv[:, -1:] - sv[:, :1]) * qs[None, :])   # even grid, min to max
    del sv, sw, lo, hi, span, dens, comp

    def assign(c):
        c, _ = torch.sort(c, dim=1)
        mid = ((c[:, 1:] + c[:, :-1]) / 2).contiguous()
        return c, torch.searchsorted(mid, g)

    best_c = best_idx = best_err = None
    scale = g.abs().amax(1, keepdim=True).clamp_min(1e-12)
    gw = g * wt
    for c in starts:
        for it in range(iters):
            c, idx = assign(c)
            num = torch.zeros_like(c).scatter_add_(1, idx, gw)
            den = torch.zeros_like(c).scatter_add_(1, idx, wt)
            new = torch.where(den > 0, num / den.clamp_min(1e-30), c)
            if it % 10 == 9 and float(((new - c).abs() / scale).max()) < 1e-6:   # converged in every group
                c = new
                break
            c = new
        c, idx = assign(c)
        err = (wt * (torch.gather(c, 1, idx) - g) ** 2).sum(1)
        if best_err is None:
            best_c, best_idx, best_err = c, idx, err
        else:
            better = err < best_err
            best_c = torch.where(better[:, None], c, best_c)
            best_idx = torch.where(better[:, None], idx, best_idx)
            best_err = torch.minimum(err, best_err)
    return best_c, best_idx.to(torch.uint8)


def decode_codes(lut, idx, shape, group: int = GROUP):
    """Inverse of kmeans_codes: [G, n] table lookups back to the weight's shape (padding rows dropped)."""
    import torch

    rec = torch.gather(lut, 1, idx.long())                     # [G, group * in]
    return rec.reshape(lut.shape[0] * group, -1)[: shape[0]].reshape(shape)


def _sk_group(args):
    """One 16-channel group, clustered exactly as coremltools does it: on fp16 groups of 10,000+ weights the optimal
    1-D k-means (kmeans1d, over unique values weighted by their counts), otherwise sklearn k-means++ (tol 1e-2, one
    init, seed 0). With importance, the unique values are weighted by their summed importance instead: exact weighted
    k-means (coremltools' SKMPalettizer objective). Measured 2026-11-09: copying only the sklearn branch scored 0.53
    points worse than ultra-pal4 on shard 1, because coremltools takes the kmeans1d branch for these weights."""
    import numpy as np
    from coremltools.models.neural_network import quantization_utils as qu

    vals, wts, k = args
    if vals.dtype == np.float16 and vals.size >= 10_000 and qu._HAS_KMEANS1D:
        uniq, inv, counts = np.unique(vals, return_inverse=True, return_counts=True)
        inv = inv.reshape(-1)
        w = counts.astype(np.float64) if wts is None else np.bincount(inv, weights=wts, minlength=len(uniq))
        n = min(len(uniq), k)
        res = qu._kmeans1d.cluster(uniq, n, weights=w)
        lut = np.zeros(k, dtype=np.float32)
        lut[:n] = res.centroids
        return lut, np.asarray(res.clusters, dtype=np.uint8)[inv]
    from sklearn.cluster import KMeans

    x = vals.reshape(-1, 1)
    n = min(len(x), k)
    km = KMeans(n, init="k-means++", tol=1e-2, n_init=1, random_state=0).fit(x, sample_weight=wts)
    lut = np.zeros(k, dtype=np.float32)
    lut[:n] = km.cluster_centers_[:, 0]
    return lut, km.labels_.astype(np.uint8)


_POOL = None


def kmeans_sklearn(w, nbits: int, importance=None, workers: int = 8, group: int = GROUP):
    """Reconstruction of w with per-grouped-channel k-means exactly as coremltools palettizes (sklearn, fp16 input).

    Data-free (importance None) reproduces the shipped builds' clustering; with importance it is coremltools'
    sensitive k-means (SKMPalettizer: Fisher-weighted sklearn k-means). Groups run in a process pool.
    """
    import multiprocessing as mp

    import numpy as np
    import torch

    global _POOL
    if _POOL is None:
        _POOL = mp.get_context("spawn").Pool(workers)
    shape = w.shape
    a = w.detach().cpu().numpy().astype(np.float16).reshape(shape[0], -1)   # coremltools clusters the fp16 export
    imp = None if importance is None else importance.detach().cpu().numpy().astype(np.float64).reshape(shape[0], -1)
    k = 1 << nbits
    jobs = [(a[s:s + group].reshape(-1), None if imp is None else np.maximum(imp[s:s + group].reshape(-1), 1e-30), k)
            for s in range(0, shape[0], group)]
    out = np.empty(a.shape, dtype=np.float32)
    for j, (lut, lab) in enumerate(_POOL.imap(_sk_group, jobs, chunksize=4)):
        s = j * group
        out[s:s + group] = lut[lab].reshape(-1, a.shape[1])
    return torch.from_numpy(out.reshape(shape)).to(w.dtype)


def kmeans_groups(w, nbits: int, group: int = GROUP, iters: int = 150, importance=None):
    """The k-means reconstruction of w (same shape and dtype); fast Lloyd's, used by the sensitivity sweep only."""
    lut, idx = kmeans_codes(w, nbits, group, iters, importance)
    return decode_codes(lut, idx, w.shape).to(w.dtype)


# ---------------------------------------------------------------------------------------------------------------
# Calibration audio and evaluation on it
# ---------------------------------------------------------------------------------------------------------------

def calib_clips(calib_dir: Path, limit: int | None, max_seconds: float = 20.0, min_seconds: float = 1.0) -> list[dict]:
    rows = [json.loads(l) for l in (calib_dir / "manifest.jsonl").read_text().splitlines() if l.strip()]
    rows = [r for r in rows if min_seconds <= float(r["audio_seconds"]) <= max_seconds]
    rows.sort(key=lambda r: r["clip_id"])
    if limit and len(rows) > limit:
        step = len(rows) / limit                                # even spread over speakers (manifest is grouped)
        rows = [rows[int(i * step)] for i in range(limit)]
    for r in rows:
        r["path"] = str(calib_dir / r["file"])
    return rows


def _audio(path: str):
    import soundfile as sf
    import torch

    data, sr = sf.read(path, dtype="float32")
    assert sr == 16000, (path, sr)
    if data.ndim > 1:
        data = data[:, 0]
    return torch.from_numpy(data)


class CalibSet:
    """Mel features for the calibration clips, computed once; batched by length."""

    def __init__(self, model, clips: list[dict], batch_seconds: float = 120.0):
        import torch

        self.clips = clips
        self.items = []
        for r in clips:
            x = _audio(r["path"])[None]
            n = torch.tensor([x.shape[1]])
            mel, mel_len = model.preprocessor(input_signal=x, length=n)
            self.items.append((mel, mel_len))
        order = sorted(range(len(clips)), key=lambda i: clips[i]["audio_seconds"])
        self.batches, cur, secs = [], [], 0.0
        for i in order:
            cur.append(i); secs += clips[i]["audio_seconds"]
            if secs >= batch_seconds:
                self.batches.append(cur); cur, secs = [], 0.0
        if cur:
            self.batches.append(cur)

    def batch(self, idx: list[int]):
        import torch

        mels = [self.items[i][0] for i in idx]
        T = max(m.shape[-1] for m in mels)
        mel = torch.cat([torch.nn.functional.pad(m, (0, T - m.shape[-1])) for m in mels])
        lens = torch.cat([self.items[i][1] for i in idx])
        return mel, lens


def encode_all(model, cs: CalibSet, device: str = "cpu"):
    """Encoder outputs per clip, on the CPU (MPS matches CPU to 2e-6 relative; measured)."""
    import torch

    outs = [None] * len(cs.clips)
    with torch.inference_mode():
        for b in cs.batches:
            mel, lens = cs.batch(b)
            enc, enc_len = model.encoder(audio_signal=mel.to(device), length=lens.to(device))
            enc, enc_len = enc.cpu(), enc_len.cpu()
            for j, i in enumerate(b):
                outs[i] = (enc[j:j + 1, :, :enc_len[j]].clone(), enc_len[j:j + 1].clone())
    return outs


def rel_error(ref, got) -> float:
    """Pooled relative L2 error of encoder outputs: ||got - ref|| / ||ref|| over every frame of every clip."""
    num = den = 0.0
    for (r, _), (g, _) in zip(ref, got):
        num += float(((g - r) ** 2).sum()); den += float((r ** 2).sum())
    return math.sqrt(num / den)


def greedy_wer(model, encoded, clips) -> tuple[float, int, int]:
    """Greedy TDT decode of cached encoder outputs; pooled WER with the repo's EdAcc normaliser."""
    import torch
    from edacc_eval.normalize import normalize
    from edacc_eval.wer import align_counts

    errors = words = 0
    with torch.inference_mode():
        for (enc, n), r in zip(encoded, clips):
            hyp = model.decoding.rnnt_decoder_predictions_tensor(encoder_output=enc, encoded_lengths=n)
            h = hyp[0] if isinstance(hyp, (list, tuple)) else hyp
            h = h[0] if isinstance(h, (list, tuple)) else h
            text = getattr(h, "text", h)
            c = align_counts(normalize(r["reference"]), normalize(str(text)))
            errors += c.errors; words += c.n
    return errors / max(words, 1), errors, words


# ---------------------------------------------------------------------------------------------------------------
# Step 1: layer sensitivity
# ---------------------------------------------------------------------------------------------------------------

def module_group(name: str) -> str:
    """encoder.layers.7.self_attn.linear_q -> L07.attn; encoder.pre_encode.* -> pre_encode."""
    parts = name.split(".")
    if parts[1] != "layers":
        return parts[1]
    blk, kind = int(parts[2]), parts[3]
    kind = {"self_attn": "attn", "feed_forward1": "ff1", "feed_forward2": "ff2", "conv": "conv"}.get(kind, kind)
    return f"L{blk:02d}.{kind}"


def cmd_sensitivity(a) -> None:
    """Every palettizable weight at the base width (6), then each module group alone at each probe width (4, 3).

    Encoder outputs are compared with the full-precision model's on the same clips (pooled relative L2), and the
    greedy WER on the calibration slice is recorded beside it. Clustering is the builds' own (kmeans_sklearn), kept as
    fp16 reconstructions (~1.2 GB per width). Resumable: finished rows are kept in --out.
    """
    import torch

    torch.set_num_threads(a.threads)
    dev = a.device
    model = load_ultra(a.nemo)
    mods = palettizable(model)
    clips = calib_clips(a.calib, a.clips)
    minutes = sum(c["audio_seconds"] for c in clips) / 60
    print(f"{len(mods)} palettizable encoder weights; {len(clips)} calibration clips ({minutes:.1f} min)", flush=True)
    cs = CalibSet(model, clips)
    shapes = {n: tuple(m.weight.shape) for n, m in mods.items()}

    codes: dict[int, dict] = {}
    for b in sorted({a.base_bits, *a.probe_bits}, reverse=True):
        t0 = time.time()
        codes[b] = {}
        for j, (n, m) in enumerate(mods.items()):
            codes[b][n] = kmeans_sklearn(m.weight.data, b, workers=a.workers).half()   # the builds' clustering
            if j % 50 == 49:
                print(f"  k-means {b}-bit: {j + 1}/{len(mods)} weights, {time.time() - t0:.0f}s", flush=True)
        print(f"k-means {b}-bit for every weight: {time.time() - t0:.0f}s", flush=True)
    # k-means on the CPU (many small kernels starve on a shared GPU; measured), the encoder on `dev`, the decoder
    # and joint on the CPU.
    model.encoder.to(dev)
    ref = encode_all(model, cs, dev)
    base_wer = greedy_wer(model, ref, clips)
    print(f"full-precision calibration WER {base_wer[0]:.4f}", flush=True)

    def put(n, b):
        mods[n].weight.data.copy_(codes[b][n].to(mods[n].weight.device, torch.float32))

    groups: dict[str, list[str]] = {}
    for n in mods:
        groups.setdefault(module_group(n), []).append(n)
    out = a.out
    done = json.loads(out.read_text()) if out.exists() else {}
    done.setdefault("meta", {
        "calibration_clips": len(clips), "calibration_minutes": round(minutes, 2), "base_bits": a.base_bits,
        "probe_bits": a.probe_bits, "group_size": GROUP, "full_precision_wer": base_wer[0],
        "metric": "pooled relative L2 error of encoder outputs vs full precision; greedy TDT WER beside it",
        "params": {n: int(math.prod(shapes[n])) for n in mods}, "groups": groups,
    })
    rows = done.setdefault("rows", {})

    def save():
        tmp = out.with_suffix(".tmp"); tmp.write_text(json.dumps(done, indent=1)); tmp.rename(out)

    def measure(tag: str, changes: dict[str, int]):
        if tag in rows:
            return
        for n, b in changes.items():
            put(n, b)
        got = encode_all(model, cs, dev)
        e = rel_error(ref, got)
        w = greedy_wer(model, got, clips)
        rows[tag] = {"rel_error": e, "wer": w[0], "errors": w[1], "words": w[2]}
        save()
        print(f"{tag}: rel error {e:.5f}, WER {w[0]:.4f}", flush=True)

    t0 = time.time()
    for b in a.probe_bits:                                      # whole-encoder rows first
        measure(f"all@{b}", {n: b for n in mods})
    measure(f"all@{a.base_bits}", {n: a.base_bits for n in mods})   # leaves every weight at the base width
    for n in mods:
        put(n, a.base_bits)
    for g, names in sorted(groups.items()):
        for b in a.probe_bits:
            measure(f"{g}@{b}", {n: b for n in names})
            for n in names:
                put(n, a.base_bits)
    print(f"SENSITIVITY-DONE in {time.time() - t0:.0f}s", flush=True)
    if _POOL is not None:
        _POOL.close(); _POOL.join()


# ---------------------------------------------------------------------------------------------------------------
# Step 2: builds
# ---------------------------------------------------------------------------------------------------------------

def _tdt_loss_fn(model):
    """Loss for the Fisher sensitivity: the TDT loss on a calibration clip. NeMo's fast TDT loss is CUDA-only, so
    this uses NeMo's pure-PyTorch TDTLossPytorch with the model's own durations and sigma, on raw joint logits."""
    import torch
    from nemo.collections.asr.losses.rnnt_pytorch import TDTLossPytorch

    kw = dict(model.cfg.loss.get("tdt_kwargs", {}))
    crit = TDTLossPytorch(blank=model.decoder.blank_idx, durations=list(kw.get("durations", [0, 1, 2, 3, 4])),
                          reduction="sum", sigma=float(kw.get("sigma", 0.0)))

    def loss_fn(m, batch):
        signal, sig_len, tokens, tok_len = batch
        enc, enc_len = m.forward(input_signal=signal, input_signal_length=sig_len)
        dec, tgt_len, _ = m.decoder(targets=tokens, target_length=tok_len)
        logits = m.joint.joint(enc.transpose(1, 2), dec.transpose(1, 2))      # [B, T, U+1, V+1+durations]
        # TDTLossPytorch calls .cuda() on two of its own tensors; on the CPU those calls are made no-ops for this
        # one call, leaving NeMo's recursion itself untouched.
        cuda = torch.Tensor.cuda
        torch.Tensor.cuda = lambda self, *a, **k: self
        try:
            return crit(acts=logits, labels=tokens, act_lens=enc_len, label_lens=tgt_len)
        finally:
            torch.Tensor.cuda = cuda

    return loss_fn


def fisher_importance(model, clips: list[dict], names: list[str], n: int) -> dict[str, "torch.Tensor"]:
    """Diagonal Fisher (mean squared gradient of the TDT loss) per weight, from n calibration clips, one at a time.

    The same importance coremltools' SKMPalettizer computes; done here so the Ultra TDT loss and the encoder-only
    module set are explicit and the per-weight bit plan can differ per module.
    """
    import torch

    torch.set_grad_enabled(True)
    model.train(False)
    params = dict(model.named_parameters())
    for p in model.parameters():
        p.requires_grad_(False)
    ws = [params[f"{nm}.weight"] for nm in names]
    for w in ws:
        w.requires_grad_(True)
    fisher = {nm: torch.zeros_like(w) for nm, w in zip(names, ws)}
    loss_fn = _tdt_loss_fn(model)
    tok = model.tokenizer
    from edacc_eval.normalize import normalize

    used = 0
    t_start = time.time()
    for r in clips[:n]:
        text = normalize(r["reference"])
        ids = tok.text_to_ids(text)
        if not ids:
            continue
        x = _audio(r["path"])[None]
        batch = (x, torch.tensor([x.shape[1]]), torch.tensor([ids]), torch.tensor([len(ids)]))
        for w in ws:
            w.grad = None
        loss = loss_fn(model, batch)
        loss.backward()
        for nm, w in zip(names, ws):
            fisher[nm] += w.grad.detach() ** 2
        used += 1
        if used % 4 == 0:
            print(f"  fisher {used}/{n}, {time.time() - t_start:.0f}s", flush=True)
    for w in ws:
        w.requires_grad_(False)
    torch.set_grad_enabled(False)
    return {k: v / max(used, 1) for k, v in fisher.items()}


def _export_fp16(model, convert: Path, work: Path):
    """The mobius fp16 encoder export (export_encoder_fp16.py) on an in-memory model."""
    import coremltools as ct
    import numpy as np
    import torch

    redux, v3 = mobius_paths(convert)
    sys.path[:0] = [str(v3), str(redux)]
    import soundfile as sf
    from individual_components import EncoderWrapper, ExportSettings, PreprocessorWrapper, _coreml_convert

    sr = 16000
    max_samples = 15 * sr
    data, _ = sf.read(str(v3 / "audio" / "yc_first_minute_16k_15s.wav"), dtype="float32")
    data = np.pad(data, (0, max(0, max_samples - data.size)))[:max_samples]
    audio = torch.from_numpy(data)[None]
    audio_len = torch.tensor([max_samples], dtype=torch.int32)
    pre = PreprocessorWrapper(model.preprocessor.eval())
    enc = EncoderWrapper(model.encoder.eval())
    with torch.inference_mode():
        mel, mel_len = pre(audio, audio_len)
        mel_len = mel_len.to(torch.int32)
    mel, mel_len = mel.clone(), mel_len.clone()
    traced = torch.jit.trace(enc, (mel, mel_len), strict=False).eval()
    settings = ExportSettings(output_dir=work, compute_units=ct.ComputeUnit.CPU_ONLY, deployment_target=ct.target.iOS18,
                              compute_precision=None, max_audio_seconds=15.0, max_symbol_steps=1)
    return _coreml_convert(
        traced,
        [ct.TensorType(name="mel", shape=tuple(mel.shape), dtype=np.float32),
         ct.TensorType(name="mel_length", shape=(1,), dtype=np.int32)],
        [ct.TensorType(name="encoder", dtype=np.float32), ct.TensorType(name="encoder_length", dtype=np.int32)],
        settings,
    )


NOTICE = ("Parakeet Ultra weights: moondream/parakeet-ultra (CC BY 4.0), a post-training of NVIDIA "
          "parakeet-tdt-0.6b-v3 (CC BY 4.0). Core ML build: FluidInference/parakeet-ultra-coreml. Compressed for "
          "Seal Speak's size test (#272); changes: weight compression only.\n")


OURS_MAX_BITS = 4   # our k-means matches coremltools' at 3-4 bits (tests); wider weights use coremltools' own


def split_plan(plan: dict[str, int]) -> tuple[dict[str, int], dict[str, int]]:
    """(weights we quantise in torch, calibrated or not; weights coremltools palettizes from the fp16 export)."""
    # Weights the converter folds (depthwise conv + batch norm; linear_pos into the position term) are left at full
    # precision in torch and quantised once, by coremltools, after folding; quantising them in torch as well
    # quantised them twice (measured: 0.4 points worse than ultra-pal4 on shard 1).
    ours = {n: b for n, b in plan.items() if b <= OURS_MAX_BITS and not n.endswith(FOLDED_IN_EXPORT)}
    return ours, {n: b for n, b in plan.items() if n not in ours}


CT_WORKERS = 1   # a forked pool deadlocked on Kali (8 workers asleep at 0% CPU, 2026-11-09); #150 also used 1
FOLDED_IN_EXPORT = (".conv.depthwise_conv", ".self_attn.linear_pos")


def weight_key(arr) -> tuple:
    """(shape, sha1 of the fp16 bytes): identifies a weight in the Core ML export by content, since the exporter's
    const names are not stable (a modified model exported as const_248_to_fp16, not layers_0_..._weight)."""
    import hashlib
    import numpy as np

    a = np.ascontiguousarray(np.asarray(arr, dtype=np.float16))
    return tuple(a.shape), hashlib.sha1(a.tobytes()).hexdigest()


def torch_keys(mods: dict) -> dict:
    """weight_key -> torch module name, from the weights as they are now (call just before export)."""
    keys = {}
    for n, m in mods.items():
        k = weight_key(m.weight.detach().cpu().numpy())
        if k in keys:
            raise ValueError(f"{n} and {keys[k]} hold identical weights; cannot map the export by content")
        keys[k] = n
    return keys


def _pack(mlmodel, plan: dict[str, int], keys: dict):
    """Low-bit weights already hold <= 2**b values per 16-channel group: 'unique' packs them exactly. Wider ones get
    coremltools' data-free k-means, the same as the shipping 6-bit build. Every export weight must map to a planned
    torch weight and back, or nothing is built."""
    import coremltools.optimize.coreml as cto

    meta = cto.get_weights_metadata(mlmodel, weight_threshold=MIN_ELEMENTS)
    ours, theirs = split_plan(plan)
    cfg, seen, unmatched = {}, set(), []
    for const, m in meta.items():
        n = keys.get(weight_key(m.val))
        if n is None:
            unmatched.append(f"{const} {tuple(m.val.shape)}"); continue
        seen.add(n)
        if n in ours:
            cfg[const] = cto.OpPalettizerConfig(mode="unique", granularity="per_grouped_channel", group_size=GROUP,
                                                weight_threshold=MIN_ELEMENTS)
        else:
            cfg[const] = cto.OpPalettizerConfig(mode="kmeans", nbits=theirs[n], granularity="per_grouped_channel",
                                                group_size=GROUP, num_kmeans_workers=CT_WORKERS, weight_threshold=MIN_ELEMENTS)
    missing = sorted(set(plan) - seen)
    bad = [n for n in missing if not n.endswith(FOLDED_IN_EXPORT)]
    if bad:
        raise KeyError(f"plan/export mismatch: {len(bad)} planned weights not found in the export and not a kind the "
                       f"converter is known to fold (e.g. {bad[:2]}); {len(unmatched)} unmatched export consts")
    # Folded weights (depthwise conv with batch norm fused in; linear_pos folded into the position term) and the
    # non-weight consts the shipped builds palettize too (biases, position tables): coremltools' k-means at the
    # plan's widest width, as the shipped uniform builds do.
    wide = max(plan.values())
    for const, m in meta.items():
        if const not in cfg:
            cfg[const] = cto.OpPalettizerConfig(mode="kmeans", nbits=wide, granularity="per_grouped_channel",
                                                group_size=GROUP, num_kmeans_workers=CT_WORKERS, weight_threshold=MIN_ELEMENTS)
    print(f"mapped {len(seen)} of {len(plan)} planned weights by content ({len(set(ours) & seen)} packed as-is); "
          f"{len(missing)} folded by the converter and {len(unmatched)} unmatched consts in all go to "
          f"coremltools k-means at {wide} bits", flush=True)
    return cto.palettize_weights(mlmodel, config=cto.OptimizationConfig(op_name_configs=cfg))


def cmd_build(a) -> None:
    import coremltools as ct
    import torch
    from edacc_eval.lowbit import plan_from_sensitivity

    torch.set_num_threads(a.threads)
    dst = a.out / a.name
    if (dst / "variant.json").exists():
        print(f"{a.name}: already built"); return
    model = load_ultra(a.nemo)
    mods = palettizable(model)
    sizes = {n: int(m.weight.numel()) for n, m in mods.items()}
    if a.bits:
        plan = {n: a.bits for n in mods}
        plan_desc = f"{a.bits}-bit everywhere"
    else:
        sens = json.loads(a.sensitivity.read_text())
        plan, plan_desc = plan_from_sensitivity(sens, sizes, a.target_bits, low=a.low, high=a.high)
    avg = sum(plan[n] * sizes[n] for n in plan) / sum(sizes.values())
    print(f"{a.name}: {plan_desc}; {avg:.2f} bits per encoder weight", flush=True)

    imp = {}
    if a.calibrated:
        names = list(split_plan(plan)[0])
        cache = a.fisher_cache
        if cache.exists():
            saved = torch.load(cache)
            if saved.get("dtype") != "bfloat16":   # an fp16 cache lost 98% of the values to underflow (2026-11-09)
                raise ValueError(f"{cache} is not a bfloat16 cache; delete it to recompute")
            if (saved["clips"], saved.get("max_seconds")) != (a.fisher_clips, a.fisher_max_seconds) \
                    or not set(names) <= set(saved["imp"]):
                raise ValueError(f"{cache} was made with other settings; delete it to recompute")
            imp = {n: saved["imp"][n].float() for n in names}
            print(f"Fisher importance from {cache} ({a.fisher_clips} calibration clips)", flush=True)
        else:
            clips = calib_clips(a.calib, a.fisher_clips, max_seconds=a.fisher_max_seconds)   # cost ~ length squared
            t0 = time.time()
            all_names = list(split_plan({n: 1 for n in mods})[0])            # every weight we may quantise
            full = fisher_importance(model, clips, all_names, a.fisher_clips)
            tmp = cache.with_suffix(".tmp")
            torch.save({"clips": a.fisher_clips, "max_seconds": a.fisher_max_seconds, "dtype": "bfloat16", "imp": {n: v.to(torch.bfloat16) for n, v in full.items()}}, tmp)
            tmp.rename(cache)
            imp = {n: full[n] for n in names}
            del full
            print(f"Fisher importance from {a.fisher_clips} calibration clips: {time.time() - t0:.0f}s, cached", flush=True)
    t0 = time.time()
    if a.coreml_only:                                           # control: every weight quantised by coremltools itself
        global OURS_MAX_BITS
        OURS_MAX_BITS = 0
    ours, _ = split_plan(plan)
    for n in ours:
        w = mods[n].weight.data
        q = kmeans_sklearn(w, plan[n], importance=imp.get(n), workers=a.workers)
        if not torch.isfinite(q).all():
            raise ValueError(f"{n}: k-means produced non-finite weights")
        mods[n].weight.data.copy_(q)
    print(f"k-means: {time.time() - t0:.0f}s", flush=True)
    imp.clear()
    if a.check_calib:
        clips = calib_clips(a.calib, a.check_calib)
        cs = CalibSet(model, clips)
        w = greedy_wer(model, encode_all(model, cs), clips)
        print(f"{a.name}: calibration-slice WER {w[0]:.4f} (torch, before export)", flush=True)

    work = a.work / a.name
    work.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    keys = torch_keys(mods)
    ml = _export_fp16(model, a.convert, work)
    del model, mods
    q = _pack(ml, plan, keys)
    del ml
    pkg = work / "Encoder.mlpackage"
    q.save(str(pkg))
    del q
    how = ("calibrated sensitive k-means (exact 1-D k-means weighted by Fisher importance from the TDT loss, "
           f"{a.fisher_clips} held-out calibration clips of 1-{a.fisher_max_seconds:g} s)" if a.calibrated else "k-means, data-free")
    method = (f"{plan_desc}; {how}; per grouped channel (group {GROUP}); {avg:.2f} bits per encoder weight on average "
              f"(converter-folded weights at {max(plan.values())} bits); coremltools {ct.__version__}; encoder only, "
              "other components as published")
    meta = {"asr_version": "ultra", "method": method, "plan": plan}
    if a.no_compile:                                            # Linux: hand the package to a Mac to compile
        a.out.mkdir(parents=True, exist_ok=True)
        staged = a.out / f"{a.name}.Encoder.mlpackage"
        if staged.exists():
            shutil.rmtree(staged)
        shutil.move(str(pkg), str(staged))
        (a.out / f"{a.name}.variant.json").write_text(json.dumps(meta, indent=2) + "\n")
        shutil.rmtree(work)
        print(f"{a.name}: packed, {time.time() - t0:.0f}s; staged {staged} for assemble on a Mac", flush=True)
        if _POOL is not None:
            _POOL.close(); _POOL.join()
        return
    compiled = Path(ct.utils.compile_model(str(pkg)))
    print(f"export + pack + compile: {time.time() - t0:.0f}s", flush=True)
    _assemble(a.base, dst, compiled, meta)
    shutil.rmtree(work)
    print(f"{a.name}: built, {method}", flush=True)
    if _POOL is not None:
        _POOL.close(); _POOL.join()


def _assemble(base: Path, dst: Path, compiled: Path, meta: dict) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(base, dst, ignore=shutil.ignore_patterns("Encoder.mlmodelc", ".cache", "*.mlpackage"))
    shutil.move(str(compiled), str(dst / "Encoder.mlmodelc"))
    (dst / "NOTICE.txt").write_text(NOTICE)
    (dst / "variant.json").write_text(json.dumps(meta, indent=2) + "\n")


def cmd_fisher(a) -> None:
    """Fisher importance only, cached for builds elsewhere. On the 2012 mini this step ran at over 2.5 minutes a clip
    (memory-bound beside other jobs); on the M4 about 37 s a 15 s clip, so the M4 does this one step and the 2012
    mini does everything else with the cache."""
    import torch

    torch.set_num_threads(a.threads)
    if a.fisher_cache.exists():
        print(f"{a.fisher_cache} exists"); return
    model = load_ultra(a.nemo)
    mods = palettizable(model)
    clips = calib_clips(a.calib, a.fisher_clips, max_seconds=a.fisher_max_seconds)
    t0 = time.time()
    names = list(split_plan({n: 1 for n in mods})[0])
    full = fisher_importance(model, clips, names, a.fisher_clips)
    tmp = a.fisher_cache.with_suffix(".tmp")
    torch.save({"clips": a.fisher_clips, "max_seconds": a.fisher_max_seconds,
                "dtype": "bfloat16", "imp": {n: v.to(torch.bfloat16) for n, v in full.items()}}, tmp)
    tmp.rename(a.fisher_cache)
    print(f"FISHER-DONE: {len(clips)} clips, {time.time() - t0:.0f}s, {a.fisher_cache}", flush=True)


def cmd_assemble(a) -> None:
    """Mac side of a Linux build: compile <name>.Encoder.mlpackage and make the drop-in FluidAudio folder."""
    import coremltools as ct

    staged = a.staged / f"{a.name}.Encoder.mlpackage"
    meta = json.loads((a.staged / f"{a.name}.variant.json").read_text())
    compiled = Path(ct.utils.compile_model(str(staged)))
    _assemble(a.base, a.out / a.name, compiled, meta)
    shutil.rmtree(staged)
    (a.staged / f"{a.name}.variant.json").unlink()
    print(f"{a.name}: assembled in {a.out / a.name}", flush=True)


# ---------------------------------------------------------------------------------------------------------------
# Step 3: decoder and joint
# ---------------------------------------------------------------------------------------------------------------

def cmd_decoder_src(a) -> None:
    """Decoder.mlpackage and JointDecisionv3.mlpackage from ultra.nemo, by mobius's own export_decoder_joint.py (so the
    I/O contract is FluidAudio's), with its loader pointed at ultra.nemo instead of a v3 download + HF weights."""
    redux, v3 = mobius_paths(a.convert)
    sys.path[:0] = [str(v3), str(redux)]
    import nemo.collections.asr as nemo_asr
    import export_decoder_joint as edj

    if (a.out / "JointDecisionv3.mlpackage").exists():
        print(f"{a.out}: already exported"); return
    nemo_path = a.nemo
    nemo_asr.models.EncDecRNNTBPEModel.from_pretrained = classmethod(
        lambda cls, *_, **__: nemo_asr.models.EncDecRNNTBPEModel.restore_from(str(nemo_path), map_location="cpu"))
    edj.load_into_nemo = lambda model, hf_dir: None             # ultra.nemo already holds the Ultra weights
    sys.argv = ["export_decoder_joint.py", "--out", str(a.out), "--name", "ultra"]
    edj.main()


def cmd_decoder(a) -> None:
    """Palettize the published Decoder and JointDecision .mlpackage sources, swap them into a copy of a build."""
    import coremltools as ct
    import coremltools.optimize.coreml as cto

    src = a.src
    dst = a.out / a.name
    if (dst / "variant.json").exists():
        print(f"{a.name}: already built"); return
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(a.from_build, dst)
    cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(
        mode="kmeans", nbits=a.bits, granularity="per_grouped_channel", group_size=GROUP, weight_threshold=MIN_ELEMENTS,
        num_kmeans_workers=1)) if a.bits else None
    a.work.mkdir(parents=True, exist_ok=True)
    for comp in a.components.split(","):
        pkg = src / f"{comp}.mlpackage"
        m = ct.models.MLModel(str(pkg), skip_model_load=True)
        q = cto.palettize_weights(m, config=cfg) if a.bits else m
        tmp = a.work / f"{a.name}-{comp}.mlpackage"
        q.save(str(tmp))
        compiled = Path(ct.utils.compile_model(str(tmp)))
        shutil.rmtree(dst / f"{comp}.mlmodelc")
        shutil.move(str(compiled), str(dst / f"{comp}.mlmodelc"))
        shutil.rmtree(tmp)
        print(f"{a.name}: {comp} {'palettized to %d bits' % a.bits if a.bits else 're-exported, fp16'}", flush=True)
    v = json.loads((a.from_build / "variant.json").read_text())
    v["method"] = v["method"].replace("encoder only, other components as published",
                                      f"encoder as {a.from_build.name}; {a.components.replace(',', ' and ')} " + (
                                          f"{a.bits}-bit k-means per grouped channel (group {GROUP}), data-free"
                                          if a.bits else "re-exported from the same weights, fp16 (check build)"))
    v.pop("plan", None)
    (dst / "variant.json").write_text(json.dumps(v, indent=2) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    home = Path.home() / "edacc-eval"
    p = sub.add_parser("prep")
    p.add_argument("--convert", type=Path, default=home / "convert")
    p.add_argument("--hf-dir", type=Path, default=home / "convert" / "work" / "hf")
    p.add_argument("--out", type=Path, default=home / "convert" / "ultra.nemo")
    p.add_argument("--drop-downloads", action="store_true")
    for name in ("sensitivity", "build"):
        s = sub.add_parser(name)
        s.add_argument("--nemo", type=Path, default=home / "convert" / "ultra.nemo")
        s.add_argument("--calib", type=Path, default=home / "calib-272")
        s.add_argument("--threads", type=int, default=8)
        s.add_argument("--device", default="mps", choices=["mps", "cpu"])
        if name == "sensitivity":
            s.add_argument("--clips", type=int, default=240)
            s.add_argument("--base-bits", type=int, default=6)
            s.add_argument("--probe-bits", type=lambda x: [int(v) for v in x.split(",")], default=[4])
            s.add_argument("--out", type=Path, required=True)
            s.add_argument("--workers", type=int, default=8)
        else:
            s.add_argument("--name", required=True)
            s.add_argument("--bits", type=int, help="uniform width; else a plan from --sensitivity")
            s.add_argument("--sensitivity", type=Path)
            s.add_argument("--target-bits", type=float, default=4.75)
            s.add_argument("--low", type=int, default=4)
            s.add_argument("--high", type=int, default=6)
            s.add_argument("--calibrated", action="store_true")
            s.add_argument("--workers", type=int, default=8)
            s.add_argument("--coreml-only", action="store_true", help="control: no torch-side quantisation")
            s.add_argument("--no-compile", action="store_true", help="stop at the packed .mlpackage (Linux)")
            s.add_argument("--fisher-clips", type=int, default=128)
            s.add_argument("--fisher-max-seconds", type=float, default=6.0)
            s.add_argument("--fisher-cache", type=Path, default=home / "convert" / "fisher-272.pt")
            s.add_argument("--check-calib", type=int, default=240)
            s.add_argument("--convert", type=Path, default=home / "convert")
            s.add_argument("--work", type=Path, default=home / "convert" / "work-272")
            s.add_argument("--base", type=Path, default=home / "models" / "fluidaudio" / "parakeet-ultra")
            s.add_argument("--out", type=Path, default=home / "models" / "variants")
    d = sub.add_parser("decoder")
    d.add_argument("--name", required=True)
    d.add_argument("--from-build", type=Path, required=True)
    d.add_argument("--src", type=Path, required=True, help="folder with Decoder.mlpackage and JointDecision.mlpackage")
    d.add_argument("--components", default="Decoder,JointDecisionv3")
    d.add_argument("--bits", type=int, default=6, help="0 = no palettization (re-export check)")
    d.add_argument("--work", type=Path, default=home / "convert" / "work-272")
    d.add_argument("--out", type=Path, default=home / "models" / "variants")
    fi = sub.add_parser("fisher")
    fi.add_argument("--nemo", type=Path, default=home / "convert" / "ultra.nemo")
    fi.add_argument("--calib", type=Path, default=home / "calib-272")
    fi.add_argument("--fisher-clips", type=int, default=96)
    fi.add_argument("--fisher-max-seconds", type=float, default=6.0)
    fi.add_argument("--fisher-cache", type=Path, default=home / "convert" / "fisher-272.pt")
    fi.add_argument("--threads", type=int, default=8)
    asm = sub.add_parser("assemble")
    asm.add_argument("--name", required=True)
    asm.add_argument("--staged", type=Path, default=home / "staged-272")
    asm.add_argument("--base", type=Path, default=home / "models" / "fluidaudio" / "parakeet-ultra")
    asm.add_argument("--out", type=Path, default=home / "models" / "variants")
    ds = sub.add_parser("decoder-src")
    ds.add_argument("--nemo", type=Path, default=home / "convert" / "ultra.nemo")
    ds.add_argument("--convert", type=Path, default=home / "convert")
    ds.add_argument("--out", type=Path, default=home / "convert" / "work-272" / "decoder-src")
    a = ap.parse_args()
    {"fisher": cmd_fisher, "assemble": cmd_assemble, "decoder-src": cmd_decoder_src, "prep": cmd_prep, "sensitivity": cmd_sensitivity, "build": cmd_build, "decoder": cmd_decoder}[a.cmd](a)


if __name__ == "__main__":
    main()
