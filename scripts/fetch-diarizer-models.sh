#!/bin/sh
# Fetches the pre-compiled Sortformer speaker-diarization model (FluidAudio, ADR 0014) into the app's
# gitignored Resources/Models/ so it ships inside the app and first launch needs no network.
# Idempotent: files already present with the right size and sha256 are skipped.
# Precision must match SortformerConfig in LiveDiarizer.swift (fastV2_1 + fp16). For the smaller
# palettized model (~97 MB instead of ~241 MB) change PRECISION here AND the config there.
set -eu
REPO="FluidInference/diar-streaming-sortformer-coreml"
PRECISION="fp16"
NAME="Sortformer_v2.1.mlmodelc"
SUBDIR="v3/$PRECISION/$NAME"
DEST="$(cd "$(dirname "$0")/.." && pwd)/Apps/Spike/Resources/Models/$NAME"

mkdir -p "$DEST"
curl -sf "https://huggingface.co/api/models/$REPO/tree/main/$SUBDIR?recursive=true" -o "$DEST/../.tree.json"

python3 - "$DEST" "$SUBDIR" "$REPO" <<'PY'
import hashlib, json, os, subprocess, sys
dest, subdir, repo = sys.argv[1:4]
tree = json.load(open(os.path.join(dest, "..", ".tree.json")))
files = [x for x in tree if x["type"] == "file"]
if not files:
    sys.exit("No files listed for " + subdir + " -- repo layout changed?")

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

for x in files:
    rel = x["path"][len(subdir) + 1:]
    out = os.path.join(dest, rel)
    want = (x.get("lfs") or {}).get("oid")      # sha256, only reported for LFS files
    if os.path.exists(out) and os.path.getsize(out) == x["size"] and (not want or sha256(out) == want):
        continue
    os.makedirs(os.path.dirname(out), exist_ok=True)
    url = "https://huggingface.co/%s/resolve/main/%s" % (repo, x["path"])
    subprocess.run(["curl", "-sfL", "-o", out, url], check=True)
    if os.path.getsize(out) != x["size"]:
        sys.exit("Size mismatch for " + rel)
    if want and sha256(out) != want:
        sys.exit("Checksum mismatch for " + rel)
    print("fetched", rel)
print("OK:", len(files), "files verified in", dest)
PY
rm -f "$DEST/../.tree.json"
