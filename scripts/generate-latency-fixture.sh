#!/bin/bash
set -e

# Generate a deterministic ~20s speech fixture for latency benchmarking.
# Requires macOS say command. Run once to commit the fixture; tests read the committed file.

OUTPUT="Packages/CaptionCore/Tests/CaptionCoreTests/Fixtures/latency-fixture.wav"
mkdir -p "$(dirname "$OUTPUT")"

/usr/bin/say \
  -v Samantha \
  --data-format=LEF32@16000 \
  -o "$OUTPUT" \
  "The quick brown fox jumps over the lazy dog. Now is the time for all good people to come to the aid of their country. She sells seashells by the seashore. Whether the weather be fine or whether the weather be not, whatever the weather, the weather is here. These pretzels are making me thirsty. How much wood would a woodchuck chuck if a woodchuck could chuck wood."

echo "Generated latency fixture at $OUTPUT"
ls -lh "$OUTPUT"
