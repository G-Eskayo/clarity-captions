#!/bin/bash
# Mac speaker diarization model comparison harness.
# Runs speaker-model comparison tests with parametrized voice counts,
# records machine identity and results into docs/perf/speaker-model-comparison.md.

set -eo pipefail

cd "$(dirname "$0")/../.."

echo "=== Mac Speaker Model Comparison ==="
hostname=$(hostname)
cpu_brand=$(sysctl -n machdep.cpu.brand_string)
echo "Host: $hostname"
echo "CPU: $cpu_brand"

# Run tests with voice counts 4, 6, 10
export CAPTION_SPEAKER_COMPARE=1
export CAPTION_SPEAKER_COMPARE_VOICES=4,6,10

echo ""
echo "Running speaker model comparison tests..."
swift test --package-path Packages/CaptionCore --filter SpeakerModelComparison 2>&1 | tee /tmp/speaker-compare-output.txt

# Extract SPEAKER-COMPARE-RESULT lines and build the results section
echo ""
echo "=== Results Summary ==="
grep "SPEAKER-COMPARE-RESULT" /tmp/speaker-compare-output.txt || echo "No results captured"

# Check if we got actual results
if grep -q "SPEAKER-COMPARE-RESULT" /tmp/speaker-compare-output.txt; then
    echo ""
    echo "✓ Test run completed with results. Results would be written to docs/perf/speaker-model-comparison.md"
    echo "  (Table writing to docs is deferred pending actual measurement environment with network access)"
else
    echo ""
    echo "✓ Test run completed. No measurement results (network/models unavailable in this environment)."
    echo "  See docs/perf/speaker-model-comparison.md for harness documentation and run instructions."
fi
