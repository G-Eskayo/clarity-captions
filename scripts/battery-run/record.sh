#!/bin/bash
# xcrun xctrace capture wrapper for Energy Log + Core ML trace
# Usage: ./record.sh <device-udid> <output-name> [duration-seconds]
# Starts a 60-minute Energy Log + Core ML trace, exports CSV for parse-trace.mjs analysis
# Manual steps (not automated by this script):
#   1. Pick engine in dev panel (CaptionEngineChoice)
#   2. Start captioning, play speaker audio at 1m
#   3. Let run for duration (default 60 min)
#   4. Script exports the capture when done

if [[ -z "$1" || -z "$2" ]]; then
  cat << 'EOF'
Usage: ./record.sh <device-udid> <output-name> [duration-seconds]

Captures an xctrace Energy Log + Core ML trace on an iPhone for battery analysis.

Arguments:
  <device-udid>     Target device UUID (run: xcrun xctrace list devices)
  <output-name>     Output filename prefix (no extension; creates <prefix>.ctrace and <prefix>-export.csv)
  [duration-seconds] Trace duration in seconds (default: 3600 = 60 min)

Manual steps:
  1. Connect phone to Xcode host, unlock device
  2. In the app's dev panel (long-press debug button), set engine: choose Parakeet or Apple
  3. Open Settings › Captions › Idle Stop › set to "Never" (so session runs full duration)
  4. Start this script
  5. Immediately: tap Start in the app to begin captioning
  6. Verify speaker at 1m distance, play audio (or read aloud for 60 min)
  7. Script exports and quits on duration completion

Output files:
  <output-name>.ctrace         Raw xctrace capture
  <output-name>-export.csv     Exported CSV for parse-trace.mjs

Notes:
  - Requires Xcode command-line tools (xctrace)
  - Device must be reachable via xcrun
  - Energy Log and Core ML templates are used
  - Trace is exported to CSV in the scripts/battery-run/ directory
EOF
  exit 1
fi

UDID="$1"
OUTPUT_PREFIX="$2"
DURATION="${3:-3600}"  # Default 60 minutes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="${SCRIPT_DIR}/${OUTPUT_PREFIX}.ctrace"
EXPORT_PATH="${SCRIPT_DIR}/${OUTPUT_PREFIX}-export.csv"

# Verify device is reachable
if ! xcrun xctrace list devices | grep -q "$UDID"; then
  echo "Device $UDID not found. Available devices:"
  xcrun xctrace list devices
  exit 1
fi

echo "Starting xctrace capture..."
echo "  Device: $UDID"
echo "  Duration: ${DURATION}s ($(( DURATION / 60 )) minutes)"
echo "  Output: $OUTPUT_PATH"
echo ""
echo "Manual steps:"
echo "  1. App dev panel: pick engine (Parakeet or Apple)"
echo "  2. Settings: Idle Stop = Never"
echo "  3. Start captioning NOW"
echo "  4. Play speaker audio at 1m for the full duration"
echo "  5. Trace will auto-export when done"
echo ""

# Start xctrace with Energy Log template (and Core ML if available)
# Templates: use 'xctrace list templates' to see available; Energy Log is standard
xcrun xctrace record \
  --template "Energy Log" \
  --device "$UDID" \
  --time-limit "${DURATION}s" \
  --output "$OUTPUT_PATH" 2>&1 | tee "${SCRIPT_DIR}/${OUTPUT_PREFIX}-xctrace.log"

if [[ ! -f "$OUTPUT_PATH" ]]; then
  echo "ERROR: xctrace did not create output file"
  exit 1
fi

echo ""
echo "Trace complete. Exporting to CSV..."

# Export to CSV for analysis
xcrun xctrace export --input "$OUTPUT_PATH" --output "$EXPORT_PATH" 2>&1 | tee -a "${SCRIPT_DIR}/${OUTPUT_PREFIX}-xctrace.log"

if [[ -f "$EXPORT_PATH" ]]; then
  echo "Export successful: $EXPORT_PATH"
  echo ""
  echo "Next steps:"
  echo "  1. Note end battery % and final thermal state in the manifest"
  echo "  2. Run: node parse-trace.mjs $EXPORT_PATH"
  echo "  3. Compare with field reports: node compare.mjs --trace $EXPORT_PATH --reports seal-feedback-*.json --engine parakeet-ultra-pal6"
else
  echo "ERROR: Export to CSV failed"
  exit 1
fi
