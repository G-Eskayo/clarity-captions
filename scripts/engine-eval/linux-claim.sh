#!/usr/bin/env bash
# 2012 Mac mini: shared sherpa-onnx work queue (#145). Claims live on this box so both minis see one queue.
#   linux-claim.sh claim HOST FIRST LAST   -> prints the claimed shard number, or nothing when none is left
#   linux-claim.sh done K
set -euo pipefail
export PATH=/usr/bin:/bin
ROOT="$HOME/edacc-eval"
export PYTHONPATH="$ROOT/tool"
PY="$ROOT/venv/bin/python"
case "$1" in
  claim) exec "$PY" -m edacc_eval.cli claim --root "$ROOT/claims" --host "$2" --first "$3" --total "$4" ;;
  done)  exec "$PY" -m edacc_eval.cli claim-done --root "$ROOT/claims" --shard "$2" ;;
  *) echo "usage: linux-claim.sh claim HOST FIRST LAST | done K" >&2; exit 2 ;;
esac
