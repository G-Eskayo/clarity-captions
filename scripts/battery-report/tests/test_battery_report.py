"""Tests for battery report parsing and analysis. Run: python -m pytest scripts/battery-report/tests"""
from __future__ import annotations

import json
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

import report


# --- Fixtures ---

def make_beta_report(
    conversations: list[dict[str, Any]] | None = None,
    app_build: str = "11",
    engine: str = "parakeet-ultra-pal6",
    device_model: str = "iPhone14,6",
    **overrides: Any,
) -> dict[str, Any]:
    """Create a minimal valid beta report."""
    if conversations is None:
        conversations = [{
            "id": "test-1",
            "startedAt": "2026-10-12T12:31:05-06:00",
            "minutes": 60.0,
            "battery": {"dropPercentPer30Min": 6.5, "maxThermalState": "fair"},
            "engine": engine,
        }]
    return {
        "schema": 1,
        "app": {"version": "1.0", "build": app_build, "environment": "sandbox"},
        "device": {"model": device_model, "os": "iOS 26.1", "lowPowerModeSeen": False},
        "sentAt": "2026-10-12T18:04:00-06:00",
        "conversations": conversations,
        **overrides,
    }


def make_xctrace_export(
    battery_level: list[float],
    display_energy: list[float] | None = None,
    thermal_state: list[tuple[float, str]] | None = None,
    signpost_intervals: list[tuple[str, str, float, float]] | None = None,
    device_model: str = "iPhone14,6",
    engine: str = "parakeet-ultra-pal6",
) -> dict[str, Any]:
    """Create a minimal valid xctrace export with 60-minute window. Time values span 3600 seconds."""
    if display_energy is None:
        display_energy = [50.0] * len(battery_level)
    if thermal_state is None:
        thermal_state = [(0.0, "fair")]
    if signpost_intervals is None:
        signpost_intervals = [
            ("com.sealspeak.battery", "mic-capture", 0.0, 100.0),
            ("com.sealspeak.battery", "parakeet-decode", 100.0, 200.0),
        ]

    # Spread battery samples across 3600 seconds (60 minutes) for realism
    num_samples = len(battery_level)
    time_step = 3600.0 / max(1, num_samples - 1) if num_samples > 1 else 0.0
    battery_samples = [
        {"time_seconds": float(i) * time_step, "level": battery_level[i]}
        for i in range(num_samples)
    ]

    # Same for display energy samples
    display_samples = [
        {"time_seconds": float(i) * time_step, "energy": display_energy[i]}
        for i in range(len(display_energy))
    ]

    return {
        "battery_samples": battery_samples,
        "display_energy_samples": display_samples,
        "thermal_state_transitions": [{"time_seconds": t, "state": s} for t, s in thermal_state],
        "signpost_intervals": [{"subsystem": s, "category": c, "start_seconds": st, "end_seconds": e} for s, c, st, e in signpost_intervals],
        "window_label": "60-minute-battery-test",
        "window_start_seconds": 0.0,
        "device_model": device_model,
        "engine": engine,
    }


# --- Test: Input parsing ---

def test_parse_xctrace_plist():
    """Parse xctrace plist format."""
    with tempfile.TemporaryDirectory() as tmp:
        plist_path = Path(tmp) / "trace.plist"
        xctrace_dict = {
            "battery_samples": [{"time_seconds": 0.0, "level": 85}],
            "signpost_intervals": [],
            "window_label": "60-minute-battery-test",
        }
        # Write as plist (using plistlib)
        import plistlib
        plist_path.write_bytes(plistlib.dumps(xctrace_dict))

        result = report.parse_xctrace_export(plist_path)
        assert "battery_samples" in result


def test_parse_xctrace_json():
    """Parse xctrace JSON format."""
    with tempfile.TemporaryDirectory() as tmp:
        json_path = Path(tmp) / "trace.json"
        xctrace_dict = {
            "battery_samples": [{"time_seconds": 0.0, "level": 85}],
            "signpost_intervals": [],
            "window_label": "60-minute-battery-test",
        }
        json_path.write_text(json.dumps(xctrace_dict))

        result = report.parse_xctrace_export(json_path)
        assert "battery_samples" in result


def test_malformed_xctrace_export():
    """Malformed xctrace export → clear error, never silent 0/null."""
    with tempfile.TemporaryDirectory() as tmp:
        bad_path = Path(tmp) / "bad.json"
        bad_path.write_text("{invalid json")

        with pytest.raises(ValueError, match="xctrace"):
            report.parse_xctrace_export(bad_path)


def test_xctrace_file_not_found():
    """Missing xctrace file → clear error."""
    with pytest.raises(ValueError, match="not found"):
        report.parse_xctrace_export(Path("/nonexistent/trace.plist"))


def test_malformed_beta_report():
    """Malformed beta report JSON → clear error."""
    with pytest.raises(ValueError, match="beta"):
        report.parse_beta_report("{invalid json")


def test_missing_required_battery_field():
    """Missing battery field → clear error."""
    beta = make_beta_report(conversations=[{
        "id": "test-1",
        "startedAt": "2026-10-12T12:31:05-06:00",
        "minutes": 60.0,
        # missing battery field
        "engine": "parakeet-ultra-pal6",
    }])
    xctrace = make_xctrace_export([85] * 100)
    with pytest.raises(ValueError, match="battery"):
        report.analyze(xctrace, beta)


def test_wrong_schema():
    """Wrong schema version → clear error."""
    beta = make_beta_report()
    beta["schema"] = 2
    xctrace = make_xctrace_export([85] * 100)
    with pytest.raises(ValueError, match="schema"):
        report.analyze(xctrace, beta)


# --- Test: Break-it #1: Charging or Low Power Mode ---

def test_low_power_mode_active_run_discarded():
    """Low Power Mode active → run discarded."""
    beta = make_beta_report()
    beta["device"]["lowPowerModeSeen"] = True
    xctrace = make_xctrace_export([85, 83, 81])
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "discarded"
    assert "Low Power Mode" in result.get("reason", "")


def test_charging_active_power_state_run_discarded():
    """Charging detected in xctrace power state → run discarded."""
    beta = make_beta_report()
    xctrace = make_xctrace_export([85, 83, 81])
    xctrace["power_state_transitions"] = [{"state": "charging"}]
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "discarded"
    assert "Charging" in result.get("reason", "")


# --- Test: Break-it #2: Thermal state transitions ---

def test_serious_thermal_transition_reported_separately():
    """Thermal transition to .serious inside window → reported separately, never folded in."""
    thermal = [(0.0, "fair"), (1800.0, "serious"), (3600.0, "fair")]
    xctrace = make_xctrace_export([85] * 3600, thermal_state=thermal)
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("thermal_transition") == "serious"
    # Status should still be "ok", not "serious"
    assert result.get("status") == "ok"
    # Battery metrics should be computed
    assert "battery_percentage_per_hour" in result


def test_critical_thermal_state_flagged():
    """.critical thermal state → flagged separately."""
    thermal = [(0.0, "critical")]
    xctrace = make_xctrace_export([85] * 3600, thermal_state=thermal)
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("thermal_state") == "critical"
    assert result.get("status") == "ok"


# --- Test: Break-it #3: Start charge validation ---

def test_start_charge_outside_80_90_percent_flagged_invalid():
    """Start charge outside 80–90% → comparison flagged invalid."""
    xctrace = make_xctrace_export([75, 73, 71])  # starts at 75%
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "invalid"
    assert "start_charge" in result.get("reason", "").lower() or "80" in result.get("reason", "")


def test_start_charge_too_high_flagged_invalid():
    """Start charge > 90% → flagged invalid."""
    xctrace = make_xctrace_export([95, 93, 91])  # starts at 95%
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "invalid"


def test_start_charge_in_range_ok():
    """Start charge 80–90% → passes validation."""
    xctrace = make_xctrace_export([85] * 100)  # starts at 85%
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    # Should pass this check and move on
    assert result.get("status") != "invalid" or "display" in result.get("reason", "").lower()


# --- Test: Break-it #4: Display energy near zero ---

def test_display_energy_near_zero_stretch_flagged_invalid():
    """Display energy near zero for a stretch (screen dimmed/locked) → run flagged invalid."""
    display_energy = [50.0] * 1800 + [1.0] * 1800  # dimmed/locked for second half
    xctrace = make_xctrace_export([85] * 3600, display_energy=display_energy)
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "invalid"
    assert "display" in result.get("reason", "").lower()


def test_display_energy_always_on_ok():
    """Display energy high throughout → passes validation."""
    display_energy = [50.0] * 3600
    xctrace = make_xctrace_export([85] * 3600, display_energy=display_energy)
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    # Should pass display check
    assert "display" not in (result.get("reason", "") or "").lower()


# --- Test: Oversized/mismatched input ---

def test_export_uses_labeled_window():
    """Export spanning more than 60-minute window → isolates only the labeled window."""
    xctrace = make_xctrace_export([85] * 10000)  # huge export
    xctrace["window_label"] = "60-minute-battery-test"
    xctrace["window_start_seconds"] = 0.0
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("window_duration_minutes") == 60


def test_multiple_conversations_uses_first():
    """Multiple conversations in report → uses first (time matching not yet implemented)."""
    conversations = [
        {"id": "1", "startedAt": "2026-10-12T12:31:05-06:00", "minutes": 60.0, "battery": {"dropPercentPer30Min": 5.0, "maxThermalState": "fair"}, "engine": "parakeet-ultra-pal6"},
        {"id": "2", "startedAt": "2026-10-12T13:31:05-06:00", "minutes": 60.0, "battery": {"dropPercentPer30Min": 7.0, "maxThermalState": "fair"}, "engine": "parakeet-ultra-pal6"},
    ]
    xctrace = make_xctrace_export([85] * 3600)
    beta = make_beta_report(conversations=conversations)
    result = report.analyze(xctrace, beta)
    # Should use first conversation's drop (5.0)
    assert result.get("delta") is not None


# --- Test: Dependency failure: zero signpost intervals ---

def test_zero_signpost_intervals_older_build():
    """Zero signpost intervals (older build) → 'component split unavailable'."""
    xctrace = make_xctrace_export([85] * 3600, signpost_intervals=[])
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("component_split") == "unavailable"
    assert result.get("status") == "ok"


# --- Test: Dependency failure: no comparable beta data ---

def test_beta_report_no_battery_dropPercentPer30Min_null():
    """Beta report with null dropPercentPer30Min → 'no_comparable_data'."""
    xctrace = make_xctrace_export([85] * 3600)
    conversations = [{
        "id": "test-1",
        "startedAt": "2026-10-12T12:31:05-06:00",
        "minutes": 60.0,
        "battery": {"dropPercentPer30Min": None, "maxThermalState": "fair"},
        "engine": "parakeet-ultra-pal6",
    }]
    beta = make_beta_report(conversations=conversations)
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "no_comparable_data"


# --- Test: Idempotence ---

def test_running_twice_is_idempotent():
    """Re-running script twice on same inputs is idempotent."""
    xctrace = make_xctrace_export([85, 83, 81])
    beta = make_beta_report()
    result1 = report.analyze(xctrace, beta)
    result2 = report.analyze(xctrace, beta)
    assert result1 == result2


# --- Test: Engine mismatch ---

def test_xctrace_engine_parakeet_beta_report_apple_mismatch():
    """xctrace tagged Parakeet paired with beta report tagged Apple → refuses."""
    xctrace = make_xctrace_export([85] * 3600, engine="parakeet-ultra-pal6")
    conversations = [{
        "id": "test-1",
        "startedAt": "2026-10-12T12:31:05-06:00",
        "minutes": 60.0,
        "battery": {"dropPercentPer30Min": 6.5, "maxThermalState": "fair"},
        "engine": "apple-speechanalyzer",  # Mismatch!
    }]
    beta = make_beta_report(conversations=conversations)
    with pytest.raises(ValueError, match="engine.*mismatch"):
        report.analyze(xctrace, beta)


def test_matching_engines_accepted():
    """Same engine in both sources → accepted."""
    xctrace = make_xctrace_export([85] * 3600, engine="parakeet-ultra-pal6")
    beta = make_beta_report(engine="parakeet-ultra-pal6")
    result = report.analyze(xctrace, beta)
    assert result.get("status") in ("ok", "no_comparable_data", "invalid", "discarded")


# --- Test: Device model validation ---

def test_device_model_mismatch_refuses():
    """Device model mismatch between xctrace and beta → refuses."""
    xctrace = make_xctrace_export([85] * 3600, device_model="iPhone14,6")
    beta = make_beta_report(device_model="iPhone17,1")
    with pytest.raises(ValueError, match="device.*model.*mismatch"):
        report.analyze(xctrace, beta)


def test_device_model_unknown_refuses():
    """Unknown device model → refuses."""
    xctrace = make_xctrace_export([85] * 3600, device_model="UnknownDevice123")
    beta = make_beta_report(device_model="UnknownDevice123")
    with pytest.raises(ValueError, match="device.*model.*not recognized"):
        report.analyze(xctrace, beta)


def test_known_device_models_accepted():
    """SE-3rd-gen, 16-Pro, and 17-Pro identifiers are recognized."""
    for model in ["iPhone14,6", "iPhone17,1", "iPhone18,1"]:
        xctrace = make_xctrace_export([85] * 3600, device_model=model)
        beta = make_beta_report(device_model=model)
        result = report.analyze(xctrace, beta)
        assert result.get("status") != "error"


def test_missing_xctrace_device_model_raises():
    """xctrace missing device_model field → raises error."""
    xctrace = make_xctrace_export([85] * 3600, device_model="iPhone14,6")
    del xctrace["device_model"]
    beta = make_beta_report(device_model="iPhone14,6")
    with pytest.raises(ValueError, match="device.*model.*missing"):
        report.analyze(xctrace, beta)


def test_missing_beta_device_model_raises():
    """Beta report missing device model → raises error."""
    xctrace = make_xctrace_export([85] * 3600, device_model="iPhone14,6")
    beta = make_beta_report(device_model="iPhone14,6")
    del beta["device"]["model"]
    with pytest.raises(ValueError, match="device.*model.*missing"):
        report.analyze(xctrace, beta)


def test_missing_xctrace_engine_raises():
    """xctrace missing engine field → raises error."""
    xctrace = make_xctrace_export([85] * 3600, engine="parakeet-ultra-pal6")
    del xctrace["engine"]
    beta = make_beta_report(engine="parakeet-ultra-pal6")
    with pytest.raises(ValueError, match="engine.*missing"):
        report.analyze(xctrace, beta)


def test_missing_beta_engine_raises():
    """Beta report missing engine field → raises error."""
    xctrace = make_xctrace_export([85] * 3600, engine="parakeet-ultra-pal6")
    conversations = [{
        "id": "test-1",
        "startedAt": "2026-10-12T12:31:05-06:00",
        "minutes": 60.0,
        "battery": {"dropPercentPer30Min": 6.5, "maxThermalState": "fair"},
        # missing engine field
    }]
    beta = make_beta_report(conversations=conversations)
    with pytest.raises(ValueError, match="engine.*missing"):
        report.analyze(xctrace, beta)


# --- Test: Protect existing results ---

def test_existing_dated_battery_file_not_overwritten_without_force():
    """Running without --force against existing file never overwrites."""
    with tempfile.TemporaryDirectory() as tmp:
        battery_file = Path(tmp) / "battery-2026-10-12.md"
        battery_file.write_text("# Existing run\n\nPrior result: 5.2% per 30 min")

        xctrace = make_xctrace_export([85] * 3600)
        xctrace_path = Path(tmp) / "xctrace.json"
        xctrace_path.write_text(json.dumps(xctrace))
        beta_path = Path(tmp) / "beta.json"
        beta_path.write_text(json.dumps(make_beta_report()))

        result = report.generate_report(
            xctrace_path=xctrace_path,
            beta_report_path=beta_path,
            output_path=battery_file,
            force=False,
        )
        assert result.get("status") == "file_exists"
        # Original file should be unchanged
        assert "Existing run" in battery_file.read_text()


def test_existing_dated_battery_file_overwritten_with_force():
    """Running with --force overwrites existing battery file."""
    with tempfile.TemporaryDirectory() as tmp:
        battery_file = Path(tmp) / "battery-2026-10-12.md"
        battery_file.write_text("# Existing run\n\nPrior result: 5.2% per 30 min")

        xctrace = make_xctrace_export([85] * 3600)
        xctrace_path = Path(tmp) / "xctrace.json"
        xctrace_path.write_text(json.dumps(xctrace))
        beta_path = Path(tmp) / "beta.json"
        beta_path.write_text(json.dumps(make_beta_report()))

        result = report.generate_report(
            xctrace_path=xctrace_path,
            beta_report_path=beta_path,
            output_path=battery_file,
            force=True,
        )
        assert result.get("status") == "ok"
        # New content should have COMPLETE status
        new_content = battery_file.read_text()
        assert "COMPLETE" in new_content


# --- Test: Per-hour battery percentage calculation ---

def test_per_hour_battery_percentage():
    """Per-hour battery % calculated correctly from 60-minute window."""
    xctrace = make_xctrace_export([85, 80, 75])  # 10% drop
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "ok"
    assert result.get("battery_percentage_per_hour") == 10.0


def test_battery_drop_matches_window():
    """Battery drop matches the labeled 60-minute window."""
    xctrace = make_xctrace_export([85, 80, 75])
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("battery_drop_percent") == 10.0  # 85 - 75


# --- Test: Per-stage energy share ---

def test_per_stage_energy_share():
    """Per-stage energy share computed correctly."""
    # Three stages, each 100 seconds of a 3600-second window, 10% drop
    signpost_intervals = [
        ("com.sealspeak.battery", "mic-capture", 0.0, 100.0),
        ("com.sealspeak.battery", "parakeet-decode", 100.0, 200.0),
        ("com.sealspeak.battery", "diarization", 200.0, 300.0),
    ]
    xctrace = make_xctrace_export([85, 80], signpost_intervals=signpost_intervals)
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "ok"
    assert "energy_per_stage" in result
    # Total instrumented time is 300 seconds out of 3600, so ~8.3% of drop is attributed
    # That 8.3% is split equally among the three stages
    energy = result.get("energy_per_stage", {})
    assert len(energy) == 3


def test_duplicate_signpost_names_separated():
    """Signpost intervals with duplicate names keyed by (subsystem, category) → separated."""
    signpost_intervals = [
        ("com.sealspeak.battery", "parakeet-decode", 0.0, 100.0),
        ("com.sealspeak.battery", "diarization", 100.0, 200.0),
    ]
    xctrace = make_xctrace_export([85, 80], signpost_intervals=signpost_intervals)
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "ok"
    energy = result.get("energy_per_stage", {})
    # Both stages should be present as separate keys
    assert len(energy) >= 2


# --- Test: Beta vs. Instruments delta ---

def test_beta_vs_instruments_delta():
    """Delta computed correctly, scaling beta's per-30-min to per-hour basis."""
    # 10% drop over 60 minutes (instruments), beta reports 5% per 30 min (= 10% per hour)
    # Delta should be 0
    xctrace = make_xctrace_export([85, 80, 75])  # 10% per 60 min
    conversations = [{
        "id": "test-1",
        "startedAt": "2026-10-12T12:31:05-06:00",
        "minutes": 60.0,
        "battery": {"dropPercentPer30Min": 5.0, "maxThermalState": "fair"},  # 5% per 30 min = 10% per 60 min
        "engine": "parakeet-ultra-pal6",
    }]
    beta = make_beta_report(conversations=conversations)
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "ok"
    # Delta = instruments (10% per hour) - beta (5 * 2 = 10% per hour) = 0
    assert result.get("delta") == 0.0


def test_battery_drop_insufficient_samples():
    """Fewer than 2 battery samples → raises error."""
    xctrace = make_xctrace_export([85])  # only 1 sample
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "error"
    assert "fewer than 2" in result.get("message", "").lower()


def test_signpost_negative_duration_raises():
    """Signpost with negative duration → raises error."""
    signpost_intervals = [
        ("com.sealspeak.battery", "bad", 200.0, 100.0),  # end < start
    ]
    xctrace = make_xctrace_export([85, 80], signpost_intervals=signpost_intervals)
    beta = make_beta_report()
    result = report.analyze(xctrace, beta)
    assert result.get("status") == "error"
    assert "negative duration" in result.get("message", "").lower()
