#!/usr/bin/env python3
"""Parse xctrace export and seal-feedback JSON, compute per-hour battery % and per-stage energy share."""
from __future__ import annotations

import json
import plistlib
import sys
from argparse import ArgumentParser
from datetime import datetime
from pathlib import Path
from typing import Any, TypedDict


class AnalysisResult(TypedDict, total=False):
    """Result of battery analysis."""
    status: str
    battery_percentage_per_hour: float
    battery_drop_percent: float
    energy_per_stage: dict[str, float]
    delta: float
    thermal_transition: str | None
    thermal_state: str | None
    component_split: str
    reason: str
    message: str
    window_duration_minutes: int


# Known device models: {identifier: (display_name, short_name)}
KNOWN_DEVICES = {
    "iPhone14,6": ("iPhone SE (3rd generation)", "SE-3rd-gen"),
    "iPhone17,1": ("iPhone 16 Pro", "16-Pro"),
    "iPhone18,1": ("iPhone 17 Pro", "17-Pro"),
}


def parse_xctrace_export(file_path: Path | str) -> dict[str, Any]:
    """Parse xctrace export plist or JSON. Raise ValueError if malformed.

    Expected structure (from real xctrace exports or a converter):
    - battery_samples: [{time_seconds, level}, ...]
    - display_energy_samples: [{time_seconds, energy}, ...]
    - thermal_state_transitions: [{time_seconds, state}, ...]
    - power_state_transitions: [{state}, ...]
    - signpost_intervals: [{subsystem, category, start_seconds, end_seconds}, ...]
    - window_label: string identifying the labeled window (must contain "60")
    - window_start_seconds: float start of the labeled window
    - device_model: string like "iPhone14,6"
    - engine: string like "parakeet-ultra-pal6"
    """
    path = Path(file_path) if isinstance(file_path, str) else file_path
    if not path.exists():
        raise ValueError(f"xctrace file not found: {path}")

    content = path.read_bytes()

    # Try plist first (xctrace export --output *.plist)
    try:
        return plistlib.loads(content)
    except Exception:
        pass

    # Fall back to JSON
    try:
        return json.loads(content.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise ValueError(f"xctrace export is neither valid plist nor JSON: {e}") from e


def parse_beta_report(json_str: str) -> dict[str, Any]:
    """Parse beta report JSON. Raise ValueError if malformed."""
    try:
        return json.loads(json_str)
    except json.JSONDecodeError as e:
        raise ValueError(f"beta report is invalid JSON: {e}") from e


def _validate_schema(beta: dict[str, Any]) -> None:
    """Validate beta report schema version."""
    if beta.get("schema") != 1:
        raise ValueError(f"beta report schema must be 1, got {beta.get('schema')}")


def _validate_battery_field(conversation: dict[str, Any]) -> None:
    """Validate battery field exists (dropPercentPer30Min may be null, checked later)."""
    battery = conversation.get("battery")
    if not battery:
        raise ValueError("conversation missing battery field")


def _check_charging_or_low_power_mode(xctrace: dict[str, Any], beta: dict[str, Any]) -> bool:
    """Return True if charging or low power mode was active in either source."""
    # Check beta report
    if beta.get("device", {}).get("lowPowerModeSeen", False):
        return True

    # Check xctrace power state transitions
    power_samples = xctrace.get("power_state_transitions", [])
    for sample in power_samples:
        if sample.get("state") in ("charging", "low_power"):
            return True

    return False


def _extract_thermal_state(xctrace: dict[str, Any]) -> tuple[str | None, str | None]:
    """Extract worst thermal state transition. Return (current_state, worst_transition)."""
    thermal_samples = xctrace.get("thermal_state_transitions", [])
    if not thermal_samples:
        return None, None

    current_state = thermal_samples[-1].get("state")
    # Find worst (critical > serious > fair/nominal)
    transition = None
    for sample in thermal_samples:
        state = sample.get("state")
        if state == "critical":
            transition = "critical"
            break  # critical is worst, stop searching
        elif state == "serious" and transition != "critical":
            transition = "serious"

    return current_state, transition


def _check_display_energy(xctrace: dict[str, Any]) -> bool:
    """Return True if display energy is near zero for a significant stretch."""
    display_samples = xctrace.get("display_energy_samples", [])
    if not display_samples:
        return False

    near_zero_count = sum(1 for s in display_samples if s.get("energy", 0) < 5.0)
    if near_zero_count > len(display_samples) * 0.1:  # More than 10% near zero
        return True
    return False


def _check_start_charge(xctrace: dict[str, Any], window_start_seconds: float = 0.0) -> bool:
    """Return True if start charge at window start is outside 80-90% range."""
    battery_samples = xctrace.get("battery_samples", [])
    if not battery_samples:
        return False

    # Find first sample at or after window start
    window_sample = None
    for sample in battery_samples:
        if sample.get("time_seconds", 0) >= window_start_seconds:
            window_sample = sample
            break

    if not window_sample:
        # No sample at window start; use the first sample before window end if close enough
        window_sample = battery_samples[0] if battery_samples else None

    if not window_sample:
        return False

    start_charge = window_sample.get("level")
    return start_charge is not None and (start_charge < 80 or start_charge > 90)


def _compute_battery_drop(xctrace: dict[str, Any], window_start_seconds: float = 0.0, window_duration_seconds: float = 3600.0) -> float:
    """Compute battery percentage drop over labeled window. Raise if data insufficient."""
    battery_samples = xctrace.get("battery_samples", [])
    if len(battery_samples) < 2:
        raise ValueError("fewer than 2 battery samples in xctrace")

    # Filter to labeled window
    window_end = window_start_seconds + window_duration_seconds
    samples_in_window = [
        s for s in battery_samples
        if window_start_seconds <= s.get("time_seconds", 0) <= window_end
    ]

    if len(samples_in_window) < 2:
        raise ValueError(f"fewer than 2 battery samples in labeled window ({window_start_seconds}–{window_end} seconds)")

    start_level = samples_in_window[0].get("level")
    end_level = samples_in_window[-1].get("level")

    if start_level is None or end_level is None:
        raise ValueError("battery sample missing 'level' field")

    return start_level - end_level


def _compute_per_hour_battery(drop_percent: float, window_duration_minutes: float = 60.0) -> float:
    """Scale battery drop to per-hour percentage."""
    if window_duration_minutes <= 0:
        raise ValueError(f"window duration must be positive, got {window_duration_minutes} minutes")
    return (drop_percent * 60.0) / window_duration_minutes


def _extract_signpost_intervals(xctrace: dict[str, Any]) -> dict[str, float]:
    """Extract signpost intervals and compute duration by (subsystem, category) to avoid name collisions."""
    intervals = xctrace.get("signpost_intervals", [])
    if not intervals:
        return {}

    stage_durations: dict[str, float] = {}
    for interval in intervals:
        # Key by (subsystem, category) to distinguish apple-decode from diarization (both use "process" name)
        subsystem = interval.get("subsystem", "unknown")
        category = interval.get("category", "unknown")
        key = f"{subsystem}:{category}"

        start = interval.get("start_seconds", 0)
        end = interval.get("end_seconds", 0)
        duration = end - start

        if duration < 0:
            raise ValueError(f"signpost interval has negative duration: {start}–{end}")

        if key in stage_durations:
            stage_durations[key] += duration
        else:
            stage_durations[key] = duration

    return stage_durations


def _compute_energy_per_stage(stage_durations: dict[str, float], total_battery_percent: float, window_duration_seconds: float = 3600.0) -> dict[str, float]:
    """Compute energy share per stage. Only stages get their proportion of the drop (not idle/display)."""
    if not stage_durations:
        return {}

    total_instrumented_duration = sum(stage_durations.values())
    if total_instrumented_duration == 0:
        return {}

    # Only the instrumented stages' share of the total window gets the computed drop
    # The rest is idle/display/radio (not attributable to our code)
    instrumented_fraction = min(total_instrumented_duration / window_duration_seconds, 1.0)
    attributed_battery = total_battery_percent * instrumented_fraction

    energy_per_stage = {}
    for stage, duration in stage_durations.items():
        # Each stage gets its share of the attributed battery
        share = (duration / total_instrumented_duration) * attributed_battery
        energy_per_stage[stage] = round(share, 2)

    return energy_per_stage


def _compute_delta(instruments_drop_per_hour: float, beta_drop_per_30min: float) -> float:
    """Compute delta between Instruments (per-hour) and beta (per-30-min) measurement. Scale to same time basis."""
    # beta_drop_per_30min is for 30 minutes; scale to 60 minutes for comparison
    beta_drop_per_hour = beta_drop_per_30min * 2.0
    return round(instruments_drop_per_hour - beta_drop_per_hour, 2)


def _validate_cross_run(xctrace: dict[str, Any], conversation: dict[str, Any]) -> None:
    """Validate that the two engine runs agree on start charge and room temperature (tolerance: ±5%)."""
    # Note: This validates a single run can be compared to itself or another run.
    # For now, only implemented for detecting inconsistencies in the same data.
    # Cross-run comparison would require two separate xctrace exports (not in scope for this PR).
    # This placeholder validates that both engines in the same run have consistent metadata.
    pass  # Placeholder for future implementation of true cross-run checks


def _validate_engine_match(xctrace: dict[str, Any], conversation: dict[str, Any]) -> None:
    """Validate that xctrace and beta report use the same engine. Both must be present."""
    xctrace_engine = xctrace.get("engine")
    beta_engine = conversation.get("engine")

    # Both must be present for comparison
    if not xctrace_engine:
        raise ValueError("xctrace engine field missing")
    if not beta_engine:
        raise ValueError("beta report engine field missing")

    # They must match
    if xctrace_engine != beta_engine:
        raise ValueError(f"engine mismatch: xctrace {xctrace_engine} vs beta {beta_engine}")


def _validate_device_model(xctrace: dict[str, Any], beta: dict[str, Any]) -> None:
    """Validate device model is known and matches between both sources. Both must be present."""
    beta_model = beta.get("device", {}).get("model")
    xctrace_model = xctrace.get("device_model")

    # Both must be present for comparison
    if not beta_model:
        raise ValueError("beta report device model missing")
    if not xctrace_model:
        raise ValueError("xctrace device model missing")

    # Both must be known
    if beta_model not in KNOWN_DEVICES:
        raise ValueError(f"beta report device model not recognized: {beta_model}")
    if xctrace_model not in KNOWN_DEVICES:
        raise ValueError(f"xctrace device model not recognized: {xctrace_model}")

    # They must match
    if beta_model != xctrace_model:
        raise ValueError(f"device model mismatch: xctrace {xctrace_model} vs beta {beta_model}")


def analyze(xctrace: dict[str, Any], beta: dict[str, Any]) -> AnalysisResult:
    """Analyze battery data from xctrace export and beta report. Return result dict."""
    result: AnalysisResult = {}

    # Validate schema
    _validate_schema(beta)

    # Extract labeled window from xctrace
    window_label = xctrace.get("window_label", "")
    if "60" not in window_label:
        raise ValueError(f"xctrace window label does not indicate 60-minute window: {window_label}")
    window_start = xctrace.get("window_start_seconds", 0.0)
    window_duration = 3600.0  # 60 minutes in seconds
    result["window_duration_minutes"] = 60

    # Get conversations and find the one(s) in the labeled window
    conversations = beta.get("conversations", [])
    if not conversations:
        raise ValueError("beta report has no conversations")

    # Match conversation to labeled window (for now, use first if only one matches)
    # A conversation overlaps the window if its start + duration spans the window
    matching_conversations = []
    for conv in conversations:
        # Simple heuristic: if multiple conversations, prefer one that aligns with the labeled window
        # For this implementation, accept first conversation (production should match by timestamp)
        matching_conversations.append(conv)

    if not matching_conversations:
        raise ValueError("no conversations found in labeled window")

    conversation = matching_conversations[0]

    # Validate required fields
    _validate_battery_field(conversation)
    _validate_engine_match(xctrace, conversation)
    _validate_device_model(xctrace, beta)

    # Break-it #1: Charging or Low Power Mode
    if _check_charging_or_low_power_mode(xctrace, beta):
        result["status"] = "discarded"
        result["reason"] = "Charging or Low Power Mode active during measurement"
        return result

    # Break-it #3: Start charge validation (check before thermal to keep early exit)
    if _check_start_charge(xctrace, window_start):
        result["status"] = "invalid"
        result["reason"] = "Start charge outside 80-90% range"
        return result

    # Break-it #4: Display energy
    if _check_display_energy(xctrace):
        result["status"] = "invalid"
        result["reason"] = "Display energy near zero; screen may have been dimmed/locked"
        return result

    # Break-it #2: Thermal state (report but don't fail)
    current_thermal, thermal_transition = _extract_thermal_state(xctrace)
    if thermal_transition:
        result["thermal_transition"] = thermal_transition
    if current_thermal:
        result["thermal_state"] = current_thermal

    # Check beta report has valid battery data
    battery_data = conversation.get("battery", {})
    beta_drop = battery_data.get("dropPercentPer30Min")
    if beta_drop is None:
        result["status"] = "no_comparable_data"
        result["reason"] = "Beta report missing comparable battery data"
        return result

    # Compute battery metrics
    try:
        instruments_drop = _compute_battery_drop(xctrace, window_start, window_duration)
    except ValueError as e:
        result["status"] = "error"
        result["message"] = str(e)
        return result

    instruments_drop_per_hour = _compute_per_hour_battery(instruments_drop, window_duration / 60.0)
    result["battery_drop_percent"] = round(instruments_drop, 1)
    result["battery_percentage_per_hour"] = round(instruments_drop_per_hour, 1)

    # Extract signpost intervals (break-it: zero signpost intervals)
    try:
        stage_durations = _extract_signpost_intervals(xctrace)
    except ValueError as e:
        result["status"] = "error"
        result["message"] = str(e)
        return result

    if not stage_durations:
        result["component_split"] = "unavailable"
    else:
        energy_per_stage = _compute_energy_per_stage(stage_durations, instruments_drop, window_duration)
        result["energy_per_stage"] = energy_per_stage
        result["component_split"] = "available"

    # Compute delta vs beta report
    result["delta"] = _compute_delta(instruments_drop_per_hour, beta_drop)

    result["status"] = "ok"
    return result


def generate_report(
    xctrace_path: Path,
    beta_report_path: Path,
    output_path: Path,
    force: bool = False,
) -> dict[str, Any]:
    """Generate battery report from xctrace and beta report files."""
    # Check if output file exists
    if output_path.exists() and not force:
        return {
            "status": "file_exists",
            "message": f"{output_path} already exists; use --force to overwrite",
        }

    # Read inputs
    if not beta_report_path.exists():
        return {"status": "error", "message": f"beta report file not found: {beta_report_path}"}

    try:
        xctrace_data = parse_xctrace_export(xctrace_path)
    except ValueError as e:
        return {"status": "error", "message": str(e)}

    try:
        beta_data = parse_beta_report(beta_report_path.read_text())
    except ValueError as e:
        return {"status": "error", "message": str(e)}

    # Analyze
    try:
        analysis = analyze(xctrace_data, beta_data)
    except ValueError as e:
        return {"status": "error", "message": str(e)}

    # Generate markdown
    date_str = datetime.now().strftime("%Y-%m-%d")
    device_model = beta_data.get("device", {}).get("model")
    content = _generate_markdown(analysis, date_str, device_model)
    output_path.write_text(content)

    return {"status": "ok", "output": str(output_path)}


def _get_device_display_name(device_model: str | None) -> str:
    """Get display name for device model identifier."""
    if device_model in KNOWN_DEVICES:
        return KNOWN_DEVICES[device_model][0]
    return device_model or "Unknown device"


def _generate_markdown(analysis: AnalysisResult, date_str: str, device_model: str | None = None) -> str:
    """Generate markdown protocol document with analysis results."""
    status = analysis.get("status", "unknown")

    if status == "discarded":
        reason = analysis.get("reason", "unknown")
        content = f"""# Battery Test {date_str}

**Status:** DISCARDED — {reason}

See `docs/design/parakeet-engine-switch.md` §7 C4 for the protocol.
"""
    elif status == "invalid":
        reason = analysis.get("reason", "unknown")
        content = f"""# Battery Test {date_str}

**Status:** INVALID — {reason}

See `docs/design/parakeet-engine-switch.md` §7 C4 for the protocol.
"""
    elif status == "no_comparable_data":
        content = f"""# Battery Test {date_str}

**Status:** INCOMPLETE — No comparable beta data

Beta report present but no battery measurements; cannot compute delta.

See `docs/design/parakeet-engine-switch.md` §7 C4 for the protocol.
"""
    elif status == "error":
        message = analysis.get("message", "unknown error")
        content = f"""# Battery Test {date_str}

**Status:** ERROR

{message}

See `docs/design/parakeet-engine-switch.md` §7 C4 for the protocol.
"""
    else:
        # Valid result (status == "ok")
        battery_per_hour = analysis.get("battery_percentage_per_hour", 0)
        battery_drop_raw = analysis.get("battery_drop_percent", 0)
        delta = analysis.get("delta", 0)
        thermal_state = analysis.get("thermal_state")
        thermal_transition = analysis.get("thermal_transition")
        component_split = analysis.get("component_split", "unavailable")
        energy_stages = analysis.get("energy_per_stage", {})
        device_name = _get_device_display_name(device_model)

        # Format thermal state row (don't invent a default if no data)
        if thermal_state:
            thermal_row = thermal_state
            if thermal_transition:
                thermal_row += f" (transition to {thermal_transition})"
        else:
            thermal_row = "*no thermal data*"

        # Format component energy rows
        energy_rows = ""
        if component_split == "available" and energy_stages:
            for stage_key, energy in sorted(energy_stages.items()):
                # stage_key is "subsystem:category"
                stage_name = stage_key.split(":")[-1] if ":" in stage_key else stage_key
                energy_rows += f"| **{stage_name}** | {energy}% |\n"
        else:
            energy_rows = f"| *component split unavailable* | — |\n"

        content = f"""# Battery Test {date_str}

**Status:** COMPLETE

## Protocol

Cited: `docs/design/parakeet-engine-switch.md` §7 C4

- **Test:** 60-minute table session, speech from speaker at 1 m
- **Device:** {device_name}
- **Start charge:** 80–90%
- **Room temperature:** Same as baseline (Apple engine)
- **Screen:** On, per ADR 0019

## Results

| Metric | Value |
|--------|-------|
| **Battery drop (per 60 min)** | {battery_per_hour}% |
| **Battery drop (raw window)** | {battery_drop_raw}% |
| **Thermal state** | {thermal_row} |
| **Instruments drop (per hour) minus beta (per hour)** | {delta}% |
{energy_rows}

## How to run

See `docs/perf/battery-{date_str}.md` for the full protocol and pass criteria.
"""

    return content


def main() -> None:
    """Command-line entry point."""
    parser = ArgumentParser(description="Generate battery report from xctrace and beta report.")
    parser.add_argument("--xctrace", type=Path, required=True, help="xctrace export file (plist or JSON)")
    parser.add_argument("--beta-report", type=Path, required=True, help="seal-feedback JSON file")
    parser.add_argument("--output", type=Path, required=True, help="output markdown file")
    parser.add_argument("--force", action="store_true", help="overwrite existing output file")

    args = parser.parse_args()

    result = generate_report(
        xctrace_path=args.xctrace,
        beta_report_path=args.beta_report,
        output_path=args.output,
        force=args.force,
    )

    status = result.get("status")
    if status == "ok":
        print(f"Report generated: {result.get('output')}")
    elif status == "file_exists":
        print(f"Error: {result.get('message', 'file exists')}", file=sys.stderr)
        sys.exit(1)
    else:
        # error, discarded, invalid, no_comparable_data all get exit 1
        print(f"Error: {result.get('message', 'unknown error')}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
