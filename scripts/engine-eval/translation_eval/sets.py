"""Translation test sets (#159): FLORES-200 devtest, WMT24++ speech, EdAcc caption lines.

Each set is JSONL, one line per segment: id, set, group (bootstrap unit), source, reference (None when the set has
no human translation). The data stays in ~/translation-eval; nothing here is committed.
"""
from __future__ import annotations

import csv
import json
import re
import unicodedata
from pathlib import Path
from typing import Iterable

from edacc_eval.normalize import FILLERS

MIN_WORDS, MAX_WORDS = 2, 40

_TAG = re.compile(r"<[^>]*>")


def caption_style(text: str) -> str:
    """What a caption engine shows for the same words: lowercase, no sentence punctuation, inner ' - . kept."""
    text = unicodedata.normalize("NFC", text).lower()
    out = []
    for i, ch in enumerate(text):
        cat = unicodedata.category(ch)
        if cat[0] in "PS":
            prev_ok = i > 0 and text[i - 1].isalnum()
            next_ok = i + 1 < len(text) and text[i + 1].isalnum()
            # 3.5 and 1,000 keep their separator; it's, well-known keep theirs
            if ch in "'’-" and prev_ok and next_ok:
                out.append("'" if ch == "’" else ch)
                continue
            if ch in ".," and prev_ok and next_ok and text[i - 1].isdigit() and text[i + 1].isdigit():
                out.append(ch)
                continue
            out.append(" ")
        else:
            out.append(ch)
    return " ".join("".join(out).split())


def edacc_line(reference: str) -> str | None:
    """An EdAcc reference as a caption line: tags and fillers dropped, lowercase; None if out of length range."""
    if "IGNORE_TIME_SEGMENT_IN_SCORING" in reference:
        return None
    words = [w for w in caption_style(_TAG.sub(" ", reference)).split() if w not in FILLERS]
    if not MIN_WORDS <= len(words) <= MAX_WORDS:
        return None
    return " ".join(words)


def _row(id_: str, set_: str, group: str, source: str, reference: str | None) -> dict:
    return {"id": id_, "set": set_, "group": group, "source": source, "reference": reference}


def _pair_sets(name: str, items: list[tuple[str, str, str, str]]) -> tuple[list[dict], list[dict]]:
    clean = [_row(i, name, g, s, r) for i, g, s, r in items]
    cap = [_row(i.replace(name, f"{name}-caption", 1), f"{name}-caption", g, caption_style(s), r)
           for i, g, s, r in items]
    return clean, cap


def build_flores(flores_dir: Path, target: str) -> tuple[list[dict], list[dict]]:
    """FLORES-200 devtest eng_Latn -> target, grouped by article URL. Returns (clean, caption-style)."""
    flores_dir = Path(flores_dir)
    src = (flores_dir / "devtest" / "eng_Latn.devtest").read_text(encoding="utf-8").splitlines()
    ref = (flores_dir / "devtest" / f"{target}.devtest").read_text(encoding="utf-8").splitlines()
    with (flores_dir / "metadata_devtest.tsv").open(encoding="utf-8") as fh:
        urls = [r[0] for r in csv.reader(fh, delimiter="\t")][1:]
    if not (len(src) == len(ref) == len(urls)):
        raise ValueError(f"FLORES files disagree: {len(src)} source, {len(ref)} reference, {len(urls)} metadata")
    return _pair_sets("flores", [(f"flores-{i:04d}", urls[i], s, r) for i, (s, r) in enumerate(zip(src, ref))])


def build_speech(wmt_jsonl: Path) -> tuple[list[dict], list[dict]]:
    """WMT24++ speech-domain segments (bad sources dropped), post-edited `target` as reference."""
    items = []
    with Path(wmt_jsonl).open(encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            if r["domain"] != "speech" or r["is_bad_source"]:
                continue
            items.append((f"speech-{int(r['segment_id']):04d}", str(r["document_id"]), r["source"], r["target"]))
    return _pair_sets("speech", items)


def build_edacc_lines(manifests: Iterable[Path]) -> list[dict]:
    """Unique caption lines from EdAcc shard manifests; no reference translation exists."""
    rows, seen = [], set()
    for m in manifests:
        with Path(m).open(encoding="utf-8") as fh:
            for line in fh:
                c = json.loads(line)
                text = edacc_line(c["reference"])
                if text is None or text in seen:
                    continue
                seen.add(text)
                rows.append(_row(f"edacc-{c['clip_id']}", "edacc-lines", c["speaker"], text, None))
    return rows


def write_set(path: Path, rows: list[dict]) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    return path


def read_set(path: Path) -> list[dict]:
    with Path(path).open(encoding="utf-8") as fh:
        return [json.loads(l) for l in fh if l.strip()]
