"""Hebrew engine test (#201): score every engine on every Hebrew test set with the #202 normalizer.

WER and CER, strict and lenient (full/defective spelling folded), each with a 95% bootstrap CI over sentence groups.
Method and the reasons behind it: docs/perf/hebrew-accuracy-design.md.
"""
from __future__ import annotations

import datetime as dt
import json
import math
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .hebrew import lenient_hebrew, normalize_he
from .results import load_results
from .wer import Counts, align_counts, bootstrap_ci, char_counts, pooled_wer

# model name in the result lines -> display name. Every engine the ticket names; one with no results is listed under
# "Not run" in the report so a gap is never silent.
EXPECTED = {
    "DictationTranscriber he-IL": "Apple DictationTranscriber he-IL",
    "parakeet-tdt-0.6b-v3-he": "Parakeet-He (thewh1teagle, transformers)",
    "zipformer2-66m-streaming-he-int8": "ivrit.ai zipformer2 66M (sherpa-onnx, int8)",
    "whisper-large-v3-turbo-ivrit": "ivrit.ai Whisper large-v3 turbo (transformers), reference only",
    "nemotron-3.5-asr-streaming-0.6b-1120ms-int8": "Nemotron 3.5 streaming 0.6B, zero-shot (sherpa-onnx, int8, 1.12 s)",
}
# Report order: conversation first, since that is what live captions face.
SET_NAMES = {"eval-d1": "ivrit.ai eval-d1 (conversation)", "eval-whatsapp": "ivrit.ai eval-whatsapp (voice notes)",
             "he_il": "FLEURS he (read speech)", "common-voice-he": "Common Voice he (read)"}


@dataclass(frozen=True)
class Rate:
    value: float
    low: float
    high: float


@dataclass
class HebrewCell:
    wer: Rate
    cer: Rate
    lenient_wer: Rate
    lenient_cer: Rate
    words: int
    chars: int
    sub: int
    dele: int
    ins: int
    clips: int
    groups: int
    audio_seconds: float
    processing_seconds: float
    engine_version: str = ""

    @property
    def x_realtime(self) -> float:
        return self.audio_seconds / self.processing_seconds if self.processing_seconds else math.nan


@dataclass
class SetScore:
    clips_total: int
    clips_compared: int
    cells: dict = field(default_factory=dict)  # label -> HebrewCell


def _rate(by_group: dict[str, list[Counts]]) -> Rate:
    flat = [c for cs in by_group.values() for c in cs]
    lo, hi = bootstrap_ci({g: (sum(c.errors for c in cs), sum(c.n for c in cs)) for g, cs in by_group.items()})
    return Rate(pooled_wer(flat), lo, hi)


def score_hebrew(manifest_rows: list[dict], result_rows: list[dict]) -> dict[str, SetScore]:
    """Per test set (manifest `set`, else `accent`, which FLEURS shards fill with the config name). O(result rows +
    words^2 + chars^2 per clip) plus O(1,000 x groups) per bootstrap."""
    clips = {m["clip_id"]: m for m in manifest_rows}
    set_of = {c: m.get("set") or m.get("accent") or "unknown" for c, m in clips.items()}
    hyps: dict[str, dict[str, dict]] = defaultdict(dict)  # label -> clip -> row (repeat 1, else the lowest)
    engine_of: dict[str, str] = {}
    for row in result_rows:
        if row["clip_id"] not in clips:
            continue
        lab = str(row["model"])  # the label is the model name; two runtimes sharing one would be merged, so refuse
        if engine_of.setdefault(lab, str(row["engine"])) != str(row["engine"]):
            raise ValueError(f"model {lab!r} appears under engines {engine_of[lab]!r} and {row['engine']!r}")
        prev = hyps[lab].get(row["clip_id"])
        if prev is None or int(row["repeat"]) < int(prev["repeat"]):
            hyps[lab][row["clip_id"]] = row
    out: dict[str, SetScore] = {}
    for test_set in sorted(set(set_of.values())):
        members = sorted(c for c in clips if set_of[c] == test_set)
        labels = [lab for lab in sorted(hyps) if any(c in hyps[lab] for c in members)]
        compared = [c for c in members if labels and all(c in hyps[lab] for lab in labels)]
        score = SetScore(clips_total=len(members), clips_compared=len(compared))
        refs = {c: normalize_he(clips[c]["reference"]) for c in compared}
        for lab in labels:
            w, ch, lw, lc = (defaultdict(list) for _ in range(4))
            audio = proc = 0.0
            for c in compared:
                row = hyps[lab][c]
                hyp, ref = normalize_he(row["hypothesis"]), refs[c]
                g = clips[c].get("group") or clips[c].get("speaker") or c
                w[g].append(align_counts(ref, hyp))
                ch[g].append(char_counts(ref, hyp))
                lw[g].append(align_counts(lenient_hebrew(ref), lenient_hebrew(hyp)))
                lc[g].append(char_counts(lenient_hebrew(ref), lenient_hebrew(hyp)))
                audio += float(row["audio_seconds"])
                proc += float(row["processing_seconds"])
            words = [c for cs in w.values() for c in cs]
            chars = [c for cs in ch.values() for c in cs]
            any_row = next(iter(hyps[lab][c] for c in compared), {}) if compared else {}
            score.cells[lab] = HebrewCell(
                wer=_rate(w), cer=_rate(ch), lenient_wer=_rate(lw), lenient_cer=_rate(lc),
                words=sum(c.n for c in words), chars=sum(c.n for c in chars), sub=sum(c.sub for c in words),
                dele=sum(c.dele for c in words), ins=sum(c.ins for c in words), clips=len(compared), groups=len(w),
                audio_seconds=audio, processing_seconds=proc, engine_version=str(any_row.get("engine_version", "")))
        out[test_set] = score
    return out


def _pct(x: float) -> str:
    return "–" if x is None or math.isnan(x) else f"{100 * x:.1f}%"


def _ci(r: Rate) -> str:
    return f"{_pct(r.low)} – {_pct(r.high)}"


def name_of(label: str) -> str:
    return EXPECTED.get(label, label)


def build_hebrew_report(scores: dict[str, SetScore], meta: dict) -> str:
    now = meta.get("generated_at") or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out = [
        "# Hebrew engine accuracy (#201)",
        "",
        "Generated by `scripts/engine-eval` (`report-hebrew`) for #201 \"[E] Hebrew: measure Apple's dictation engine "
        "against the open Hebrew models\". Do not edit by hand. Method: [hebrew-accuracy-design.md]"
        "(hebrew-accuracy-design.md).",
        "",
        f"Generated {now}. Every engine ran locally on the M4 Mac mini; nothing was sent to a cloud service.",
        "",
        "WER = (S + D + I) / N over words, CER the same over characters (single spaces included), pooled over clips, "
        "after the #202 Hebrew normalizer on both sides (niqqud, maqaf, geresh, numbers as digits, fillers). "
        "**Lenient** also folds full and defective spelling (שולחן = שלחן); it sits beside the strict score, never "
        "instead of it. 95% confidence intervals: bootstrap over each set's groups (1,000 resamples), named under each "
        "set. Only clips every engine "
        "finished are compared within a set. CER is the in-house decision metric: one wrong prefix letter "
        "(ו, ה, ב, ל, מ, ש, כ) costs a whole word in WER.",
        "",
    ]
    order = list(SET_NAMES)
    for test_set in sorted(scores, key=lambda k: (order.index(k) if k in order else len(order), k)):
        s = scores[test_set]
        info = (meta.get("sets") or {}).get(test_set, {})
        out += [f"## {SET_NAMES.get(test_set, test_set)}", ""]
        hours = info.get("audio_hours")
        source = (f" Dataset `{info['repo']}` @ `{info['revision'][:7]}`." if info.get("repo") and info.get("revision")
                  else "")
        unit = "sentences" if info.get("sentences") else "recordings"
        out += [f"{s.clips_total} clips" + (f", {info.get('sentences')} distinct sentences" if info.get("sentences")
                                            else "") + (f", {hours:.2f} h" if hours else "")
                + f". Compared on every engine below: {s.clips_compared} clips; bootstrap over {unit}." + source, ""]
        if not s.cells:
            out += ["No results yet.", ""]
            continue
        out += ["| Engine | WER | 95% CI | CER | 95% CI | Lenient WER | Lenient CER | Sub | Del | Ins | Ref words "
                "| Clips | Speed (x real time) |",
                "|---|---:|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
        for lab in sorted(s.cells, key=lambda l: (math.isnan(s.cells[l].cer.value), s.cells[l].cer.value)):
            c = s.cells[lab]
            xr = "–" if math.isnan(c.x_realtime) else f"{c.x_realtime:.1f}x"
            out.append(f"| {name_of(lab)} | {_pct(c.wer.value)} | {_ci(c.wer)} | {_pct(c.cer.value)} | {_ci(c.cer)} | "
                       f"{_pct(c.lenient_wer.value)} | {_pct(c.lenient_cer.value)} | {c.sub} | {c.dele} | {c.ins} | "
                       f"{c.words} | {c.clips} | {xr} |")
        out.append("")

    ran = {lab for s in scores.values() for lab in s.cells}
    out += ["## Not run", "",
            "Engines and sets with no results here, and why, are explained in the design doc "
            "([what could not run](hebrew-accuracy-design.md#what-could-not-run)).", ""]
    missing = [name for lab, name in EXPECTED.items() if lab not in ran]
    out += [f"- {name}" for name in missing] or ["- every expected engine has results"]
    out.append("")
    missing_sets = [name for k, name in SET_NAMES.items() if k not in scores]
    if missing_sets:
        out += ["Test sets not scored: " + "; ".join(missing_sets) + ".", ""]

    out += ["## Engines and versions", "", "| Engine | Model | Version |", "|---|---|---|"]
    seen = set()
    for s in scores.values():
        for lab, c in s.cells.items():
            if lab not in seen:
                seen.add(lab)
                out.append(f"| {name_of(lab)} | `{lab}` | {c.engine_version} |")
    ls = meta.get("load_stats") or {}
    if ls:
        out += ["", f"Result lines read: {ls.get('lines', 0)}; corrupt lines skipped: {ls.get('corrupt', 0)}; "
                    f"duplicates ignored: {ls.get('duplicates', 0)}."]
    return "\n".join(out) + "\n"


def write_hebrew_report(shards_root: Path, results_dir: Path, out: Path, json_out: Path | None = None) -> dict:
    """Shard sets under shards_root/<name>/ (index.json + shard-NNN/manifest.jsonl); every *.jsonl in results_dir."""
    from .shards import read_manifest

    shards_root = Path(shards_root)
    manifest, sets = [], {}
    for index_path in sorted(shards_root.glob("*/index.json")):
        index = json.loads(index_path.read_text(encoding="utf-8"))
        rows = [m for name in index["shards"] for m in read_manifest(index_path.parent / name)]
        manifest += rows
        for m in rows[:1]:
            sets[m.get("set") or m.get("accent") or "unknown"] = index
    rows, stats = load_results(sorted(Path(results_dir).glob("*.jsonl")))
    scores = score_hebrew(manifest, rows)
    Path(out).write_text(build_hebrew_report(scores, {"sets": sets, "load_stats": asdict(stats)}), encoding="utf-8")
    if json_out:
        Path(json_out).write_text(json.dumps({
            k: {"clips_total": s.clips_total, "clips_compared": s.clips_compared,
                "cells": {lab: {**asdict(c), "x_realtime": c.x_realtime} for lab, c in s.cells.items()}}
            for k, s in scores.items()}, indent=2, ensure_ascii=False, default=lambda x: None) + "\n", encoding="utf-8")
    return scores
