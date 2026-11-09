#!/usr/bin/env python3
"""Cut CHiME-6 sessions into the #271 test windows, on the 2012 mini (stdlib only; run with python3 -I).

  python3 -I chime6-cut.py <CHiME6_eval.tar.gz> <windows.json> <out-dir> [--sessions S01,S21]

windows.json comes from speaker_eval.chime6.write_reference. For each window, channel 1 of its array is pulled out
of the tarball (only the files needed, one at a time) and the window's span written as <out-dir>/<window>.wav,
16 kHz mono 16-bit, as the corpus ships it. Idempotent: windows already cut are skipped.
"""
import json
import os
import sys
import tarfile
import wave


def main(argv):
    tar_path, windows_path, out = argv[1], argv[2], argv[3]
    sessions = None
    if "--sessions" in argv:
        sessions = set(argv[argv.index("--sessions") + 1].split(","))
    windows = [w for w in json.load(open(windows_path)) if sessions is None or w["session"] in sessions]
    os.makedirs(out, exist_ok=True)
    need = {}
    for w in windows:
        if not os.path.exists(os.path.join(out, w["recording"] + ".wav")):
            need.setdefault(f"{w['session']}_{w['array']}.CH1.wav", []).append(w)
    if not need:
        print("all windows cut")
        return 0
    tmp = os.path.join(out, ".src")
    os.makedirs(tmp, exist_ok=True)
    with tarfile.open(tar_path, "r:gz") as tar:
        for member in tar:
            name = os.path.basename(member.name)
            if name not in need or not member.isfile():
                continue
            src = os.path.join(tmp, name)
            with tar.extractfile(member) as fin, open(src, "wb") as fout:
                while chunk := fin.read(1 << 20):
                    fout.write(chunk)
            with wave.open(src) as w_in:
                sr, ch, width = w_in.getframerate(), w_in.getnchannels(), w_in.getsampwidth()
                if (sr, ch, width) != (16000, 1, 2):
                    print(f"{name}: unexpected format {sr} Hz {ch} ch {width * 8} bit", file=sys.stderr)
                    return 1
                for w in need.pop(name):
                    a, b = int(round(w["start"] * sr)), int(round(w["end"] * sr))
                    w_in.setpos(min(a, w_in.getnframes()))
                    frames = w_in.readframes(max(0, b - a))
                    part = os.path.join(out, w["recording"] + ".wav.part")
                    with wave.open(part, "wb") as w_out:
                        w_out.setnchannels(1); w_out.setsampwidth(2); w_out.setframerate(sr)
                        w_out.writeframes(frames)
                    os.replace(part, os.path.join(out, w["recording"] + ".wav"))
                    print(f"{w['recording']}: {name} {w['start']:.0f}-{w['end']:.0f} s")
            os.remove(src)
            if not need:
                break
    if need:
        print(f"not found in the tarball: {sorted(need)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
