"""scripts/ensure-local.sh and its callers: data a cold store parked comes back before anything reads it, and a
machine with no cold store is never slowed or broken by the call. Real sh, a fake `marvin-cold`."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts" / "ensure-local.sh"
M4 = ["m4-compression", "m4-driver", "m4-language-driver", "m4-low-bit", "m4-shard-extras"]


def _tool(tmp_path: Path, rc: int) -> Path:
    t = tmp_path / "marvin-cold"
    t.write_text(f'#!/bin/sh\necho "$@" >> "{tmp_path}/calls"\nexit {rc}\n')
    t.chmod(0o755)
    return t


def _sh(script: str, env: dict) -> subprocess.CompletedProcess:
    return subprocess.run(["sh", "-c", script], capture_output=True, text=True, env={**os.environ, **env})


def test_no_cold_store_on_this_machine_is_a_no_op(tmp_path):
    r = _sh(f'. "{HELPER}"; ensure_local "$HOME/x"; echo rc=$?',
            {"HOME": str(tmp_path), "SEAL_COLD_ENSURE": str(tmp_path / "missing"), "PATH": "/usr/bin:/bin"})
    assert r.stdout.strip() == "rc=0"


def test_the_tool_is_asked_for_the_folder_and_its_failure_is_passed_on(tmp_path):
    tool = _tool(tmp_path, 3)
    r = _sh(f'. "{HELPER}"; ensure_local "$HOME/eval bench"; echo rc=$?',
            {"HOME": str(tmp_path), "SEAL_COLD_ENSURE": str(tool)})
    assert r.stdout.strip() == "rc=3"
    assert (tmp_path / "calls").read_text() == f"ensure {tmp_path}/eval bench --optional\n"


def test_fetch_asr_models_local_source_brings_the_model_back_first_and_stops_if_it_cannot(tmp_path):
    tool = _tool(tmp_path, 3)                         # e.g. the cold host is asleep
    r = subprocess.run(["sh", str(REPO / "scripts" / "fetch-asr-models.sh")], capture_output=True, text=True,
                       env={**os.environ, "HOME": str(tmp_path), "SEAL_COLD_ENSURE": str(tool),
                            "SEAL_ASR_MODEL": "hebrew", "SEAL_MODEL_SOURCE": "local",
                            "SEAL_MODEL_DEST": str(tmp_path / "dest")})
    assert r.returncode != 0
    assert (tmp_path / "calls").read_text() == \
        f"ensure {tmp_path}/edacc-eval/models/release/he-zipformer-pal4/HebrewZipformer --optional\n"
    assert "copying from" not in r.stdout and not (tmp_path / "dest").exists()


def test_fetch_asr_models_names_no_host_and_the_default_source_never_calls_the_cold_store():
    text = (REPO / "scripts" / "fetch-asr-models.sh").read_text()
    assert "gils-mac-mini" not in text
    github = text.split("    github)")[1].split(";;")[0]
    assert "ensure_local" not in github


def test_every_m4_script_ensures_its_work_folder_before_using_it():
    for name in M4:
        lines = (REPO / "scripts" / "engine-eval" / f"{name}.sh").read_text().splitlines()
        at = next(i for i, l in enumerate(lines) if 'ensure_local "$WORK"' in l)
        first_use = next(i for i, l in enumerate(lines) if "$WORK" in l and "WORK=" not in l)
        assert at == first_use, name
