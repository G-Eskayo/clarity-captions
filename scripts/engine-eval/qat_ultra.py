#!/usr/bin/env python3
"""Step 4 of #272 "Parakeet Ultra smaller with no loss": quantisation-aware training (QAT) of Ultra's encoder.

Goal (owner, 2026-11-10): an encoder build under 400 MB with no loss against the shipped 6-bit build, judged by the
paired rule on the EdAcc held-out test split. Spend approved within $23-86 of GPU time; `--budget-hours` stops a run
before it can go over.

Data (owner: prefer CC BY so the EdAcc licence question does not come back): **LibriSpeech only** (CC BY 4.0,
openslr.org/12). train-clean-100 trains; dev-clean picks checkpoints and settings. No EdAcc audio, text or
EdAcc-derived importance goes into training or selection. EdAcc is used only to score the finished build.

Targets are the full-precision model's own transcripts of the LibriSpeech audio (`pseudo`), not LibriSpeech's
upper-case, unpunctuated text: Ultra writes punctuation and capitals, the WER normaliser hides both, so training
on LibriSpeech's own text could quietly teach the model to drop them. QAT's job is to recover the full-precision model,
not to learn LibriSpeech.

How it trains: every weight our builds quantise in torch (calibrated_ultra.split_plan, <= 4 bits, not folded by the
converter) gets a fake palette: forward uses its 16-channel group's table value for each weight. Tables start from
data-free k-means, so step 0 is the data-free build. By default the assignments stay fixed and training moves the
tables plus the parameters that stay unquantised in the export (`--free small`: biases and norms; `--free encoder`:
every other encoder parameter too, the >= 6-bit and converter-folded weights then palettized by coremltools as
before). Moving the assignments (straight-through latent weights, `--lr` > 0, reassigned every --refresh steps) is
available but made a toy layer worse at every step size tried, 2 and 4 bits, Adam and SGD (the weight oscillation
Nagel et al. 2022 describe), against a steady gain for tables alone (tests/test_qat.py). Batch norm and dropout stay
in eval mode; decoder and joint are frozen (published as they are).

  librispeech  LibriSpeech folder -> manifest.jsonl in the calibration format (calibrated_ultra.calib_clips)
  pseudo       add the full-precision model's transcript of each clip as "target"
  train        QAT; checkpoints, resumable, budget-guarded; keeps the best checkpoint by dev-clean WER
  export       best checkpoint -> qat-weights.pt (fp16 quantised weights + plan) for
               `calibrated_ultra.py build --prequantized`, which packs them exactly (palettize mode "unique")
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import calibrated_ultra as cu  # noqa: E402

LICENCE = "CC BY 4.0 (LibriSpeech, Panayotov et al. 2015, openslr.org/12)"


# ---------------------------------------------------------------------------------------------------------------
# Fake palettes
# ---------------------------------------------------------------------------------------------------------------

def _torch():
    import torch
    return torch


class FakePalette(_torch().nn.Module):
    """Parametrization: weight -> its group's table entries. 16 output channels share one table of 2**nbits values,
    as in the shipped builds. Value = table lookup; gradient flows to the table and, straight through, to the latent
    weight (so reassignment can move a weight to another entry)."""

    def __init__(self, w, nbits: int, group: int = cu.GROUP):
        torch = _torch()
        super().__init__()
        self.nbits, self.group, self.shape = nbits, group, tuple(w.shape)
        out = w.shape[0]
        lut, idx = cu.kmeans_codes(w.detach().float(), nbits, group)        # data-free start: step 0 = data-free build
        self.lut = torch.nn.Parameter(lut.contiguous())
        self.register_buffer("idx", idx.reshape(lut.shape[0] * group, -1)[:out].contiguous())
        self.register_buffer("row_group", torch.arange(out, device=w.device) // group, persistent=False)

    def _rows(self):
        return self.lut[self.row_group]                                       # [out, k]

    def forward(self, x):
        torch = _torch()
        q = torch.gather(self._rows(), 1, self.idx.long()).reshape(self.shape)
        return q + (x - x.detach())

    @_torch().no_grad()
    def refresh(self, x) -> None:
        """Reassign every latent weight to its nearest table entry: O(numel * log k)."""
        torch = _torch()
        c, perm = torch.sort(self._rows().float(), dim=1)
        mid = ((c[:, 1:] + c[:, :-1]) / 2).contiguous()
        pos = torch.searchsorted(mid, x.detach().float().reshape(self.shape[0], -1).contiguous())
        self.idx.copy_(torch.gather(perm, 1, pos).to(self.idx.dtype))


def attach(mod, name: str, nbits: int) -> FakePalette:
    from torch.nn.utils import parametrize

    fp = FakePalette(getattr(mod, name).detach(), nbits)
    parametrize.register_parametrization(mod, name, fp)
    return fp


def _palettes(model):
    for mname, mod in model.named_modules():
        ps = getattr(mod, "parametrizations", None)
        if ps is None:
            continue
        for pname, plist in ps.items():
            for p in plist:
                if isinstance(p, FakePalette):
                    yield (f"{mname}.{pname}" if mname else pname), plist, p


def refresh_all(model) -> None:
    for _, plist, p in _palettes(model):
        p.refresh(plist.original)


def check_packable(name: str, w, nbits: int, group: int = cu.GROUP) -> None:
    """Raise unless every 16-channel group of w holds at most 2**nbits distinct values (what mode 'unique' needs)."""
    torch = _torch()
    out = w.shape[0]
    flat = w.reshape(out, -1)
    pad = (-out) % group
    if pad:
        flat = torch.cat([flat, flat[-1:].expand(pad, -1)])
    s, _ = torch.sort(flat.reshape(-1, group * flat.shape[1]), dim=1)
    n = (s[:, 1:] != s[:, :-1]).sum(1) + 1
    worst = int(n.max())
    if worst > 1 << nbits:
        raise ValueError(f"{name}: a group holds {worst} distinct values, more than 2**{nbits}")


def quantized_weights(model) -> dict:
    """{weight name: fp16 tensor of table values}, each checked packable after the fp16 cast."""
    torch = _torch()
    out = {}
    with torch.no_grad():
        for name, plist, p in _palettes(model):
            w = p(plist.original).detach().to(torch.float16).cpu()
            check_packable(name, w, p.nbits)
            out[name] = w
    return out


# ---------------------------------------------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------------------------------------------

def librispeech_manifest(root: Path, subset: str, out_dir: Path) -> int:
    """root/<subset>/<speaker>/<chapter>/*.flac + *.trans.txt -> out_dir/manifest.jsonl. Every flac must have its
    transcript line and every line its flac, or nothing is written."""
    import soundfile as sf

    rows = []
    out_dir.mkdir(parents=True, exist_ok=True)
    for trans in sorted((root / subset).glob("*/*/*.trans.txt")):
        texts = {}
        for line in trans.read_text().splitlines():
            if line.strip():
                uid, _, text = line.strip().partition(" ")
                texts[uid] = text
        flacs = {f.stem: f for f in trans.parent.glob("*.flac")}
        if set(flacs) != set(texts):
            raise ValueError(f"{trans}: transcript ids and audio files differ "
                             f"({sorted(set(flacs) ^ set(texts))[:3]})")
        for uid in sorted(flacs):
            info = sf.info(str(flacs[uid]))
            if info.samplerate != 16000:
                raise ValueError(f"{flacs[uid]}: {info.samplerate} Hz")
            rows.append({"clip_id": uid, "file": os.path.relpath(flacs[uid], out_dir),
                         "audio_seconds": info.frames / info.samplerate, "reference": texts[uid].lower(),
                         "speaker": uid.split("-")[0], "subset": subset, "licence": LICENCE})
    if not rows:
        raise ValueError(f"no LibriSpeech audio under {root / subset}")
    tmp = out_dir / "manifest.jsonl.tmp"
    tmp.write_text("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
    tmp.rename(out_dir / "manifest.jsonl")
    return len(rows)


def duration_batches(rows: list[dict], batch_seconds: float, seed: int) -> list[list[dict]]:
    """Clips sorted by length, packed into batches of at most batch_seconds of audio (a longer clip goes alone), in a
    seeded random order."""
    rows = sorted(rows, key=lambda r: (r["audio_seconds"], r["clip_id"]))
    out, cur, secs = [], [], 0.0
    for r in rows:
        if cur and secs + r["audio_seconds"] > batch_seconds:
            out.append(cur); cur, secs = [], 0.0
        cur.append(r); secs += r["audio_seconds"]
    if cur:
        out.append(cur)
    random.Random(seed).shuffle(out)
    return out


def over_budget(started: float, now: float, hours: float) -> bool:
    return hours > 0 and now - started >= hours * 3600


def _signal_batch(rows, device):
    torch = _torch()
    xs = [cu._audio(r["path"]) for r in rows]
    n = max(len(x) for x in xs)
    sig = torch.stack([torch.nn.functional.pad(x, (0, n - len(x))) for x in xs]).to(device)
    return sig, torch.tensor([len(x) for x in xs], device=device)


def load_rows(d: Path, max_seconds: float, need_target: bool, limit: int | None = None) -> list[dict]:
    name = "pseudo.jsonl" if need_target else "manifest.jsonl"
    rows = [json.loads(l) for l in (d / name).read_text().splitlines() if l.strip()]
    rows = [r for r in rows if 0.5 <= r["audio_seconds"] <= max_seconds and (not need_target or r.get("target"))]
    rows.sort(key=lambda r: r["clip_id"])
    if limit and len(rows) > limit:
        step = len(rows) / limit
        rows = [rows[int(i * step)] for i in range(limit)]
    for r in rows:
        r["path"] = str(d / r["file"])
    return rows


# ---------------------------------------------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------------------------------------------

def cmd_librispeech(a) -> None:
    n = librispeech_manifest(a.root, a.subset, a.out)
    print(f"{a.subset}: {n} clips -> {a.out / 'manifest.jsonl'}")


def _greedy_texts(model, sig, lens):
    enc, enc_len = model.forward(input_signal=sig, input_signal_length=lens)
    hyps = model.decoding.rnnt_decoder_predictions_tensor(encoder_output=enc, encoded_lengths=enc_len)
    hyps = hyps[0] if isinstance(hyps, tuple) else hyps
    return [str(getattr(h, "text", h)) for h in hyps]


def cmd_pseudo(a) -> None:
    """The full-precision model's transcript of each clip, appended to pseudo.jsonl (resumable)."""
    torch = _torch()
    model = cu.load_ultra(a.nemo).to(a.device)
    rows = load_rows(a.data, a.max_seconds, need_target=False, limit=a.limit)
    out = a.data / "pseudo.jsonl"
    done = set()
    if out.exists():
        done = {json.loads(l)["clip_id"] for l in out.read_text().splitlines() if l.strip()}
    todo = [r for r in rows if r["clip_id"] not in done]
    print(f"pseudo-labels: {len(done)} done, {len(todo)} to go on {a.device}", flush=True)
    t0 = time.time()
    with torch.inference_mode(), out.open("a") as f:
        for i, b in enumerate(duration_batches(todo, a.batch_seconds, seed=0)):
            sig, lens = _signal_batch(b, a.device)
            for r, text in zip(b, _greedy_texts(model, sig, lens)):
                row = {k: v for k, v in r.items() if k != "path"}
                row["target"] = text.strip()
                f.write(json.dumps(row, sort_keys=True) + "\n")
            f.flush()
            if i % 20 == 0:
                print(f"  {i} batches, {time.time() - t0:.0f}s", flush=True)
    print(f"pseudo-labels done: {time.time() - t0:.0f}s", flush=True)


def make_plan(model, a) -> tuple[dict, str]:
    from edacc_eval.lowbit import plan_from_sensitivity

    mods = cu.palettizable(model)
    sizes = {n: int(m.weight.numel()) for n, m in mods.items()}
    if a.bits:
        return {n: a.bits for n in mods}, f"{a.bits}-bit everywhere"
    sens = json.loads(a.sensitivity.read_text())
    return plan_from_sensitivity(sens, sizes, a.target_bits, low=a.low, high=a.high)


def _loss_fn(model, device: str):
    """TDT loss on raw joint logits: NeMo's CUDA loss on a GPU, NeMo's pure-PyTorch TDT loss on the CPU (dry runs)."""
    torch = _torch()
    if str(device).startswith("cuda"):
        def nemo_loss(logits, tokens, enc_len, tok_len):
            return model.loss(log_probs=logits, targets=tokens, input_lengths=enc_len, target_lengths=tok_len)
        return nemo_loss
    from nemo.collections.asr.losses.rnnt_pytorch import TDTLossPytorch

    kw = dict(model.cfg.loss.get("tdt_kwargs", {}))
    crit = TDTLossPytorch(blank=model.decoder.blank_idx, durations=list(kw.get("durations", [0, 1, 2, 3, 4])),
                          reduction="mean_batch", sigma=float(kw.get("sigma", 0.0)))

    def cpu_loss(logits, tokens, enc_len, tok_len):
        cuda = torch.Tensor.cuda
        torch.Tensor.cuda = lambda self, *x, **k: self        # TDTLossPytorch calls .cuda() on two of its tensors
        try:
            return crit(acts=logits, labels=tokens, act_lens=enc_len, label_lens=tok_len)
        finally:
            torch.Tensor.cuda = cuda
    return cpu_loss


def dev_wer(model, rows, device, batch_seconds: float) -> float:
    torch = _torch()
    from edacc_eval.normalize import normalize
    from edacc_eval.wer import align_counts

    errors = words = 0
    with torch.inference_mode():
        for b in duration_batches(rows, batch_seconds, seed=0):
            sig, lens = _signal_batch(b, device)
            for r, text in zip(b, _greedy_texts(model, sig, lens)):
                c = align_counts(normalize(r["reference"]), normalize(text))
                errors += c.errors; words += c.n
    return errors / max(words, 1)


def free_params(model, which: str) -> dict:
    """Encoder parameters trained alongside the tables that stay unquantised in torch: 'small' = 1-D ones (biases,
    norms; exported as fp16, under the 2,048-element palettization threshold or kept by coremltools at the plan's
    widest width), 'encoder' = every encoder parameter that is not a fake palette's latent weight."""
    if which == "none":
        return {}
    palettised = {id(plist.original) for _, plist, _ in _palettes(model)}
    out = {}
    for name, p in model.encoder.named_parameters():
        if id(p) in palettised or name.endswith(".lut"):
            continue
        if which == "encoder" or p.dim() == 1:
            out[f"encoder.{name}"] = p
    return out


def _trainable(model):
    lat, luts = [], []
    for _, plist, p in _palettes(model):
        lat.append(plist.original); luts.append(p.lut)
    return lat, luts


def _save(path: Path, obj) -> None:
    torch = _torch()
    tmp = path.with_suffix(".tmp")
    torch.save(obj, tmp)
    tmp.rename(path)


def _state(model, free: dict) -> dict:
    return {"palettes": {name: {"original": plist.original.detach().cpu(), "lut": p.lut.detach().cpu(),
                                "idx": p.idx.cpu()} for name, plist, p in _palettes(model)},
            "free": {n: p.detach().cpu().clone() for n, p in free.items()}}


def _load_state(model, free: dict, st: dict) -> None:
    torch = _torch()
    with torch.no_grad():
        for name, plist, p in _palettes(model):
            s = st["palettes"][name]
            plist.original.copy_(s["original"]); p.lut.copy_(s["lut"]); p.idx.copy_(s["idx"])
        for n, p in free.items():
            p.copy_(st["free"][n])


def cmd_train(a) -> None:
    torch = _torch()
    started = time.time()
    torch.manual_seed(a.seed)
    torch.set_num_threads(a.threads)
    a.out.mkdir(parents=True, exist_ok=True)
    model = cu.load_ultra(a.nemo)
    plan, desc = make_plan(model, a)
    ours, theirs = cu.split_plan(plan)
    mods = cu.palettizable(model)
    model.to(a.device)
    torch.set_grad_enabled(True)
    model.eval()                                               # batch norm and dropout frozen
    for p in model.parameters():
        p.requires_grad_(False)
    t0 = time.time()
    for n in ours:
        attach(mods[n], "weight", plan[n])
    print(f"{desc}: {len(ours)} weights trained as fake palettes, {len(theirs)} left to coremltools at export; "
          f"tables initialised in {time.time() - t0:.0f}s", flush=True)
    lat, luts = _trainable(model)
    free = free_params(model, a.free)
    free_list = list(free.values())
    groups = [{"params": luts, "lr": a.lut_lr}]
    if a.lr > 0:
        groups.append({"params": lat, "lr": a.lr})
    else:
        lat = []
    if free_list:
        groups.append({"params": free_list, "lr": a.free_lr})
    for g in groups:
        for p in g["params"]:
            p.requires_grad_(True)
    trained = [p for g in groups for p in g["params"]]
    print(f"training {len(luts)} tables, {len(lat)} latent weights, {len(free)} free parameters "
          f"({sum(p.numel() for p in free_list) / 1e6:.1f} M)", flush=True)
    opt = torch.optim.AdamW(groups, weight_decay=0.0)
    teacher = None
    if a.kd > 0:
        teacher = cu.load_ultra(a.nemo).to(a.device)
        teacher.eval()
        for p in teacher.parameters():
            p.requires_grad_(False)
        torch.set_grad_enabled(True)                           # load_ultra turns gradients off for the process

    train = load_rows(a.train, a.max_seconds, need_target=True, limit=a.train_limit)
    dev = load_rows(a.dev, a.max_seconds, need_target=False, limit=a.dev_clips)
    loss_fn = _loss_fn(model, a.device)
    tok = model.tokenizer
    ck, best_path, log = a.out / "checkpoint.pt", a.out / "best.pt", a.out / "train.jsonl"
    step, epoch, best = 0, 0, None
    if ck.exists():
        st = torch.load(ck, map_location="cpu", weights_only=False)
        _load_state(model, free, st["state"])
        opt.load_state_dict(st["opt"])
        step, epoch, best = st["step"], st["epoch"], st["best"]
        print(f"resumed at step {step} (epoch {epoch}, best dev WER {best})", flush=True)
    meta = {"plan": plan, "plan_desc": desc, "args": {k: str(v) for k, v in vars(a).items()}, "data": LICENCE}

    def checkpoint():
        _save(ck, {"state": _state(model, free), "opt": opt.state_dict(), "step": step, "epoch": epoch,
                   "best": best, "meta": meta})

    def evaluate():
        nonlocal best
        w = dev_wer(model, dev, a.device, a.batch_seconds)
        rec = {"step": step, "epoch": epoch, "dev_wer": w, "hours": (time.time() - started) / 3600}
        if best is None or w < best:
            best = w
            _save(best_path, {"state": _state(model, free), "step": step, "dev_wer": w, "meta": meta})
            rec["best"] = True
        with log.open("a") as f:
            f.write(json.dumps(rec) + "\n")
        print(f"step {step}: dev-clean WER {w:.4f}{' (best)' if rec.get('best') else ''}", flush=True)

    if step == 0:
        evaluate()                                             # the data-free starting point, for the record
    stop = None
    while stop is None:
        batches = duration_batches(train, a.batch_seconds, seed=a.seed + epoch)
        skip = step - epoch * len(batches) if step > epoch * len(batches) else 0
        for b in batches[skip:]:
            sig, lens = _signal_batch(b, a.device)
            ids = [tok.text_to_ids(r["target"]) for r in b]
            u = max(len(i) for i in ids)
            tokens = torch.tensor([i + [0] * (u - len(i)) for i in ids], device=a.device)
            tok_len = torch.tensor([len(i) for i in ids], device=a.device)
            enc, enc_len = model.forward(input_signal=sig, input_signal_length=lens)
            dec, _, _ = model.decoder(targets=tokens, target_length=tok_len)
            logits = model.joint.joint(enc.transpose(1, 2), dec.transpose(1, 2))
            loss = loss_fn(logits, tokens, enc_len, tok_len)
            if teacher is not None:
                with torch.no_grad():
                    t_enc, _ = teacher.forward(input_signal=sig, input_signal_length=lens)
                mask = (torch.arange(enc.shape[-1], device=a.device)[None, :] < enc_len[:, None])[:, None, :]
                kd = (((enc - t_enc) ** 2) * mask).sum() / (mask.sum() * enc.shape[1]) / t_enc.var().clamp_min(1e-8)
                loss = loss + a.kd * kd
            if not torch.isfinite(loss):
                raise FloatingPointError(f"step {step}: loss is {float(loss)}")
            opt.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(trained, 1.0)
            opt.step()
            step += 1
            if lat and step % a.refresh == 0:
                refresh_all(model)
            if step % 10 == 0:
                print(f"step {step} loss {float(loss):.4f} {(time.time() - started) / 3600:.2f} h", flush=True)
            if step % a.eval_every == 0:
                if lat:
                    refresh_all(model)
                evaluate()
            if step % a.ckpt_every == 0:
                checkpoint()
            if over_budget(started, time.time(), a.budget_hours):
                stop = "BUDGET-STOP"; break
            if step >= a.steps:
                stop = "STEPS-DONE"; break
        else:
            epoch += 1
    if lat:
        refresh_all(model)
    evaluate()
    checkpoint()
    print(f"{stop}: step {step}, best dev-clean WER {best:.4f}, {(time.time() - started) / 3600:.2f} h", flush=True)


def cmd_export(a) -> None:
    """best.pt -> qat-weights.pt: the trained encoder weights as fp16 table values, checked packable."""
    torch = _torch()
    st = torch.load(a.checkpoint, map_location="cpu", weights_only=False)
    plan = st["meta"]["plan"]
    weights = {}
    for name, s in st["state"]["palettes"].items():
        mod_name = name.rsplit(".", 1)[0]
        lut, idx = s["lut"].float(), s["idx"].long()
        w = torch.gather(lut[torch.arange(idx.shape[0]) // cu.GROUP], 1, idx)
        w = w.reshape(s["original"].shape).to(torch.float16)
        check_packable(name, w, plan[mod_name])
        weights[mod_name] = w
    _save(a.out, {"plan": plan, "weights": weights, "free": st["state"]["free"], "meta": {**st["meta"], "step": st["step"],
                                                            "dev_wer": st.get("dev_wer")}})
    print(f"exported {len(weights)} weights from step {st['step']} (dev-clean WER {st.get('dev_wer')}) -> {a.out}")


def main() -> None:
    home = Path.home() / "edacc-272"
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("librispeech")
    s.add_argument("--root", type=Path, required=True, help="the LibriSpeech folder the tarballs unpack to")
    s.add_argument("--subset", required=True)
    s.add_argument("--out", type=Path, required=True)
    for name in ("pseudo", "train"):
        s = sub.add_parser(name)
        s.add_argument("--nemo", type=Path, default=home / "convert" / "ultra.nemo")
        s.add_argument("--device", default="cpu")
        s.add_argument("--threads", type=int, default=8)
        s.add_argument("--max-seconds", type=float, default=20.0)
        s.add_argument("--batch-seconds", type=float, default=60.0)
        if name == "pseudo":
            s.add_argument("--data", type=Path, required=True)
            s.add_argument("--limit", type=int)
        else:
            s.add_argument("--train", type=Path, required=True)
            s.add_argument("--dev", type=Path, required=True)
            s.add_argument("--out", type=Path, required=True)
            s.add_argument("--bits", type=int, help="uniform width; else a plan from --sensitivity")
            s.add_argument("--sensitivity", type=Path)
            s.add_argument("--target-bits", type=float, default=4.5)
            s.add_argument("--low", type=int, default=4)
            s.add_argument("--high", type=int, default=6)
            s.add_argument("--steps", type=int, default=3000)
            s.add_argument("--lr", type=float, default=0.0, help="latent-weight rate; 0 = assignments fixed (default)")
            s.add_argument("--free", choices=["none", "small", "encoder"], default="small")
            s.add_argument("--free-lr", type=float, default=1e-5)
            s.add_argument("--lut-lr", type=float, default=1e-5)
            s.add_argument("--kd", type=float, default=1.0, help="weight of the encoder-output distillation term; 0 = off")
            s.add_argument("--refresh", type=int, default=20)
            s.add_argument("--eval-every", type=int, default=250)
            s.add_argument("--ckpt-every", type=int, default=250)
            s.add_argument("--dev-clips", type=int, default=600)
            s.add_argument("--train-limit", type=int)
            s.add_argument("--budget-hours", type=float, default=0.0, help="stop (checkpointed) after this long; 0 = none")
            s.add_argument("--seed", type=int, default=0)
    s = sub.add_parser("export")
    s.add_argument("--checkpoint", type=Path, required=True)
    s.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    {"librispeech": cmd_librispeech, "pseudo": cmd_pseudo, "train": cmd_train, "export": cmd_export}[a.cmd](a)


if __name__ == "__main__":
    main()
