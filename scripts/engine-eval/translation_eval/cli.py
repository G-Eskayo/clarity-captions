"""Command line for the translation comparison test (#159). Run as `python -m translation_eval.cli <command>`."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import socket
import sys
from pathlib import Path

PAIRS = {  # pair -> (FLORES target, WMT24++ file stem)
    "en-es": ("spa_Latn", "en-es_MX"),
    "en-fr": ("fra_Latn", "en-fr_FR"),
    "en-de": ("deu_Latn", "en-de_DE"),
}
SET_NAMES = ["flores", "flores-caption", "speech", "speech-caption", "edacc-lines"]


def load_sets(sets_dir: Path) -> dict[str, list[dict]]:
    from .sets import read_set
    return {p.stem: read_set(p) for p in sorted(Path(sets_dir).glob("*.jsonl"))}


def cmd_build_sets(a) -> int:
    from .sets import build_edacc_lines, build_flores, build_speech, write_set
    flores_t, wmt = PAIRS[a.pair]
    out = Path(a.out) / a.pair
    fc, fcap = build_flores(Path(a.data) / "flores" / "flores200_dataset", flores_t)
    sc, scap = build_speech(Path(a.data) / "wmt24pp" / f"{wmt}.jsonl")
    edacc = build_edacc_lines(sorted((Path(a.data) / "edacc").glob("shard-*.jsonl")))
    for name, rows in zip(SET_NAMES, [fc, fcap, sc, scap, edacc]):
        write_set(out / f"{name}.jsonl", rows)
        print(f"{a.pair} {name}: {len(rows)}")
    return 0


def cmd_ct2(a) -> int:
    import ctranslate2
    from transformers import MarianTokenizer
    from .run import run_lines
    from .split import translate_split
    tok = MarianTokenizer.from_pretrained(a.hf_model)
    tr = ctranslate2.Translator(str(a.model), device="cpu", inter_threads=1, intra_threads=a.threads)

    def model_batch(lines: list[str]) -> list[str]:
        src = [tok.convert_ids_to_tokens(tok.encode(l)) for l in lines]
        res = tr.translate_batch(src, beam_size=a.beam, max_decoding_length=512)
        return [tok.decode(tok.convert_tokens_to_ids(r.hypotheses[0]), skip_special_tokens=True) for r in res]

    def batch(lines: list[str]) -> list[str]:
        return translate_split(lines, model_batch) if a.split else model_batch(lines)

    sets = load_sets(a.sets)
    version = (f"ctranslate2 {ctranslate2.__version__}, int8, beam {a.beam}, {a.threads} threads"
               + (", sentence split" if a.split else ""))
    model = a.name or Path(a.model).name.removesuffix("-ct2")
    batch(["warm up"])
    for name in SET_NAMES:
        if name not in sets:
            continue
        speed = name == "edacc-lines"
        s = run_lines(sets[name], a.results, engine=a.engine, model=model, version=version,
                      repeats=a.repeats if speed else 1, translate=None, translate_batch=batch,
                      batch_size=1 if speed else a.batch, host=socket.gethostname())
        print(f"{model} {name}: {s}", flush=True)
    return 0


def cmd_comet(a) -> int:
    """Score every reference set's repeat-1 lines with COMET; cache to comet.jsonl beside the results."""
    from comet import download_model, load_from_checkpoint
    from edacc_eval.results import load_results
    sets = load_sets(a.sets)
    seg = {r["id"]: r for rs in sets.values() for r in rs if r.get("reference") is not None}
    cache_path = Path(a.results) / "comet.jsonl"
    cached = set()
    if cache_path.exists():
        cached = {(d["engine"], d["model"], d["clip_id"]) for d in map(json.loads, cache_path.read_text().splitlines())}
    rows, _ = load_results(sorted(Path(a.results).glob("*.jsonl")))
    todo = [r for r in rows if int(r["repeat"]) == 1 and r["clip_id"] in seg
            and (r["engine"], r["model"], r["clip_id"]) not in cached]
    print(f"COMET: {len(todo)} segments to score", flush=True)
    if not todo:
        return 0
    model = load_from_checkpoint(download_model("Unbabel/wmt22-comet-da"))
    data = [{"src": seg[r["clip_id"]]["source"], "mt": r["hypothesis"], "ref": seg[r["clip_id"]]["reference"]}
            for r in todo]
    gpus = 0 if a.accelerator == "cpu" else 1
    out = model.predict(data, batch_size=a.batch, gpus=gpus, accelerator=a.accelerator, progress_bar=False)
    with cache_path.open("a", encoding="utf-8") as fh:
        for r, sc in zip(todo, out.scores):
            fh.write(json.dumps({"engine": r["engine"], "model": r["model"], "clip_id": r["clip_id"],
                                 "comet": round(float(sc), 5)}) + "\n")
    return 0


def cmd_report(a) -> int:
    from edacc_eval.results import load_results
    from .report import build_report, score_pair
    meta = json.loads(Path(a.meta).read_text()) if a.meta else {}
    pairs, js = {}, {}
    for pair in PAIRS:
        sdir, rdir = Path(a.sets) / pair, Path(a.results) / pair
        if not sdir.exists() or not rdir.exists():
            continue
        rows, stats = load_results(sorted(rdir.glob("*.jsonl")))
        comet = {}
        cp = rdir / "comet.jsonl"
        if cp.exists():
            for d in map(json.loads, cp.read_text().splitlines()):
                comet[(d["engine"], d["model"], d["clip_id"])] = d["comet"]
        speed = None
        if a.speed_results and (Path(a.speed_results) / pair).exists():
            speed, _ = load_results(sorted((Path(a.speed_results) / pair).glob("*.jsonl")))
        pairs[pair] = score_pair(load_sets(sdir), rows, comet, speed_rows=speed)
        js[pair] = pairs[pair]
    sizes = json.loads(Path(a.sizes).read_text()) if a.sizes and Path(a.sizes).exists() else {}
    meta = {**meta, "sizes": sizes, "generated": dt.date.today().isoformat()}
    Path(a.out).write_text(build_report(pairs, meta), encoding="utf-8")
    if a.json_out:
        Path(a.json_out).write_text(json.dumps(js, indent=1, default=list) + "\n")
    print(f"wrote {a.out}")
    return 0


def cmd_build_languages(a) -> int:
    from .languages import APPLE_FLORES, build_language_sets
    codes = a.codes.split(",") if a.codes else sorted(APPLE_FLORES)
    for code in codes:
        print(build_language_sets(Path(a.data) / "flores" / "flores200_dataset", a.edacc_lines, code, a.out))
    return 0


def cmd_languages_report(a) -> int:
    """Apple on FLORES for every language: es/fr/de from the main comparison, the rest from results-apple."""
    from edacc_eval.results import load_results
    from edacc_eval.sizes import dir_bytes
    from .languages import APPLE_FLORES, apple_assets, language_row, languages_table, pair_assets
    from .sets import read_set
    assets = apple_assets()
    out = []
    for code in sorted(APPLE_FLORES):
        main_pair = f"en-{code}" if f"en-{code}" in PAIRS else None
        sdir = Path(a.sets) / main_pair if main_pair else Path(a.language_sets) / f"en-{code}"
        rdir = Path(a.results) / main_pair if main_pair else Path(a.language_results) / f"en-{code}"
        if not (rdir / "apple.jsonl").exists():
            print(f"en-{code}: no Apple results, skipped")
            continue
        sets = {n: read_set(sdir / f"{n}.jsonl") for n in ("flores", "edacc-lines") if (sdir / f"{n}.jsonl").exists()}
        rows, _ = load_results([rdir / "apple.jsonl"])
        speed = None
        if main_pair and a.speed_results and (Path(a.speed_results) / main_pair / "apple.jsonl").exists():
            speed, _ = load_results([Path(a.speed_results) / main_pair / "apple.jsonl"])
        need = pair_assets(sorted(assets), code)
        disk = sum(dir_bytes(assets[s]) for s in need) if need else None
        comet = {}
        if (rdir / "comet.jsonl").exists():
            for d in map(json.loads, (rdir / "comet.jsonl").read_text().splitlines()):
                comet[(d["engine"], d["model"], d["clip_id"])] = d["comet"]
        row = language_row(code, sets, rows, speed_rows=speed, disk_bytes=disk, comet=comet)
        row["assets"] = need
        row["source"] = "main comparison" if main_pair else "all-languages run"
        out.append(row)
        print(f"en-{code}: chrF {row['chrf']:.1f}, {row['median_ms']} ms", flush=True)
    header = ("<!-- Generated by `python -m translation_eval.cli languages-report`; do not edit by hand. -->\n\n"
              f"# Apple Translation, every installed language: FLORES-200 devtest (#159)\n\nGenerated "
              f"{dt.date.today().isoformat()}. Written-text numbers (Wikipedia-style prose), not conversation. "
              "English source, 1,012 sentences, chrF with 95% group-bootstrap "
              "intervals (1,000 resamples over articles); COMET is wmt22-comet-da, mean segment score. Time per line: EdAcc caption lines, one at a time, median "
              "and p95 over two repeats after warm-up. Assets: the installed family asset plus its English and "
              "target assets, on disk.\n\n")
    Path(a.out).write_text(header + languages_table(out), encoding="utf-8")
    if a.json_out:
        Path(a.json_out).write_text(json.dumps(out, indent=1, default=list) + "\n")
    print(f"wrote {a.out}")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="translation_eval")
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build-sets")
    b.add_argument("--data", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--pair", choices=sorted(PAIRS), required=True)
    bl = sub.add_parser("build-languages", help="FLORES devtest + caption lines for every Apple language")
    bl.add_argument("--data", required=True)
    bl.add_argument("--edacc-lines", type=Path, required=True, help="an existing edacc-lines.jsonl")
    bl.add_argument("--out", type=Path, required=True)
    bl.add_argument("--codes", help="comma-separated Apple codes; default all")
    lr = sub.add_parser("languages-report", help="table of Apple on FLORES for every installed language")
    lr.add_argument("--sets", type=Path, required=True, help="main comparison sets (en-es, en-fr, en-de)")
    lr.add_argument("--results", type=Path, required=True, help="main comparison results")
    lr.add_argument("--speed-results", type=Path)
    lr.add_argument("--language-sets", type=Path, required=True)
    lr.add_argument("--language-results", type=Path, required=True)
    lr.add_argument("--out", type=Path, required=True)
    lr.add_argument("--json-out", type=Path)
    c = sub.add_parser("ct2", help="run an OPUS-MT model converted to CTranslate2 over one pair's sets")
    c.add_argument("--sets", type=Path, required=True)
    c.add_argument("--model", type=Path, required=True)
    c.add_argument("--hf-model", required=True, help="Hugging Face id, for the Marian tokenizer")
    c.add_argument("--engine", default="opus-mt")
    c.add_argument("--name")
    c.add_argument("--results", type=Path, required=True)
    c.add_argument("--beam", type=int, default=4)
    c.add_argument("--threads", type=int, default=4)
    c.add_argument("--batch", type=int, default=16)
    c.add_argument("--repeats", type=int, default=2)
    c.add_argument("--no-split", dest="split", action="store_false",
                   help="feed whole segments (Marian drops sentences from long multi-sentence input)")
    m = sub.add_parser("comet")
    m.add_argument("--sets", type=Path, required=True)
    m.add_argument("--results", type=Path, required=True, help="one pair's results directory")
    m.add_argument("--batch", type=int, default=16)
    m.add_argument("--accelerator", default="mps", help="mps (Apple GPU) or cpu")
    r = sub.add_parser("report")
    r.add_argument("--sets", type=Path, required=True)
    r.add_argument("--results", type=Path, required=True)
    r.add_argument("--out", type=Path, required=True)
    r.add_argument("--json-out", type=Path)
    r.add_argument("--meta", type=Path)
    r.add_argument("--sizes", type=Path)
    r.add_argument("--speed-results", type=Path, help="results of the isolated timing pass, one folder per pair")
    a = p.parse_args(argv)
    return {"build-sets": cmd_build_sets, "build-languages": cmd_build_languages,
            "languages-report": cmd_languages_report, "ct2": cmd_ct2, "comet": cmd_comet, "report": cmd_report}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
