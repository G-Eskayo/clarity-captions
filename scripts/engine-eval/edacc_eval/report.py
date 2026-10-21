"""Score all result lines so far and render docs/perf/engine-accuracy-comparison.md (#145).

Rebuilt from scratch each cycle: O(result lines + alignment) per run; a few seconds at EdAcc scale.
"""
from __future__ import annotations

import datetime as dt
import json
import math
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .normalize import normalize
from .results import load_results
from .wer import Counts, align_counts, bootstrap_ci, pooled_wer

GOOD, ACCEPTABLE = 0.15, 0.30  # docs/testing/test-plan.md targets
MIN_SPEAKERS = 3


@dataclass
class Cell:
    wer: float
    ci_low: float
    ci_high: float
    sub: int
    dele: int
    ins: int
    n: int
    clips: int
    speakers: int


@dataclass
class Determinism:
    clips: int = 0
    identical: int = 0
    identical_normalized: int = 0
    repeats: int = 0
    wer_min: float = math.nan
    wer_max: float = math.nan


@dataclass
class Speed:
    audio_seconds: float
    processing_seconds: float
    lines: int

    @property
    def rtf(self) -> float:
        return self.processing_seconds / self.audio_seconds if self.audio_seconds else math.nan

    @property
    def x_realtime(self) -> float:
        return self.audio_seconds / self.processing_seconds if self.processing_seconds else math.nan


@dataclass
class Score:
    labels: list[str]
    overall: dict[str, Cell]
    by_accent: dict[str, dict[str, Cell]]
    determinism: dict[str, Determinism]
    speed: dict[str, Speed]
    clips_compared: int
    audio_seconds_compared: float
    clips_done: dict[str, int]
    models: dict[str, dict]
    load_stats: dict = field(default_factory=dict)


def _labels(rows: list[dict]) -> dict[tuple[str, str], str]:
    models_per_engine: dict[str, set[str]] = defaultdict(set)
    for r in rows:
        models_per_engine[r["engine"]].add(str(r["model"]))
    out = {}
    for engine, models in models_per_engine.items():
        for m in models:
            out[(engine, m)] = engine if len(models) == 1 else f"{engine} ({m})"
    return out


def _cell(counts_by_speaker: dict[str, list[Counts]]) -> Cell:
    flat = [c for cs in counts_by_speaker.values() for c in cs]
    groups = {spk: (sum(c.errors for c in cs), sum(c.n for c in cs)) for spk, cs in counts_by_speaker.items()}
    lo, hi = bootstrap_ci(groups)
    return Cell(wer=pooled_wer(flat), ci_low=lo, ci_high=hi, sub=sum(c.sub for c in flat),
                dele=sum(c.dele for c in flat), ins=sum(c.ins for c in flat), n=sum(c.n for c in flat),
                clips=len(flat), speakers=len(counts_by_speaker))


def score(manifest_rows: list[dict], result_rows: list[dict]) -> Score:
    clips = {m["clip_id"]: m for m in manifest_rows}
    rows = [r for r in result_rows if r["clip_id"] in clips]
    label_of = _labels(rows)
    labels = sorted(set(label_of.values()))

    # hyps[label][clip][repeat] = text
    hyps: dict[str, dict[str, dict[int, str]]] = defaultdict(lambda: defaultdict(dict))
    speed_acc: dict[str, list[float]] = defaultdict(lambda: [0.0, 0.0, 0])
    models: dict[str, dict] = {}
    for r in rows:
        lab = label_of[(r["engine"], str(r["model"]))]
        hyps[lab][r["clip_id"]][int(r["repeat"])] = r["hypothesis"]
        acc = speed_acc[lab]
        acc[0] += float(r["audio_seconds"])
        acc[1] += float(r["processing_seconds"])
        acc[2] += 1
        models[lab] = {"engine": r["engine"], "model": str(r["model"]), "engine_version": str(r.get("engine_version", ""))}

    compared = sorted(c for c in clips if labels and all(c in hyps[lab] for lab in labels))
    ref_norm = {c: normalize(clips[c]["reference"]) for c in compared}

    overall: dict[str, Cell] = {}
    by_accent: dict[str, dict[str, Cell]] = {}
    determinism: dict[str, Determinism] = {}
    for lab in labels:
        per_speaker: dict[str, list[Counts]] = defaultdict(list)
        per_accent: dict[str, dict[str, list[Counts]]] = defaultdict(lambda: defaultdict(list))
        per_repeat: dict[int, list[Counts]] = defaultdict(list)
        det = Determinism()
        for c in compared:
            reps = hyps[lab][c]
            first = reps[min(reps)]
            counts = align_counts(ref_norm[c], normalize(first))
            spk = clips[c].get("speaker", c)
            per_speaker[spk].append(counts)
            per_accent[clips[c].get("accent", "unknown")][spk].append(counts)
            if len(reps) > 1:
                det.clips += 1
                texts = list(reps.values())
                det.identical += all(t == texts[0] for t in texts)
                det.identical_normalized += len({normalize(t) for t in texts}) == 1
                det.repeats = max(det.repeats, len(reps))
                for rep, text in reps.items():
                    per_repeat[rep].append(align_counts(ref_norm[c], normalize(text)))
        overall[lab] = _cell(per_speaker)
        by_accent[lab] = {acc: _cell(spk) for acc, spk in per_accent.items()}
        full = [rep for rep, cs in per_repeat.items() if len(cs) == det.clips]
        if det.clips and full:
            wers = [pooled_wer(per_repeat[rep]) for rep in full]
            det.wer_min, det.wer_max = min(wers), max(wers)
        determinism[lab] = det

    speed = {lab: Speed(*speed_acc[lab]) for lab in labels}
    return Score(labels=labels, overall=overall, by_accent=by_accent, determinism=determinism, speed=speed,
                 clips_compared=len(compared),
                 audio_seconds_compared=sum(float(clips[c].get("audio_seconds", 0)) for c in compared),
                 clips_done={lab: len(hyps[lab]) for lab in labels}, models=models)


def _pct(x: float) -> str:
    return "–" if x is None or (isinstance(x, float) and math.isnan(x)) else f"{100 * x:.1f}%"


def _verdict(w: float) -> str:
    if math.isnan(w):
        return ""
    return "good" if w <= GOOD else "acceptable" if w <= ACCEPTABLE else "above target"


def build_report(s: Score, meta: dict) -> str:
    now = meta.get("generated_at") or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out = [
        "# Engine accuracy comparison (EdAcc)",
        "",
        "Generated by `scripts/engine-eval` for #145 \"[E] Engine accuracy test on the Mac: compare speech engines on "
        "accented conversations with checked transcripts\". Do not edit by hand: the scorer on the 2012 Mac mini "
        "rewrites this file after every cycle. Method: [engine-accuracy-design.md](engine-accuracy-design.md).",
        "",
        f"**Status:** {meta.get('shards_done', 0)} of {meta.get('shards_total', '?')} shards scored · "
        f"{s.clips_compared} clips ({s.audio_seconds_compared / 3600:.2f} h) compared on every engine · {now}.",
        "",
        f"Targets (docs/testing/test-plan.md): word error rate **15% or less is good, 30% or less is acceptable**. "
        "WER = (S + D + I) / N, pooled over clips; 95% confidence intervals from a speaker-level bootstrap "
        "(1,000 resamples). Primary score uses repeat 1.",
        "",
    ]
    if not s.labels or s.clips_compared == 0:
        out += ["No results yet.", ""]
        return "\n".join(out)

    out += ["## Overall", "",
            "| Engine | WER | 95% CI | vs target | Sub | Del | Ins | Ref words | Clips | Speakers | Speed (x real time) |",
            "|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|"]
    for lab in sorted(s.labels, key=lambda l: s.overall[l].wer):
        c, sp = s.overall[lab], s.speed[lab]
        xr = "–" if math.isnan(sp.x_realtime) else f"{sp.x_realtime:.1f}x"
        out.append(f"| {lab} | {_pct(c.wer)} | {_pct(c.ci_low)} – {_pct(c.ci_high)} | {_verdict(c.wer)} | {c.sub} | "
                   f"{c.dele} | {c.ins} | {c.n} | {c.clips} | {c.speakers} | {xr} |")
    out.append("")

    accents = sorted({a for lab in s.labels for a in s.by_accent[lab]},
                     key=lambda a: -max(s.by_accent[l][a].n for l in s.labels if a in s.by_accent[l]))
    order = sorted(s.labels, key=lambda l: s.overall[l].wer)
    out += ["## By accent", "",
            "WER per engine (95% CI). Accents with fewer than 3 speakers in the sample are marked *; their intervals "
            "say little.", "",
            "| Accent | Speakers | Ref words | " + " | ".join(order) + " |",
            "|---|---:|---:|" + "---|" * len(order)]
    for a in accents:
        ref = s.by_accent[order[0]].get(a)
        spk = ref.speakers if ref else 0
        mark = "*" if spk < MIN_SPEAKERS else ""
        cells = []
        for lab in order:
            c = s.by_accent[lab].get(a)
            cells.append("–" if c is None else f"{_pct(c.wer)} ({_pct(c.ci_low)}–{_pct(c.ci_high)})")
        out.append(f"| {a}{mark} | {spk} | {ref.n if ref else 0} | " + " | ".join(cells) + " |")
    out.append("")

    out += ["## Determinism (repeats)", "",
            "Same clip, same engine, run again: did the text come out identical?", "",
            "| Engine | Clips repeated | Repeats | Identical raw text | Identical after normalizing | WER range across repeats |",
            "|---|---:|---:|---:|---:|---|"]
    for lab in order:
        d = s.determinism[lab]
        if d.clips == 0:
            out.append(f"| {lab} | 0 | 1 | – | – | – |")
            continue
        out.append(f"| {lab} | {d.clips} | {d.repeats} | {d.identical} ({100 * d.identical / d.clips:.1f}%) | "
                   f"{d.identical_normalized} ({100 * d.identical_normalized / d.clips:.1f}%) | "
                   f"{_pct(d.wer_min)} – {_pct(d.wer_max)} |")
    out.append("")

    out += ["## Speed", "",
            "Over every repeat. Real-time factor = processing time / audio time (lower is faster). Model loading is "
            "excluded. Apple-side engines ran on the M4 Mac mini; sherpa-onnx on the 2012 Mac mini's CPU.", "",
            "| Engine | Real-time factor | x real time | Audio processed (h) | Result lines |", "|---|---:|---:|---:|---:|"]
    for lab in order:
        sp = s.speed[lab]
        out.append(f"| {lab} | {sp.rtf:.4f} | {sp.x_realtime:.1f}x | {sp.audio_seconds / 3600:.2f} | {sp.lines} |")
    out.append("")

    out += ["## Engines and models", "", "| Engine | Model | Version | Clips done |", "|---|---|---|---:|"]
    for lab in order:
        m = s.models[lab]
        out.append(f"| {lab} | `{m['model']}` | {m['engine_version']} | {s.clips_done[lab]} |")
    out.append("")
    ls = meta.get("load_stats") or {}
    if ls:
        out += [f"Result lines read: {ls.get('lines', 0)}; corrupt lines skipped: {ls.get('corrupt', 0)}; "
                f"duplicates ignored: {ls.get('duplicates', 0)}.", ""]
    return "\n".join(out)


def write_report(shards_dir: Path, results_dir: Path, out: Path, json_out: Path | None = None) -> Score:
    shards_dir, results_dir = Path(shards_dir), Path(results_dir)
    index = json.loads((shards_dir / "index.json").read_text(encoding="utf-8"))
    rows, stats = load_results(sorted(results_dir.glob("*.jsonl")))
    shards_with_results = {int(r.get("shard", 0)) for r in rows}
    manifest_rows = []
    for name in index["shards"]:
        k = int(name.split("-")[1])
        if k in shards_with_results:
            from .shards import read_manifest
            manifest_rows += read_manifest(shards_dir / name)
    s = score(manifest_rows, rows)
    s.load_stats = asdict(stats)
    md = build_report(s, meta={"shards_done": len(shards_with_results), "shards_total": index["n_shards"],
                               "load_stats": asdict(stats)})
    Path(out).write_text(md + "\n", encoding="utf-8")
    if json_out:
        Path(json_out).write_text(json.dumps({
            "clips_compared": s.clips_compared,
            "overall": {k: asdict(v) for k, v in s.overall.items()},
            "by_accent": {k: {a: asdict(c) for a, c in v.items()} for k, v in s.by_accent.items()},
            "determinism": {k: asdict(v) for k, v in s.determinism.items()},
            "speed": {k: {**asdict(v), "rtf": v.rtf, "x_realtime": v.x_realtime} for k, v in s.speed.items()},
            "models": s.models, "load_stats": s.load_stats,
        }, indent=2, default=lambda x: None) + "\n", encoding="utf-8")
    return s
