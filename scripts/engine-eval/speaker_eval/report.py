"""Markdown for one model's scoreboard row (#271). The committed results page quotes from this."""
from __future__ import annotations


SETS = {"ami": "AMI test meetings (one far-field table microphone, Array1-01)",
        "chime6": "CHiME-6 eval dinner parties (one Kinect array per 10-minute window)"}


def _pct(x: float) -> str:
    return "n/a" if x != x else f"{100 * x:.1f}%"


def _ci(c: dict, fmt=_pct) -> str:
    lo, hi = c["ci95"]
    return f"**{fmt(c['value'])}** ({fmt(lo)}–{fmt(hi)})"


def _s(x: float) -> str:
    return "n/a" if x != x else f"{x:.2f} s"


def markdown(s: dict) -> str:
    lc = s.get("live_components", {})
    meta = s.get("meta", {})
    rows = [
        f"# Speaker scoreboard: {s['model']} on {SETS.get(s.get('set'), s.get('set'))}",
        "",
        f"{s['recordings']} test recordings, {s['audio_hours']:.1f} h. "
        "95% CIs: bootstrap over recordings, 1,000 resamples."
        + (" **Partial run: not for decisions.**" if s.get("missing") else ""),
        "",
    ]
    if meta:
        rows += ["Model: " + ", ".join(f"{k} {v}" for k, v in sorted(meta.items())), ""]
    rows += [
        "| Measure | Value (95% CI) |",
        "|---|---|",
        f"| **DER on screen** (live path: LiveDiarizer + SpeakerLabelSmoother, final labels) | {_ci(s['der_live'])} |",
        f"| of which missed / false alarm / confusion | {_pct(lc.get('miss', float('nan')))} / "
        f"{_pct(lc.get('fa', float('nan')))} / {_pct(lc.get('conf', float('nan')))} |",
        f"| DER, plain overlap (SpeakerAligner) | {_ci(s['der_raw'])} |",
        f"| DER, bare model segments | {_ci(s['der_bare'])} |",
        f"| Floor: every line given its true speaker | {_ci(s['der_floor'])} |",
        f"| Speaker-count error (mean abs, labels shown vs people) | {_ci(s['speaker_count_mae'], lambda x: 'n/a' if x != x else f'{x:.2f}')} |",
        f"| Recordings with the right speaker count | {s['speaker_count_exact']} of {s['recordings']} |",
        f"| One long monologue split across two labels | {_ci(s['monologue_split_rate'])} of {s['monologues']} monologues (≥20 s) |",
        f"| Line's first label, median / p90 after the line starts | {_ci(s['line_first_label_median_s'], _s)} / "
        f"{_ci(s['line_first_label_p90_s'], _s)} |",
        f"| Lines never labelled | {_pct(s['unlabeled_line_rate'])} |",
        f"| First label of the session, median / worst | {_s(s['session_first_label_s']['median'])} / "
        f"{_s(s['session_first_label_s']['max'])} |",
        f"| Speed | {s['speed_x_realtime']:.0f}x real time; per 85 ms buffer p95 worst {s['chunk_ms_p95_worst']:.1f} ms, "
        f"max {s['chunk_ms_max']:.0f} ms |",
        f"| Peak memory (process footprint, model load included) | median {s['peak_mb']['median']:.0f} MB, max {s['peak_mb']['max']:.0f} MB |",
        f"| Model load | median {s['load_s_median']:.2f} s |",
        f"| Repeat runs identical | {s['repeats_checked'] - len(s['repeats_differing'])} of {s['repeats_checked']} |",
        "",
        "| Recording | People | Shown | DER on screen | Bare model | Floor | Monologues split |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in s["per_recording"]:
        rows.append(f"| {r['recording']} | {r['ref_speakers']} | {r['shown_speakers']} | {_pct(r['der_live'])} | "
                    f"{_pct(r['der_bare'])} | {_pct(r['der_floor'])} | {r['split']} of {r['monologues']} |")
    return "\n".join(rows) + "\n"
