"""Every English->X pair Apple's Translation framework has installed, on FLORES-200 devtest (#159 follow-up).

One folder per language under ~/translation-eval/sets-apple/en-<code>: flores.jsonl (written text with human
references) and edacc-lines.jsonl (the en-es caption lines, for time per line; source-only, so any target works).
The table is one row per language, sorted by chrF.
"""
from __future__ import annotations

import math
import plistlib
from pathlib import Path

from .sets import build_flores, read_set, write_set

APPLE_ASSETS = Path("/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Translation_Assets")

# Apple language code (Locale.Language minimal identifier, as `translation-eval --list` prints it) -> FLORES-200 code.
# Apple's Arabic is ar-AE (Modern Standard Arabic in the UI); FLORES's MSA file is arb_Arab.
APPLE_FLORES = {
    "ar-AE": "arb_Arab", "de": "deu_Latn", "es": "spa_Latn", "fr": "fra_Latn", "hi": "hin_Deva", "id": "ind_Latn",
    "it": "ita_Latn", "ja": "jpn_Jpan", "ko": "kor_Hang", "nl": "nld_Latn", "pl": "pol_Latn", "pt": "por_Latn",
    "ru": "rus_Cyrl", "th": "tha_Thai", "tr": "tur_Latn", "uk": "ukr_Cyrl", "vi": "vie_Latn", "zh": "zho_Hans",
    "zh-TW": "zho_Hant",
}

NAMES = {
    "ar-AE": "Arabic", "de": "German", "es": "Spanish", "fr": "French", "hi": "Hindi", "id": "Indonesian",
    "it": "Italian", "ja": "Japanese", "ko": "Korean", "nl": "Dutch", "pl": "Polish", "pt": "Portuguese (Brazil)",
    "ru": "Russian", "th": "Thai", "tr": "Turkish", "uk": "Ukrainian", "vi": "Vietnamese",
    "zh": "Chinese (Simplified)", "zh-TW": "Chinese (Traditional)",
}


def apple_assets(root: Path = APPLE_ASSETS) -> dict[str, Path]:
    """Installed Translation asset folders by AssetSpecifier (com.apple.sequoia.asset.mt.bi-en-ar.en.20 ...)."""
    out = {}
    for info in Path(root).glob("*/*.asset/Info.plist"):
        with info.open("rb") as fh:
            spec = plistlib.load(fh).get("MobileAssetProperties", {}).get("AssetSpecifier")
        if spec:
            out[spec] = info.parent
    return out


def pair_assets(specifiers: list[str], code: str) -> list[str]:
    """The machine-translation assets en->code needs: its family's shared asset plus the family's en and target
    assets. Families are named mt.bi-en-<lang>-<lang>...; zh-TW uses the zh assets, ar-AE the ar ones."""
    lang = code.split("-")[0]
    for spec in specifiers:
        parts = spec.split(".")
        # com.apple.sequoia.asset.mt.<family>.<version> is the family's shared asset
        if len(parts) == 7 and parts[4] == "mt" and parts[5].startswith("bi-en-") \
                and lang in parts[5].split("-")[2:]:
            family, version = ".".join(parts[:6]), parts[6]
            want = [f"{family}.{version}", f"{family}.en.{version}", f"{family}.{lang}.{version}"]
            if all(w in specifiers for w in want):
                return want
    return []


def build_language_sets(flores_dir: Path, edacc_lines: Path, code: str, out_dir: Path) -> Path:
    """Write en-<code>/flores.jsonl and a copy of the caption lines; returns the folder."""
    target = APPLE_FLORES[code]
    clean, _ = build_flores(Path(flores_dir), target)
    folder = Path(out_dir) / f"en-{code}"
    write_set(folder / "flores.jsonl", clean)
    write_set(folder / "edacc-lines.jsonl", read_set(edacc_lines))
    return folder


def language_row(code: str, sets: dict[str, list[dict]], rows: list[dict], speed_rows: list[dict] | None = None,
                 disk_bytes: int | None = None, comet: dict | None = None, n_boot: int | None = None) -> dict:
    """One table row from score_pair: Apple's FLORES chrF with its CI, COMET if scored, and ms per caption line."""
    from .report import score_pair
    kw = {} if n_boot is None else {"n_boot": n_boot}
    s = score_pair(sets, rows, comet=comet or {}, speed_rows=speed_rows, **kw)
    flores = s["sets"].get("flores")
    e = flores["engines"][0] if flores and flores["engines"] else None
    sp = s["speed"][0]["speed"] if s["speed"] and s["speed"][0]["speed"] else {}
    return {"code": code, "name": NAMES.get(code, code), "chrf": e["chrf"] if e else math.nan,
            "ci": e["ci"] if e else (math.nan, math.nan), "n": flores["n"] if flores else 0,
            "comet": e["comet"][0] if e and e["comet"] else None,
            "median_ms": sp.get("median_ms"), "p95_ms": sp.get("p95_ms"),
            "untranslated": s["speed"][0]["checks"]["untranslated"] if s["speed"] else None,
            "disk_bytes": disk_bytes}


def _mb(b: int | None) -> str:
    return "–" if not b else f"{b / 1e6:.0f} MB"


def languages_table(rows: list[dict]) -> str:
    """rows: {code, name, chrf, ci, n, median_ms, p95_ms, disk_bytes} -> markdown, best chrF first."""
    out = ["| Language | Apple code | chrF | 95% CI | COMET | Median ms/line | p95 ms | Assets on disk |",
           "|---|---|---|---|---|---|---|---|"]
    for r in sorted(rows, key=lambda r: -r["chrf"] if not math.isnan(r["chrf"]) else math.inf):
        lo, hi = r["ci"]
        ms = "–" if r.get("median_ms") is None else f"{r['median_ms']:.0f}"
        p95 = "–" if r.get("p95_ms") is None else f"{r['p95_ms']:.0f}"
        comet = "–" if r.get("comet") is None else f"{r['comet']:.3f}"
        out.append(f"| {r['name']} | `{r['code']}` | {r['chrf']:.1f} | {lo:.1f} to {hi:.1f} | {comet} | {ms} | {p95} | "
                   f"{_mb(r.get('disk_bytes'))} |")
    return "\n".join(out) + "\n"
