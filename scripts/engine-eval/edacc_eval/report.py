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

from .normalize import normalize, strip_accents
from .results import load_results
from .wer import Counts, align_counts, bootstrap_ci, pooled_wer

GOOD, ACCEPTABLE = 0.15, 0.30
# Engines stopped partway (owner decision 2026-10-21). They keep their rows, scored on the clips they ran, and never
# shrink the set of clips the active engines are compared on.
DROPPED = {
    "whisperkit": "dropped after shard 1: slowest, least accurate, Apple-only (no Android path); scored on shard 1 only",
    "whisperkit-nogate": "diagnostic, shard 1 only (WhisperKit dropped after shard 1)",
}  # docs/testing/test-plan.md targets
MIN_SPEAKERS = 3
LENGTH_BUCKETS = [("under 1 s", 0.0, 1.0), ("1-5 s", 1.0, 5.0), ("5-30 s", 5.0, 30.0), ("over 30 s", 30.0, float("inf"))]


def length_bucket(seconds: float) -> str:
    for name, lo, hi in LENGTH_BUCKETS:
        if lo <= seconds < hi or (hi == 30.0 and seconds == 30.0):
            return name
    return LENGTH_BUCKETS[-1][0]


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
    speed_by_host: dict = field(default_factory=dict)
    latency: dict = field(default_factory=dict)
    sizes: dict = field(default_factory=dict)
    memory: dict = field(default_factory=dict)
    by_length: dict = field(default_factory=dict)
    notes: dict = field(default_factory=dict)
    accent_blind: dict = field(default_factory=dict)  # label -> pooled WER with diacritics stripped (#158 languages)


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


def score(manifest_rows: list[dict], result_rows: list[dict], dropped: dict | None = None) -> Score:
    dropped = DROPPED if dropped is None else dropped
    clips = {m["clip_id"]: m for m in manifest_rows}
    rows = [r for r in result_rows if r["clip_id"] in clips]
    label_of = _labels(rows)
    labels = sorted(set(label_of.values()))

    # hyps[label][clip][repeat] = text
    hyps: dict[str, dict[str, dict[int, str]]] = defaultdict(lambda: defaultdict(dict))
    speed_acc: dict[str, list[float]] = defaultdict(lambda: [0.0, 0.0, 0])
    host_acc: dict[tuple[str, str], list[float]] = defaultdict(lambda: [0.0, 0.0, 0])
    models: dict[str, dict] = {}
    for r in rows:
        lab = label_of[(r["engine"], str(r["model"]))]
        hyps[lab][r["clip_id"]][int(r["repeat"])] = r["hypothesis"]
        acc = speed_acc[lab]
        acc[0] += float(r["audio_seconds"])
        acc[1] += float(r["processing_seconds"])
        acc[2] += 1
        hacc = host_acc[(lab, str(r.get("host", "")))]
        hacc[0] += float(r["audio_seconds"]); hacc[1] += float(r["processing_seconds"]); hacc[2] += 1
        models[lab] = {"engine": r["engine"], "model": str(r["model"]), "engine_version": str(r.get("engine_version", ""))}

    active = [lab for lab in labels if models[lab]["engine"] not in dropped] or labels
    compared = sorted(c for c in clips if active and all(c in hyps[lab] for lab in active))
    clip_sets = {lab: compared if lab in active else sorted(c for c in clips if c in hyps[lab]) for lab in labels}
    lang_of = {c: clips[c].get("language") for c in clips}
    ref_norm = {c: normalize(clips[c]["reference"], lang_of[c]) for lab in labels for c in clip_sets[lab]}
    # Bootstrap unit: the manifest's group (FLEURS sentence id) when present, else the speaker (#145).
    unit_of = {c: clips[c].get("group") or clips[c].get("speaker", c) for c in clips}
    accent_blind: dict[str, float] = {}

    overall: dict[str, Cell] = {}
    by_accent: dict[str, dict[str, Cell]] = {}
    determinism: dict[str, Determinism] = {}
    by_length: dict[str, dict[str, Cell]] = {}
    for lab in labels:
        per_speaker: dict[str, list[Counts]] = defaultdict(list)
        per_accent: dict[str, dict[str, list[Counts]]] = defaultdict(lambda: defaultdict(list))
        per_repeat: dict[int, list[Counts]] = defaultdict(list)
        per_length: dict[str, dict[str, list[Counts]]] = defaultdict(lambda: defaultdict(list))
        det = Determinism()
        blind: list[Counts] = []
        for c in clip_sets[lab]:
            reps = hyps[lab][c]
            first = reps[min(reps)]
            hyp_norm = normalize(first, lang_of[c])
            counts = align_counts(ref_norm[c], hyp_norm)
            if lang_of[c] not in (None, "en"):  # English already strips diacritics
                blind.append(align_counts(strip_accents(ref_norm[c]), strip_accents(hyp_norm)))
            spk = unit_of[c]
            per_speaker[spk].append(counts)
            per_accent[clips[c].get("accent", "unknown")][spk].append(counts)
            per_length[length_bucket(float(clips[c].get("audio_seconds", 0)))][spk].append(counts)
            if len(reps) > 1:
                det.clips += 1
                texts = list(reps.values())
                det.identical += all(t == texts[0] for t in texts)
                det.identical_normalized += len({normalize(t, lang_of[c]) for t in texts}) == 1
                det.repeats = max(det.repeats, len(reps))
                for rep, text in reps.items():
                    per_repeat[rep].append(align_counts(ref_norm[c], normalize(text, lang_of[c])))
        overall[lab] = _cell(per_speaker)
        if blind:
            accent_blind[lab] = pooled_wer(blind)
        by_accent[lab] = {acc: _cell(spk) for acc, spk in per_accent.items()}
        by_length_lab = {b: _cell(spk) for b, spk in per_length.items()}
        full = [rep for rep, cs in per_repeat.items() if len(cs) == det.clips]
        if det.clips and full:
            wers = [pooled_wer(per_repeat[rep]) for rep in full]
            det.wer_min, det.wer_max = min(wers), max(wers)
        determinism[lab] = det
        by_length[lab] = by_length_lab

    speed = {lab: Speed(*speed_acc[lab]) for lab in labels}
    speed_by_host = {k: Speed(*v) for k, v in host_acc.items()}
    notes = {lab: dropped[models[lab]["engine"]] for lab in labels if lab not in active}
    return Score(notes=notes, labels=labels, overall=overall, by_accent=by_accent, determinism=determinism, speed=speed,
                 clips_compared=len(compared),
                 audio_seconds_compared=sum(float(clips[c].get("audio_seconds", 0)) for c in compared),
                 clips_done={lab: len(hyps[lab]) for lab in labels}, models=models, speed_by_host=speed_by_host,
                 by_length=by_length, accent_blind=accent_blind)


def _pct(x: float) -> str:
    return "–" if x is None or (isinstance(x, float) and math.isnan(x)) else f"{100 * x:.1f}%"


def _verdict(w: float) -> str:
    if math.isnan(w):
        return ""
    return "good" if w <= GOOD else "acceptable" if w <= ACCEPTABLE else "above target"


def _secs(x: float) -> str:
    return "–" if x is None or math.isnan(x) else f"{x:.2f} s"


def _latency_section(lat: dict) -> list[str]:
    if not lat or not lat.get("engines"):
        return []
    out = ["## Live latency (streaming sample)", "",
           f"{lat['clips']} clips ({lat['audio_seconds'] / 60:.0f} min of audio, shard 1, clips up to 30 s) fed as if "
           "live. **Time to correct word** = when a word first appears correctly (and is still right in the final "
           "text) minus when it was said. **Time to first text** = first words on screen minus the end of the "
           "first spoken word. Method: [engine-accuracy-design.md](engine-accuracy-design.md#live-latency).", "",
           "**Mac numbers, not iPhone numbers.** These ran on the M4 Mac mini. The ranking should carry over; "
           "absolute latency needs a check on the phone.", "",
           "| Engine | Streaming method | Time to correct word, median | p95 | Time to first text, median | p95 | "
           "Words timed | Words right in final |", "|---|---|---:|---:|---:|---:|---:|---:|"]
    for lab, e in sorted(lat["engines"].items(), key=lambda kv: kv[1]["median"] if not math.isnan(kv[1]["median"]) else 1e9):
        shown = f"{lab} † (dropped after shard 1)" if lab.split(" (")[0] in DROPPED else lab
        out.append(f"| {shown} | {e.get('method', '')} | {_secs(e['median'])} | {_secs(e['p95'])} | "
                   f"{_secs(e['first_text_median'])} | {_secs(e['first_text_p95'])} | {e['words']} | "
                   f"{_pct(e['final_correct_share'])} |")
    out.append("")
    return out


def _mb(b) -> str:
    return "–" if b is None else f"{b / 1e6:.0f} MB"


def size_rows(s: Score) -> list[dict]:
    """One row per model that has a size record: size, WER, latency, memory, and whether it clearly beats Apple
    (upper end of its 95% CI below Apple's WER)."""
    apple = next((l for l in s.labels if s.models[l]["engine"] == "apple-speechanalyzer"), None)
    apple_wer = s.overall[apple].wer if apple else math.nan
    by_model = {s.models[l]["model"]: l for l in s.labels}
    lat = (s.latency or {}).get("engines", {})
    rows = []
    for model, z in s.sizes.items():
        lab = by_model.get(model)
        cell = s.overall.get(lab) if lab else None
        lat_key = next((k for k in lat if k.endswith(f"({model})")), None)
        mem = s.memory.get(model, {})
        rows.append({
            "model": model, "label": lab, "method": z.get("method", ""), "disk": z.get("disk_bytes"),
            "zipped": z.get("zipped_bytes"), "wer": cell.wer if cell else math.nan,
            "ci": (cell.ci_low, cell.ci_high) if cell else (math.nan, math.nan),
            "latency": (lat[lat_key]["median"], lat[lat_key]["p95"]) if lat_key else (math.nan, math.nan),
            "memory_peak_mb": mem.get("footprint_peak_mb"),
            "beats_apple": bool(cell and not math.isnan(apple_wer) and cell.ci_high < apple_wer),
        })
    rows.sort(key=lambda r: r["disk"] or 0)
    return rows


def _size_section(s: Score) -> list[str]:
    if not s.sizes:
        return []
    out = ["## Size options (Parakeet builds)", "",
           "Whole model folder as the app would ship it (all components). Zipped = deflate level 9, close to what an "
           "App Store download costs. Memory = this process's peak footprint while transcribing 60 clips on the M4 "
           "(Neural Engine memory held by system daemons is not included). \"Clearly beats Apple\" = the upper end "
           "of the 95% CI is below Apple SpeechAnalyzer's WER.", "",
           "| Model | Method | On disk | Zipped | WER (95% CI) | Clearly beats Apple | Correct word, median / p95 | "
           "Peak memory |", "|---|---|---:|---:|---|---|---|---:|"]
    for r in size_rows(s):
        wer = "not run" if math.isnan(r["wer"]) else f"{_pct(r['wer'])} ({_pct(r['ci'][0])}–{_pct(r['ci'][1])})"
        latency = "–" if math.isnan(r["latency"][0]) else f"{_secs(r['latency'][0])} / {_secs(r['latency'][1])}"
        mem = "–" if r["memory_peak_mb"] is None else f"{r['memory_peak_mb']:.0f} MB"
        beats = "–" if math.isnan(r["wer"]) else ("yes" if r["beats_apple"] else "no")
        out.append(f"| {r['model']} | {r['method']} | {_mb(r['disk'])} | {_mb(r['zipped'])} | {wer} | {beats} | "
                   f"{latency} | {mem} |")
    apple_mem = next((v for k, v in s.memory.items() if k.startswith("SpeechTranscriber")), None)
    if apple_mem:
        out += ["", f"Apple SpeechAnalyzer for reference: model is a system asset (not in the app download); this "
                    f"process peaked at {apple_mem['footprint_peak_mb']:.0f} MB (the recognizer runs largely in a system "
                    "service, so this understates its memory)."]
    out.append("")
    return out


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
    for lab in sorted(s.labels, key=lambda l: (l in s.notes, s.overall[l].wer)):
        c, sp = s.overall[lab], s.speed[lab]
        xr = "–" if math.isnan(sp.x_realtime) else f"{sp.x_realtime:.1f}x"
        shown = f"{lab} ({s.notes[lab]})" if lab in s.notes else lab
        out.append(f"| {shown} | {_pct(c.wer)} | {_pct(c.ci_low)} – {_pct(c.ci_high)} | {_verdict(c.wer)} | {c.sub} | "
                   f"{c.dele} | {c.ins} | {c.n} | {c.clips} | {c.speakers} | {xr} |")
    out.append("")

    accents = sorted({a for lab in s.labels for a in s.by_accent[lab]},
                     key=lambda a: -max(s.by_accent[l][a].n for l in s.labels if a in s.by_accent[l]))
    order = sorted(s.labels, key=lambda l: (l in s.notes, s.overall[l].wer))
    head = [f"{l} †" if l in s.notes else l for l in order]
    out += ["## By accent", "",
            "WER per engine (95% CI). Accents with fewer than 3 speakers in the sample are marked *; their intervals "
            "say little.", "",
            "† dropped after shard 1; its cells cover shard 1 only." if s.notes else "", "",
            "| Accent | Speakers | Ref words | " + " | ".join(head) + " |",
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

    out += ["## By clip length", "",
            "EdAcc is cut into segments; 28% are under a second (\"yeah\", \"right\"). Engines differ most on those, "
            "and in a live conversation they would arrive inside continuous audio rather than alone.", "",
            "| Clip length | Ref words | " + " | ".join(head) + " |", "|---|---:|" + "---|" * len(order)]
    for name, _, _ in LENGTH_BUCKETS:
        ref = s.by_length.get(order[0], {}).get(name)
        if ref is None:
            continue
        cells = [_pct(s.by_length[lab][name].wer) if name in s.by_length.get(lab, {}) else "–" for lab in order]
        out.append(f"| {name} | {ref.n} | " + " | ".join(cells) + " |")
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
            "excluded. Machine is the hostname each result line recorded: the M4 Mac mini shows as gils-mac-mini.local "
            "(Swift) or Mac (Python), the 2012 Mac mini as mac-mini-2012. All engines ran at low priority (nice +15) "
            "alongside other work, so treat speed as indicative.", "",
            "| Engine | Machine | Real-time factor | x real time | Audio processed (h) | Result lines |",
            "|---|---|---:|---:|---:|---:|"]
    for lab in order:
        hosts = sorted(h for (l, h) in s.speed_by_host if l == lab) or [""]
        for h in hosts:
            sp = s.speed_by_host.get((lab, h), s.speed[lab])
            out.append(f"| {lab} | {h or '–'} | {sp.rtf:.4f} | {sp.x_realtime:.1f}x | {sp.audio_seconds / 3600:.2f} | "
                       f"{sp.lines} |")
    out.append("")
    out += _latency_section(s.latency)
    out += _size_section(s)

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
    if (results_dir / "sizes.json").exists():
        s.sizes = json.loads((results_dir / "sizes.json").read_text(encoding="utf-8"))
    for mem_file in sorted((results_dir / "memory").glob("*.jsonl")):
        for raw in mem_file.read_text(encoding="utf-8").splitlines():
            try:
                m = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(m, dict) and "model" in m:
                s.memory[m["model"]] = m  # last measurement wins
    for lat_file in sorted((results_dir / "latency").glob("latency-shard-*.jsonl")):
        from .latency import analyze
        from .shards import read_manifest as _rm
        shard_name = lat_file.stem[len("latency-"):]
        if (shards_dir / shard_name).exists():
            s.latency = analyze(lat_file, _rm(shards_dir / shard_name))
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
            "models": s.models, "load_stats": s.load_stats, "latency": s.latency,
            "speed_by_host": {f"{k[0]} @ {k[1]}": {**asdict(v), "rtf": v.rtf} for k, v in s.speed_by_host.items()},
        }, indent=2, default=lambda x: None) + "\n", encoding="utf-8")
    return s


# --- Languages (#158): FLEURS Spanish, French, German ------------------------------------------------------------

LANGUAGE_NAMES = {"es": "Spanish", "fr": "French", "de": "German"}
APPLE_ENGINE, ULTRA_ENGINE, ONNX_ENGINE = "apple-speechanalyzer", "parakeet-fluidaudio", "sherpa-onnx"


@dataclass
class Verdict:
    verdict: str            # "Parakeet", "Apple" or "not ready"
    reason: str
    apple_label: str | None = None


def _ci(c: Cell) -> str:
    return f"{_pct(c.wer)} ({_pct(c.ci_low)}–{_pct(c.ci_high)})"


def recommend(apple: dict, ultra: Cell | None, not_ready: float = GOOD) -> Verdict:
    """The #158 rule (language-accuracy-design.md): not ready if the better of Apple's best locale and Parakeet Ultra
    misses the 15% line; else Parakeet if the low end of Ultra's 95% CI is at or below Apple's WER (ADR 0026 §3,
    "matches or beats"); else Apple."""
    valid = {k: c for k, c in apple.items() if c is not None and not math.isnan(c.wer)}
    if not valid or ultra is None or math.isnan(ultra.wer):
        missing = ", ".join(n for n, ok in (("Apple", bool(valid)), ("Parakeet Ultra", ultra is not None
                                            and not math.isnan(ultra.wer))) if not ok)
        return Verdict("not ready", f"no results yet for {missing}")
    label = min(valid, key=lambda k: valid[k].wer)
    a = valid[label]
    best = min(a.wer, ultra.wer)
    if best > not_ready:
        return Verdict("not ready", f"the better engine still has {_pct(best)} word errors on read speech, above "
                                    f"the {_pct(not_ready)} line", label)
    if ultra.ci_low <= a.wer:
        how = "beats" if ultra.ci_high < a.wer else "matches"
        return Verdict("Parakeet", f"Parakeet Ultra {_ci(ultra)} {how} Apple's best locale {_ci(a)}", label)
    return Verdict("Apple", f"Apple's best locale {_ci(a)} is clearly ahead of Parakeet Ultra {_ci(ultra)}", label)


def display_name(model: dict) -> str:
    engine, name = model["engine"], model["model"]
    if engine == APPLE_ENGINE:
        return "Apple SpeechAnalyzer, " + name.replace("SpeechTranscriber ", "")
    if engine == ULTRA_ENGINE:
        return "Parakeet Ultra, FluidAudio (Core ML)" if "ultra" in name else f"Parakeet {name}, FluidAudio (Core ML)"
    if engine == ONNX_ENGINE:
        if "ultra" in name:
            return "Parakeet Ultra, sherpa-onnx (ONNX, community export)"
        return "Parakeet v3, sherpa-onnx (ONNX)" if "v3" in name else f"{name}, sherpa-onnx (ONNX)"
    return f"{engine} ({name})"


@dataclass
class LanguageResult:
    language: str
    score: Score
    verdict: Verdict
    index: dict

    def labels_for(self, engine: str) -> list[str]:
        return [l for l in self.score.labels if self.score.models[l]["engine"] == engine]

    @property
    def ultra_label(self) -> str | None:
        labs = self.labels_for(ULTRA_ENGINE)
        return next((l for l in labs if "ultra" in self.score.models[l]["model"]), labs[0] if labs else None)


def score_language(lang: str, manifest_rows: list[dict], result_rows: list[dict], index: dict) -> LanguageResult:
    s = score(manifest_rows, result_rows, dropped={})
    res = LanguageResult(lang, s, Verdict("not ready", "no results yet"), index)
    if s.clips_compared:
        apple = {l: s.overall[l] for l in res.labels_for(APPLE_ENGINE)}
        u = res.ultra_label
        res.verdict = recommend(apple, s.overall[u] if u else None)
    return res


def _android_line(res: LanguageResult) -> str:
    s, u = res.score, res.ultra_label
    parts = []
    for lab in sorted(res.labels_for(ONNX_ENGINE)):
        c = s.overall[lab]
        rel = ""
        if u:
            uc = s.overall[u]
            gap = 100 * (c.wer - uc.wer)
            rel = (" (same as Ultra on Core ML within its interval)" if uc.ci_low <= c.wer <= uc.ci_high
                   else f" ({abs(gap):.1f} points {'worse' if gap > 0 else 'better'} than Ultra on Core ML)")
        parts.append(f"{display_name(s.models[lab])} {_ci(c)}{rel}")
    return "Android path: " + ("; ".join(parts) if parts else "no ONNX results yet") + "."


def build_language_report(results: dict[str, LanguageResult], meta: dict) -> str:
    now = meta.get("generated_at") or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    names = [LANGUAGE_NAMES.get(l, l) for l in results]
    out = [
        "# Language accuracy comparison (FLEURS)",
        "",
        "Generated by `scripts/engine-eval` (`report-languages`) for #158 \"[E] Language accuracy test: Apple vs "
        "Parakeet Ultra (and its Android build) on Spanish, French and German\". Do not edit by hand. Method: "
        "[language-accuracy-design.md](language-accuracy-design.md).",
        "",
        f"**Languages:** {', '.join(names)} · {now}.",
        "",
        "WER = (S + D + I) / N, pooled over clips, after a per-language normalizer that keeps accents (an engine that "
        "writes *esta* for *está* makes an error). **Accent-blind** is the same score with accent marks removed, to "
        "show how much of the error is only accents. 95% confidence intervals: bootstrap over FLEURS sentences "
        "(1,000 resamples). Only clips every engine finished are compared. Targets (docs/testing/test-plan.md): "
        "**15% or less is good, 30% or less is acceptable**.",
        "",
        "**FLEURS is read speech in quiet rooms**, not conversation. Every engine scores far better here than in a "
        "sit-down chat (#145 on EdAcc), so the ranking is the useful part and the absolute numbers flatter all of "
        "them. Mac numbers (M4 Mac mini, nice +15 next to other work), not iPhone numbers.",
        "",
        "## Summary",
        "",
        "| Language | Apple, best locale | Parakeet Ultra (Core ML) | Parakeet v3 (ONNX) | Parakeet Ultra (ONNX) | Recommendation |",
        "|---|---|---|---|---|---|",
    ]
    for lang, res in results.items():
        s = res.score
        def pick(engine, want):
            labs = [l for l in res.labels_for(engine) if want(s.models[l]["model"])]
            return _ci(s.overall[labs[0]]) if labs else "–"
        apple = (f"{_ci(s.overall[res.verdict.apple_label])}, {s.models[res.verdict.apple_label]['model'].split()[-1]}"
                 if res.verdict.apple_label else "–")
        out.append(f"| {LANGUAGE_NAMES.get(lang, lang)} | {apple} | {pick(ULTRA_ENGINE, lambda m: 'ultra' in m)} | "
                   f"{pick(ONNX_ENGINE, lambda m: 'ultra' not in m)} | {pick(ONNX_ENGINE, lambda m: 'ultra' in m)} | "
                   f"**{res.verdict.verdict}** |")
    out.append("")

    for lang, res in results.items():
        s, idx = res.score, res.index
        out += [f"## {LANGUAGE_NAMES.get(lang, lang)}", ""]
        if idx:
            out += [f"FLEURS `{idx.get('config', '')}` test split: {idx.get('clips', '?')} clips, "
                    f"{idx.get('sentences', '?')} distinct sentences, {idx.get('audio_hours', 0):.2f} h. Compared on "
                    f"every engine: {s.clips_compared} clips ({s.audio_seconds_compared / 3600:.2f} h).", ""]
        if not s.clips_compared:
            out += ["No results yet.", ""]
            continue
        out += ["| Engine | WER | 95% CI | Accent-blind WER | vs target | Sub | Del | Ins | Ref words | Clips | "
                "Sentences | Speed (x real time) |", "|---|---:|---|---:|---|---:|---:|---:|---:|---:|---:|---:|"]
        for lab in sorted(s.labels, key=lambda l: s.overall[l].wer):
            c, sp = s.overall[lab], s.speed[lab]
            xr = "–" if math.isnan(sp.x_realtime) else f"{sp.x_realtime:.1f}x"
            out.append(f"| {display_name(s.models[lab])} | {_pct(c.wer)} | {_pct(c.ci_low)} – {_pct(c.ci_high)} | "
                       f"{_pct(s.accent_blind.get(lab, math.nan))} | {_verdict(c.wer)} | {c.sub} | {c.dele} | {c.ins} | "
                       f"{c.n} | {c.clips} | {c.speakers} | {xr} |")
        out += ["", f"**{res.verdict.verdict}**: {res.verdict.reason}.", "", _android_line(res), ""]

    out += ["## Engines and models", "", "| Engine | Model | Version |", "|---|---|---|"]
    seen = set()
    for res in results.values():
        for lab in res.score.labels:
            m = res.score.models[lab]
            key = (m["engine"], m["model"])
            if key not in seen:
                seen.add(key)
                out.append(f"| {display_name(m)} | `{m['model']}` | {m['engine_version']} |")
    out.append("")
    ls = meta.get("load_stats") or {}
    if ls:
        out += [f"Result lines read: {ls.get('lines', 0)}; corrupt lines skipped: {ls.get('corrupt', 0)}; "
                f"duplicates ignored: {ls.get('duplicates', 0)}.", ""]

    out += ["## Recommendation", "",
            "Rule (decided before the run, [design](language-accuracy-design.md#recommendation-rule)): **not ready** if "
            "the better of Apple's best locale and Parakeet Ultra is above 15% WER; otherwise **Parakeet** if Ultra "
            "matches or beats Apple (the low end of its 95% CI is at or below Apple's WER, ADR 0026 §3); otherwise "
            "**Apple**.", "",
            "| Language | Recommendation | Why |", "|---|---|---|"]
    for lang, res in results.items():
        out.append(f"| {LANGUAGE_NAMES.get(lang, lang)} | {res.verdict.verdict} | {res.verdict.reason} |")
    return "\n".join(out)


def write_language_report(shards_root: Path, results_dir: Path, out: Path,
                          json_out: Path | None = None) -> dict[str, LanguageResult]:
    """One shard set per language under shards_root/<lang>/ (fleurs.py); every *.jsonl in results_dir."""
    from .shards import read_manifest

    shards_root = Path(shards_root)
    rows, stats = load_results(sorted(Path(results_dir).glob("*.jsonl")))
    langs = [l for l in LANGUAGE_NAMES if (shards_root / l / "index.json").exists()]
    results: dict[str, LanguageResult] = {}
    for lang in langs:
        index = json.loads((shards_root / lang / "index.json").read_text(encoding="utf-8"))
        manifest = [m for name in index["shards"] for m in read_manifest(shards_root / lang / name)]
        ids = {m["clip_id"] for m in manifest}
        results[lang] = score_language(lang, manifest, [r for r in rows if r["clip_id"] in ids], index)
    md = build_language_report(results, meta={"load_stats": asdict(stats)})
    Path(out).write_text(md + "\n", encoding="utf-8")
    if json_out:
        Path(json_out).write_text(json.dumps({
            lang: {"verdict": res.verdict.verdict, "reason": res.verdict.reason, "apple_label": res.verdict.apple_label,
                   "clips_compared": res.score.clips_compared,
                   "overall": {k: asdict(v) for k, v in res.score.overall.items()},
                   "accent_blind": res.score.accent_blind,
                   "speed": {k: {**asdict(v), "rtf": v.rtf, "x_realtime": v.x_realtime}
                             for k, v in res.score.speed.items()},
                   "models": res.score.models}
            for lang, res in results.items()}, indent=2, default=lambda x: None) + "\n", encoding="utf-8")
    return results
